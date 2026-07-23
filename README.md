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
- `INSTALL.txt` (LuCI upload + `opkg` install instructions)
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

The APK artifact is produced by a post-build conversion step that runs only after
successful IPK creation and validation. It uses the pinned converter fork
`DomainDevelop/openwrt-ipk2apk` to convert each generated IPK into APK v2 format.

### Install offline on the router

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

Optionally verify integrity first with `sha256sum -c SHA256SUMS`.

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
