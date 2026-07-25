#!/usr/bin/env python3
"""
sign_apk.py — Sign an OpenWrt/Alpine APK v2 package (ECDSA P-256 / SHA-1).

APK v2 ECDSA signing algorithm:
  1. Split the unsigned APK into its two gzip streams: control and data.
     The control stream covers .PKGINFO and install scripts; data covers package
     files.  The converter (openwrt-ipk2apk.py) produces exactly this two-stream
     layout.
  2. Compute SHA-1 over the raw control gzip stream bytes (including the gzip
     header, compressed deflate data, CRC-32 and ISIZE trailer).
  3. Sign the 20-byte SHA-1 digest with the EC private key.  The output is a
     DER-encoded ECDSA signature.
  4. Build a minimal gzip-compressed tar segment containing one file:
       .SIGN.ECDSA.<key-name>.ecdsa.pub
     whose content is the DER signature bytes.  The tar EOF null-blocks are
     stripped so the segment chains cleanly with the following control stream
     in the APK container (identical technique to the converter).
  5. Write  sig_block || control_gz || data_gz  as the signed APK.

  apk-tools looks for /etc/apk/keys/<key-name>.ecdsa.pub on the device to
  verify the signature.  Distribute the PEM public key derived from the same
  private key so users can copy it there once.

Usage:
  python3 sign_apk.py --key private.pem --key-name NAME [--pubkey out.pub] \\
      INPUT [OUTPUT]

  --key     Path to PEM EC private key, or '-' to read from stdin.
  --key-name  Key name embedded in the signature file name and used by apk-tools
              to look up the matching public key in /etc/apk/keys/.
  --pubkey  Optional: write the PEM-encoded public key to this path.
  INPUT     Unsigned .apk file (two-stream: control + data).
  OUTPUT    Signed .apk output path.  Defaults to overwriting INPUT.
"""

import argparse
import gzip
import hashlib
import io
import struct
import sys
import tarfile
import zlib


def split_first_gzip_stream(data: bytes):
    """Return (first_stream_bytes, rest_bytes) by parsing the gzip header and
    deflate stream of the first gzip member in *data*.

    The gzip format has a fixed 10-byte header followed by optional fields
    (FEXTRA, FNAME, FCOMMENT, FHCRC), then raw deflate-compressed data, then
    a 4-byte CRC-32 and a 4-byte ISIZE footer.  zlib.decompressobj with a
    negative window-bits value decompresses raw deflate and stops at the
    end-of-stream marker, leaving any trailing bytes in .unused_data.
    """
    if len(data) < 2 or data[:2] != b"\x1f\x8b":
        raise ValueError("Data does not begin with gzip magic bytes (0x1f 0x8b)")

    flg = data[3]
    pos = 10  # fixed header length

    if flg & 4:  # FEXTRA
        if pos + 2 > len(data):
            raise ValueError("Truncated gzip FEXTRA length field")
        xlen = struct.unpack_from("<H", data, pos)[0]
        pos += 2 + xlen

    if flg & 8:  # FNAME (null-terminated)
        while pos < len(data) and data[pos] != 0:
            pos += 1
        pos += 1

    if flg & 16:  # FCOMMENT (null-terminated)
        while pos < len(data) and data[pos] != 0:
            pos += 1
        pos += 1

    if flg & 2:  # FHCRC
        pos += 2

    # Decompress the raw deflate stream.  Stops at the deflate end-of-stream
    # marker; remaining bytes (CRC-32 + ISIZE + next gzip stream) go into
    # .unused_data.
    dec = zlib.decompressobj(-zlib.MAX_WBITS)
    try:
        dec.decompress(data[pos:])
    except zlib.error as exc:
        raise ValueError(f"Deflate decompression failed: {exc}") from exc

    # Position right after the compressed data = start of the 8-byte footer
    footer_start = len(data) - len(dec.unused_data)
    stream_end = footer_start + 8  # skip CRC-32 (4) + ISIZE (4)

    if stream_end > len(data):
        raise ValueError("Truncated gzip stream: footer extends past end of data")

    return data[:stream_end], data[stream_end:]


def make_signature_gz(signature_bytes: bytes, key_name: str) -> bytes:
    """Build the APK v2 signature block: a gzip-compressed tar containing a
    single file named .SIGN.ECDSA.<key_name>.ecdsa.pub whose content is the
    DER-encoded ECDSA signature.

    The tar EOF null-blocks are stripped before gzip compression so the block
    chains correctly with the control stream that follows it in the APK
    container (same technique used by openwrt-ipk2apk.py for the control tar).
    """
    sig_filename = f".SIGN.ECDSA.{key_name}.ecdsa.pub"

    tar_buf = io.BytesIO()
    with tarfile.open(fileobj=tar_buf, mode="w", format=tarfile.GNU_FORMAT) as tar:
        info = tarfile.TarInfo(sig_filename)
        info.size = len(signature_bytes)
        info.uid = 0
        info.gid = 0
        info.uname = "root"
        info.gname = "root"
        info.mode = 0o644
        tar.addfile(info, io.BytesIO(signature_bytes))
        # Capture valid offset BEFORE tarfile.close() appends the two 512-byte
        # EOF null-blocks (identical pattern to the converter script).
        valid_len = tar.offset

    tar_bytes_no_eof = tar_buf.getvalue()[:valid_len]

    gz_buf = io.BytesIO()
    with gzip.GzipFile(fileobj=gz_buf, mode="wb", mtime=0) as gz:
        gz.write(tar_bytes_no_eof)
    return gz_buf.getvalue()


