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
  - Per-tunnel MTU normalization and optional obfuscation (see below)
  - **Adaptive VPN watchdog** — only reconnects/fails over the VPN when the
    underlying link degrades past a sustained threshold, using hysteresis
    (consecutive bad samples) and a cooldown so it does not flap

- **Stealth / Privacy page**
  - **TTL / hop-limit normalization** — rewrites outbound TTL to a fixed value
    so traffic appears to originate from a single device
  - **WAN MTU pinning** — blends traffic profiles / avoids fragmentation fingerprints
  - **MAC randomization scheduler** — per-interface (AP + client/STA) with modes
    `off`, `on-boot`, `on-reconnect`, and `scheduled (interval)`

- **Cell Watch page**
  - Rogue-tower / IMSI-catcher **heuristics**: forced 2G/3G downgrade and
    unexpected serving Cell ID / LAC changes
  - Coarse tower-based location from a **local offline** cell database (opt-in)

- **Performance page**
  - Performance-only tuning that does **not** weaken any security/hardening
    control. All options are opt-in and default to off:
    - **TCP MSS clamping** to the path MTU — fixes silent fragmentation /
      black-holing that tanks throughput on cellular + WireGuard links
    - **Bufferbloat control (SQM)** — applies a fair-queueing discipline
      (`fq_codel` by default, or `cake`/`fq`/`sfq`) on the WAN device
    - **Flow offload** (software, with optional hardware) — raises NAT
      throughput. **Fail-closed**: it self-disables whenever a kill-switch is
      configured or TTL normalization is active, since those controls must
      inspect every packet
  - The default WireGuard tunnel MTU is now `1420` (instead of blank) to avoid
    per-packet fragmentation on typical cellular links

- **Built-in Terminal page**
  - Admin-only LuCI page
  - Controlled PTY execution (`script` + timeout)
  - Command safety policy blocks chaining/injection operators

## Stealth / Privacy — What It Does and Does Not Do

These controls reduce **common, passive** fingerprinting vectors. They do **not**
make you invisible, and none of them can guarantee that a carrier or observer
cannot identify tethering, the device, or its location.

- **TTL normalization** defeats the most common *passive* tethering check, but
  carriers can also use DPI, radio-access-type usage patterns, and traffic
  volume heuristics. This "reduces common detection," it does not make tethering
  undetectable.
- **MAC randomization** of the AP BSSID disconnects connected clients at each
  rotation, so `on-boot` is the recommended AP mode. Client/STA interfaces can
  rotate more aggressively.
- **Cell Watch is heuristic, not proof.** True IMSI-catcher detection needs raw
  baseband / full neighbor-cell data that most modems do not expose over QMI.
  What it reliably flags is the classic forced 2G/3G downgrade and unexpected
  Cell ID / LAC changes. Treat alerts as hints.
- **Location** is coarse (hundreds of metres to kilometres) and resolved from a
  **local offline CSV database only** (`mcc,mnc,lac,cid,lat,lon`) so cell
  identifiers are never sent to the network. It shows roughly what the network
  side can infer about your position — it is not GPS.
- **WireGuard obfuscation** is opt-in and only works if the same obfuscator
  (e.g. `udp2raw`) is installed here **and** configured identically on the VPN
  server. The UI is gated on the obfuscator binary being present at runtime.


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
