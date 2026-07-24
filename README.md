# GiNet Cellular Modem + WireGuard Control (Alpha)

LuCI package for OpenWrt/XE-3000 that combines:
- Cellular APN management
- Per-SIM WireGuard policy controls
- Admin-only built-in terminal (controlled PTY execution)

> Version channel: `0.2.0` (alpha track)

## Security Positioning

This package implements best-practice hardening feasible on OpenWrt/LuCI (strict input validation, privilege boundaries, fail-closed firewall policy, secure update staging where possible). It does **not** claim literal GrapheneOS parity due to different platform and threat model.

## Main Features

- **Cell Modem page**
  - APN configuration
  - Status display (IMEI/APN/signal/connection/SIM)
  - Input sanitization and safer status rendering

- **Cellular VPN page**
  - SIM1/SIM2 VPN controls
  - Per-SIM toggles:
    - Enable VPN
    - Auto-update WireGuard (24h cron check)
    - Always-on VPN
    - Block connections without VPN (kill-switch)
  - WireGuard tunnel configuration list
  - One active tunnel enforced per SIM

- **Built-in Terminal page**
  - Admin-only LuCI page
  - Controlled PTY execution (`script` + timeout)
  - Command safety policy blocks chaining/injection operators

## Actions Artifact (Router-Installable Package Output)

The **Build OpenWrt Package** workflow (`.github/workflows/build-openwrt-package.yml`)
compiles this repo with the official OpenWrt SDK and uploads an artifact containing:
- installable `.ipk` package(s)
- `SHA256SUMS`
- `INSTALL.txt` (explains when to use `.ipk` vs `.apk`, plus offline install commands)
- converted `.apk` package(s) generated from the built `.ipk` files
- APK `SHA256SUMS`

The build defaults to the XE-3000 class target: **OpenWrt 23.05.5, `mediatek/filogic`
(`aarch64_cortex-a53`)**. Because the package is `PKGARCH:=all`, the resulting `.ipk`
is portable across OpenWrt 23.05.x devices that provide the listed dependencies.

### Get the package from the Actions tab

1. Open a completed run of **Build OpenWrt Package** (triggered by push, PR, or a
   manual **Run workflow**).
2. Download the artifact named like:
   - `openwrt-ipk-luci-app-ginet-cellmodem_0.2.0-r1_all.ipk`
   - `apk-packages-xe3000`
3. Extract it. You will get `luci-app-ginet-cellmodem_*.ipk`, `SHA256SUMS`, and
   `INSTALL.txt`.
4. For APK output, open `apk-packages-*` to get `*.apk` plus its `SHA256SUMS`.
5. Read `INSTALL.txt` before uploading anything; it tells you which package format matches
   your firmware and explains unsigned APK behavior.

The APK artifact is produced by a post-build conversion step that runs only after
successful IPK creation and validation. It uses the pinned converter fork
`DomainDevelop/openwrt-ipk2apk` to convert each generated IPK into APK v2 format.

### Install offline on the router

#### OpenWrt 23.05.x and older (`opkg`)

**Option A — LuCI web upload (no SSH needed):**
1. Log in to LuCI as admin.
2. Go to **System → Software**.
3. Click **Upload Package...**, choose the `.ipk`, and confirm.

**Option B — `opkg` over SSH / USB:**
```sh
# copy the .ipk to the router (scp or USB), then:
opkg install /tmp/luci-app-ginet-cellmodem_*.ipk
# if dependencies are missing and the router has internet:
opkg update && opkg install /tmp/luci-app-ginet-cellmodem_*.ipk
```

#### OpenWrt 25.12.x and newer (`apk`) — trusted install

The signing key pair for this repository has been generated.  The **public key**
is committed at [`keys/domaindevelop-cellmodem.ecdsa.pub`](keys/domaindevelop-cellmodem.ecdsa.pub).
Once the matching `APK_SIGNING_KEY` secret is added (see below), every CI build
will produce signed APKs and include the same public key in the artifact.

**One-time router setup — copy the public key once (USB or SSH/Ethernet):**

*Over Ethernet (SSH/SCP):*
```sh
# from your laptop in the same LAN
scp keys/domaindevelop-cellmodem.ecdsa.pub root@<ROUTER_IP>:/etc/apk/keys/
```

*Via USB (no network needed):*
```
1. Copy keys/domaindevelop-cellmodem.ecdsa.pub to a USB stick.
2. Plug the USB stick into the router.
3. SSH into the router (or use the built-in terminal page), then:
   mount /dev/sda1 /mnt  # or whichever device your USB appears as
   cp /mnt/domaindevelop-cellmodem.ecdsa.pub /etc/apk/keys/
   umount /mnt
```

**Install the signed APK:**

*Over Ethernet (SSH/SCP):*
```sh
scp luci-app-ginet-cellmodem_*.apk root@<ROUTER_IP>:/tmp/
ssh root@<ROUTER_IP> "apk add --no-network /tmp/luci-app-ginet-cellmodem_*.apk"
```

*Via USB (no network needed):*
```
1. Copy the .apk to a USB stick.
2. Plug it into the router, mount it, then:
   apk add --no-network /mnt/luci-app-ginet-cellmodem_*.apk
   umount /mnt
```

After the public key is trusted once, future updates only require copying and
installing the new `.apk` — no need to copy the key again.

**If `APK_SIGNING_KEY` is not yet configured (unsigned build)**, install with:
```sh
apk add --no-network --allow-untrusted /tmp/luci-app-ginet-cellmodem_*.apk
```

#### Setting up APK package signing (one-time secret setup)

The key pair has already been generated. You only need to register the private key
as a GitHub Actions secret so CI can sign every build automatically:

1. Copy the private key PEM shown in the PR that introduced the `keys/` directory.
2. Go to the repository **Settings → Secrets and variables → Actions**.
3. Click **New repository secret**.
4. Name: **`APK_SIGNING_KEY`**
5. Value: paste the full `-----BEGIN EC PRIVATE KEY-----` … `-----END EC PRIVATE KEY-----` block.
6. Click **Add secret**.
7. Trigger a new build (push a commit or click **Actions → Build OpenWrt Package → Run workflow**).
8. Download the `apk-packages-xe3000` artifact — it will contain the signed `.apk`
   and `domaindevelop-cellmodem.ecdsa.pub` (identical to the file in `keys/`).

- If LuCI shows **No packages** or `packages.adb` download warnings, fix router
  network / DNS / firewall / NTP first; apk repository indexes are not loading.

Optionally verify package integrity before installing: `sha256sum -c SHA256SUMS`.

The workflow also validates the generated `.ipk` format (`debian-binary`,
`control.tar.*`, `data.tar.*`) before upload, so the downloaded artifact matches
router package requirements.

## Local Build (OpenWrt SDK)

```sh
# inside OpenWrt SDK root
printf 'src-link custom /path/to/Cellular-Modem-APN_Config\n' > feeds.conf.default
./scripts/feeds update -a
./scripts/feeds install -a
make defconfig
make package/luci-app-ginet-cellmodem/compile V=s
```

## Notes / Limitations

- Kill-switch behavior is fail-closed for WAN egress when configured and applied.
- WireGuard auto-update staging uses `opkg` availability on target firmware.
- Terminal is intentionally restricted and not a full unrestricted shell.

## Package Dependencies

- Base LuCI/app runtime: `luci-base`, `libuci-lua`, `libubox`, `uqmi`, `kmod-usb-net-qmi-wwan`
- VPN/WireGuard: `wireguard-tools`, `kmod-wireguard`, `kmod-crypto-lib-chacha20poly1305`, `kmod-crypto-lib-curve25519`
