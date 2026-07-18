# GiNet XE-3000 Puli AX - Cellular Modem Configuration Package

A custom OpenWrt LuCI application for **GL.iNet XE-3000 (Puli AX)** focused on two things:

- a clear **Cellular** section for modem status and active modem controls
- a persistent **APNs** section for editing SIM profile data even when a slot is inactive

## Highlights

- **Cellular** section shows modem device, SIM inserted/status, carrier, signal, current connection, active SIM slot, current IMEI, preferred network mode, and TTL.
- **APNs** section keeps two editable SIM profiles with these fields:
  - Name
  - APN
  - Proxy
  - Port
  - Username
  - Password
  - Server
  - APN type
  - MMSC
  - MMS Proxy
  - APN Protocol
  - APN Roaming Protocol
  - Network Type
- **Capability-aware IMEI UX**:
  - Only one IMEI is shown when the modem/backend exposes a shared modem IMEI.
  - IMEI editing is only shown when a writable serial control path is detected.
  - Unsupported per-SIM IMEI switching is not presented as a working feature.
- **Per-slot persistence** through UCI (`/etc/config/ginet_modem`) with the active slot applied to `network.wwan`.
- **Downloadable IPK workflow** for practical OpenWrt SDK targets relevant to XE-3000 / Filogic.

## LuCI navigation

After installation, open **Network → Cellular**.

### Cellular section

Use this section to:

- inspect live modem status
- choose the active SIM/profile (`sim1` or `sim2`)
- review the IMEI currently in use
- edit IMEI only when supported by the modem/backend
- choose the preferred network generation from advertised options (`Auto`, `5G`, `4G`, `3G`, `2G`, `1G` if a backend ever exposes it)
- persist a TTL override

### APNs section

Each SIM profile stays editable even when inactive. The active profile is highlighted, but both profiles remain available for manual preparation and testing.

The active profile is applied by `/usr/bin/apply-ginet-modem-settings.sh` to `network.wwan` so standard OpenWrt networking can use the selected APN settings.

## Files and configuration

Key files:

- `/etc/config/ginet_modem` - package UCI state
- `/usr/bin/ginet-modem-status.sh` - defensive modem status collector
- `/usr/bin/apply-ginet-modem-settings.sh` - applies the active profile to network/UCI/runtime settings
- `/usr/lib/lua/luci/model/cbi/ginet_modem.lua` - LuCI UI
- `.github/workflows/main.yml` - IPK build workflow

Example UCI layout:

```uci
config modem 'settings'
	option enabled '1'
	option active_slot 'sim1'
	option network_mode 'auto'
	option supported_network_modes 'auto,5g,4g,3g,2g'
	option imei_scope 'global'
	option ttl ''

config apn 'sim1'
	option name 'SIM 1'
	option apn 'internet'
	...

config apn 'sim2'
	option name 'SIM 2'
	option apn 'internet'
	...
```

## Build and download workflow

The GitHub Actions workflow builds downloadable `.ipk` artifacts directly from the OpenWrt SDK.

### Workflow targets

Currently configured targets:

- **OpenWrt 23.05.5 / mediatek-filogic** - primary XE-3000 relevant build
- **OpenWrt 22.03.7 / mediatek-filogic** - compatibility build for older practical releases

### How to download the package artifact

1. Open the **Actions** tab in GitHub.
2. Run **Build OpenWrt Package** manually or use artifacts from a push/PR run.
3. Download the artifact named like:
   - `luci-app-ginet-cellmodem-23.05.5-mediatek-filogic`
4. Extract the artifact and install the included `.ipk` on the router with `opkg install`.

Each uploaded artifact also includes a `build-info.txt` file with the OpenWrt version, target, and SDK URL used for the build.

## Installation on router

```sh
opkg update
opkg install luci-app-ginet-cellmodem_1.1-1_all.ipk
/etc/init.d/ginet-modem enable
/etc/init.d/ginet-modem restart
```

## Validation notes

- Shell scripts are written to stay compatible with BusyBox `/bin/sh`.
- The UI tolerates missing modem devices and missing live modem data.
- APN values persist in UCI even if the currently edited slot is inactive.
- Runtime IMEI/network-mode changes depend on modem/backend support and are intentionally hidden or reduced when unsupported.

## Known limitations

- XE-3000 deployments typically expose **one modem IMEI shared across SIM slots**, not truly separate per-SIM IMEIs.
- Direct runtime IMEI and preferred-network-mode changes depend on the modem serial control path and modem firmware support.
- TTL application is best-effort and depends on available firewall tooling (`iptables` or `nft`).
- Only APN/auth/protocol data is pushed into `network.wwan`; MMS/proxy-style fields are preserved in UCI for manual carrier-specific workflows.
