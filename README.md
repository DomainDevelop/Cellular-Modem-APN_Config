# GiNet Cellular Modem + WireGuard Control (Alpha)

LuCI package for OpenWrt/XE-3000 that combines:
- Cellular APN management
- Per-SIM WireGuard policy controls
- Admin-only built-in terminal (controlled PTY execution)

> Version: `v0.2.0-alpha.1`

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

## Actions Artifact (Exact Installable Package Output)

The workflow builds with the OpenWrt SDK target profile and uploads the generated installable `.ipk` and `SHA256SUMS` as artifacts.

From **Actions** tab:
1. Open a completed run of **Build OpenWrt Package**.
2. Download artifact named like:
   - `luci-app-ginet-cellmodem_23.05.5_xe3000_aarch64_cortex-a53`
3. Extract and install on router:

```sh
opkg install luci-app-ginet-cellmodem_0.2.0-alpha.1-1_all.ipk
```

This artifact is produced by the same OpenWrt package build flow used to generate router-installable package files.

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