def sign_apk(apk_bytes: bytes, private_key_pem: bytes, key_name: str) -> bytes:
    """Sign an unsigned APK v2 and return the signed APK bytes.

    The APK v2 ECDSA signature covers the raw bytes of the control gzip stream
    (the first of the two streams produced by openwrt-ipk2apk.py).  The
    signature is computed with ECDSA using SHA-1 as the digest, and the result
    is DER-encoded.

    To avoid SHA-1 usage warnings from the cryptography library (which treats
    SHA-1 as legacy for signing), we compute the SHA-1 digest ourselves using
    hashlib and then sign the pre-computed 20-byte digest with Prehashed().
    This is semantically identical to ECDSA-SHA1 but bypasses the library's
    deprecation guard.
    """
    try:
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.hazmat.primitives.asymmetric.utils import Prehashed
    except ImportError as exc:
        print(
            f"[!] Missing dependency: {exc}\n"
            "    Install it with:  pip3 install cryptography",
            file=sys.stderr,
        )
        sys.exit(1)

    control_gz, data_gz = split_first_gzip_stream(apk_bytes)

    private_key = serialization.load_pem_private_key(private_key_pem, password=None)

    # APK v2 ECDSA: sign SHA-1(control_gz) with the EC private key.
    sha1_digest = hashlib.sha1(control_gz).digest()  # 20 bytes
    signature = private_key.sign(
        sha1_digest,
        ec.ECDSA(Prehashed(hashes.SHA1())),
    )

    sig_gz = make_signature_gz(signature, key_name)
    return sig_gz + control_gz + data_gz


def export_public_key_pem(private_key_pem: bytes) -> bytes:
    """Derive and return the PEM-encoded public key from a PEM private key."""
    from cryptography.hazmat.primitives import serialization

    priv = serialization.load_pem_private_key(private_key_pem, password=None)
    return priv.public_key().public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )


def main():
    ap = argparse.ArgumentParser(
        description="Sign an OpenWrt APK v2 package with ECDSA P-256 / SHA-1.",
        epilog=(
            "The public key must be placed at /etc/apk/keys/<key-name>.ecdsa.pub "
            "on the target router for apk-tools to trust the signature."
        ),
    )
    ap.add_argument("input", help="Unsigned .apk file (control + data streams)")
    ap.add_argument(
        "output",
        nargs="?",
        help="Signed .apk output path (default: overwrite input)",
    )
    ap.add_argument(
        "--key",
        required=True,
        metavar="FILE",
        help="PEM EC private key file, or '-' to read from stdin",
    )
    ap.add_argument(
        "--key-name",
        required=True,
        metavar="NAME",
        help=(
            "Key identifier embedded in the signature file name inside the APK "
            "and used by apk-tools to locate the matching public key in "
            "/etc/apk/keys/<key-name>.ecdsa.pub"
        ),
    )
    ap.add_argument(
        "--pubkey",
        metavar="FILE",
        help="Write the PEM-encoded EC public key to this file",
    )
    args = ap.parse_args()

    # Load private key
    if args.key == "-":
        private_key_pem = sys.stdin.buffer.read()
    else:
        with open(args.key, "rb") as fh:
            private_key_pem = fh.read()

    # Load unsigned APK
    with open(args.input, "rb") as fh:
        apk_bytes = fh.read()

    # Sign
    signed_bytes = sign_apk(apk_bytes, private_key_pem, args.key_name)

    # Write signed APK
    out_path = args.output or args.input
    with open(out_path, "wb") as fh:
        fh.write(signed_bytes)

    added = len(signed_bytes) - len(apk_bytes)
    print(
        f"[+] Signed APK written: {out_path}  "
        f"({len(signed_bytes)} bytes, +{added} bytes signature block)"
    )

    # Optionally export public key
    if args.pubkey:
        pub_pem = export_public_key_pem(private_key_pem)
        with open(args.pubkey, "wb") as fh:
            fh.write(pub_pem)
        print(f"[+] Public key written: {args.pubkey}")
        print(
            f"    Copy to router:  scp {args.pubkey} "
            f"root@<ROUTER_IP>:/etc/apk/keys/{args.key_name}.ecdsa.pub"
        )


if __name__ == "__main__":
    main()
