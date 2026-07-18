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
- installable package(s) (`.ipk` on OpenWrt 24.10, `.apk` on OpenWrt 25.12)
- `SHA256SUMS`
- `INSTALL.txt` (LuCI upload + `opkg`/`apk` install instructions)

The build targets the XE-3000 class **`mediatek/filogic` (`aarch64_cortex-a53`)** on the
newest supported OpenWrt releases: **24.10.7** (primary, `.ipk`) and **25.12.5** (`.apk`).
Because the package is `PKGARCH:=all`, the resulting package is portable across
`mediatek/filogic` devices of the same release that provide the listed dependencies.

### Get the package from the Actions tab

1. Open a completed run of **Build OpenWrt Package** (triggered by push, PR, or a
   manual **Run workflow**).
2. Download the artifact named like:
   - `openwrt-ipk-24.10.7-xe3000` (contains `luci-app-ginet-cellmodem_*.ipk`)
   - `openwrt-apk-25.12.5-xe3000` (contains `luci-app-ginet-cellmodem-*.apk`)
3. Extract it. You will get the package file, `SHA256SUMS`, and
   `INSTALL.txt`.

### Install offline on the router

**Option A — LuCI web upload (no SSH needed):**
1. Log in to LuCI as admin.
2. Go to **System → Software**.
3. Click **Upload Package...**, choose the `.ipk`, and confirm.

**Option B — `opkg` (24.10) or `apk` (25.12) over SSH / USB:**
```sh
# copy the package to the router (scp or USB), then on OpenWrt 24.10:
opkg install /tmp/luci-app-ginet-cellmodem_*.ipk
# if dependencies are missing and the router has internet:
opkg update && opkg install /tmp/luci-app-ginet-cellmodem_*.ipk

# on OpenWrt 25.12 (apk):
apk add --allow-untrusted /tmp/luci-app-ginet-cellmodem-*.apk
```

Optionally verify integrity first with `sha256sum -c SHA256SUMS`.

The workflow also validates the generated package format before upload (`.ipk`:
`debian-binary`, `control.tar.*`, `data.tar.*`; `.apk`: gzip integrity), so the
downloaded artifact matches router package requirements.

## Local Build (OpenWrt SDK)

```sh
# inside OpenWrt SDK root: stage this repo as a package and build it
mkdir -p package/luci-app-ginet-cellmodem
rsync -a --exclude '.git' --exclude '.github' \
  /path/to/Cellular-Modem-APN_Config/ package/luci-app-ginet-cellmodem/
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
