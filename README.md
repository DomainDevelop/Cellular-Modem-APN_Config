# GiNet XE-3000 Puli AX - Cellular Modem Configuration Package

A custom OpenWrt LuCI application for the **GiNet XE-3000 Puli AX** (GL-XE3000) that provides a web interface to display and configure cellular modem settings including IMEI, APN, and connection status.

## Features

✅ **Display Current Modem Status**
- Current IMEI (device identifier)
- Active APN (Access Point Name)
- Signal strength (dBm)
- Connection type (4G LTE / 5G NR)

✅ **Configure Settings**
- Modify APN settings
- View IMEI information
- Enable/disable cellular modem

✅ **Full Hardware Compatibility**
- Quectel RM520N-GL modem support
- MediaTek Filogic chipset optimized
- QMI (Qualcomm MSM Interface) protocol
- Dual SIM card support
- NSA & SA 5G network support

✅ **Clean Web Interface**
- LuCI web UI integration
- Status section (read-only display)
- Configuration section (editable fields)
- Save & Apply functionality

## Device Specifications (GiNet XE-3000 Puli AX)

| Component | Specification |
|-----------|---------------|
| **Modem Chipset** | Quectel RM520N-GL |
| **CPU** | MediaTek Filogic (dual-core @ 1.3 GHz) |
| **Cellular** | 5G NR (NSA/SA) + 4G LTE (dual SIM) |
| **Wi-Fi** | IEEE 802.11ax (Wi-Fi 6), dual-band |
| **WAN** | 10/100/1000/2500 Mbps Gigabit Ethernet |
| **Ports** | MicroSD, USB-A, SMA antennae |
| **Battery** | 6400mAh (portable) |
| **Firmware Base** | OpenWrt 21.02+ / GL.iNet custom build |

## Installation

### Prerequisites

```bash
# SSH into your GiNet XE-3000 device
ssh root@192.168.8.1  # Default GL.iNet address

# Update package lists
opkg update

# Install required dependencies
opkg install uqmi kmod-usb-net-qmi-wwan kmod-usb-serial-option usb-modeswitch luci
```

### Install Package

**Option 1: From this repository**

```bash
# Download the compiled .ipk package
wget https://github.com/DomainDevelop/Cellular-Modem-APN_Config/releases/download/v1.0/luci-app-ginet-cellmodem_1.0-1_all.ipk

# Install
opkg install luci-app-ginet-cellmodem_1.0-1_all.ipk

# Enable and start service
/etc/init.d/ginet-modem enable
/etc/init.d/ginet-modem start
```

**Option 2: Build from source (OpenWrt SDK)**

```bash
# Clone repository
git clone https://github.com/DomainDevelop/Cellular-Modem-APN_Config.git
cd Cellular-Modem-APN_Config

# Place in OpenWrt package directory
cp -r . /path/to/openwrt/package/luci-app-ginet-cellmodem

# Configure and build
cd /path/to/openwrt
./scripts/feeds update -a
./scripts/feeds install luci-app-ginet-cellmodem
make menuconfig  # Select LuCI → Applications → GiNet Cell Modem Configuration
make package/luci-app-ginet-cellmodem/compile V=s
```

## Usage

### Access Web Interface

1. Open browser and navigate to your router:
   - **GL.iNet default:** `http://192.168.8.1`
   - **Custom OpenWrt:** Your router's IP address

2. Log in with admin credentials

3. Navigate to: **Network → Cell Modem** (or **System → Cell Modem** depending on LuCI version)

### Status Display

The interface shows real-time modem information:
- **Current IMEI:** Your device's international mobile equipment identity
- **Current APN:** Configured access point name
- **Signal Strength:** Signal quality in dBm (closer to 0 = stronger)
- **Connection Type:** 5G NR, 4G LTE, or Disconnected

### Configure Settings

Edit the configuration section:

1. **IMEI Field:** Shows your device IMEI (read-only for security)
   - ⚠️ WARNING: Changing IMEI may be illegal in your region

2. **APN Field:** Enter your carrier's APN
   - Common examples: `internet` (AT&T), `h2g2` (T-Mobile), `uninet` (Verizon)
   - Contact your carrier if unsure

3. **Enabled:** Check to enable cellular modem

4. **Save & Apply:** Changes apply immediately

## File Structure

```
luci-app-ginet-cellmodem/
├── Makefile                                          # Package build configuration
├── README.md                                         # This file
├── files/
│   ├── etc/
│   │   ├── config/
│   │   │   └── ginet_modem                          # UCI configuration file
│   │   └── init.d/
│   │       └── ginet-modem                          # Init script for service
│   └── usr/
│       ├── bin/
│       │   ├── ginet-modem-status.sh               # Modem status detection
│       │   └── apply-ginet-modem-settings.sh       # Apply settings to modem
│       └── lib/lua/luci/
│           ├── controller/
│           │   └── ginet_modem.lua                 # LuCI controller
│           └── model/cbi/
│               └── ginet_modem.lua                 # LuCI web interface
```

## Technical Details

### Modem Detection

The package automatically detects your modem interface:
- **Primary:** `/dev/cdc-wdm0` (QMI device, recommended)
- **Fallback:** `/dev/ttyUSB0` (Serial device)

### Status Retrieval

Status is retrieved via:
- `uqmi` commands for QMI modem interface
- `AT+CGSN` for IMEI (if serial interface available)
- Signal info from `/proc/signal` or `uqmi --get-signal-info`

### Settings Application

When you save settings, the package:
1. Updates UCI configuration (`/etc/config/ginet_modem`)
2. Updates network config (`/etc/config/network`)
3. Applies APN via `uqmi --set-data-profile`
4. Reloads network services

### Backend Scripts

**ginet-modem-status.sh**
- Queries modem for IMEI, APN, signal, connection type
- Outputs JSON for web interface
- Runs every 60 seconds (can be configured)

**apply-ginet-modem-settings.sh**
- Takes IMEI and APN as parameters
- Safely applies settings without interrupting connection
- Handles both QMI and serial interfaces

## Troubleshooting

### Modem Not Detected

```bash
# SSH into device
ssh root@192.168.8.1

# Check USB device
lsusb

# Check QMI device nodes
ls -la /dev/cdc-wdm0 /dev/ttyUSB*

# Check dmesg for errors
dmesg | tail -20
```

### Cannot Access Web Interface

```bash
# Ensure LuCI is running
/etc/init.d/uhttpd start
/etc/init.d/uhttpd enable

# Check if service is listening
netstat -tlnp | grep uhttpd
```

### Settings Not Applying

```bash
# Check package installation
opkg list-installed | grep ginet

# Check service status
/etc/init.d/ginet-modem status

# View logs
logread | grep ginet
tail -f /tmp/ginet_modem_status.json
```

### Restore Default Settings

```bash
ssh root@192.168.8.1

# Reset configuration
rm /etc/config/ginet_modem
/etc/init.d/ginet-modem restart

# Or restore via web UI: System → Backup/Restore
```

## Building from Source

### Requirements

- OpenWrt Build System (tested on 21.02+)
- Cross-compiler for your target (MediaTek MT7981 for XE-3000)
- `make`, `git`

### Build Steps

```bash
# Clone OpenWrt
git clone https://github.com/openwrt/openwrt.git openwrt-build
cd openwrt-build
git checkout openwrt-21.02  # or desired version

# Add this package
git clone https://github.com/DomainDevelop/Cellular-Modem-APN_Config.git \
  package/luci-app-ginet-cellmodem

# Configure feeds
./scripts/feeds update -a
./scripts/feeds install -a

# Configure build
make menuconfig

# In menuconfig: 
# - Select Target (MediaTek Filogic for XE-3000)
# - LuCI → Applications → [*] LuCI app - GiNet Cell Modem Configuration

# Build
make -j4

# Find output
ls -lh bin/packages/*/luci/*.ipk | grep ginet
```

## Known Limitations

⚠️ **IMEI Modification:**
- Most production modems (including RM520N-GL) do **not** allow IMEI changes via software
- IMEI is burned into hardware during manufacturing
- This package displays IMEI read-only for legal/security compliance
- **Attempting to change IMEI is illegal in many countries**

⚠️ **Regional Restrictions:**
- Some countries restrict 5G frequencies or modem capabilities
- Check local regulations before use in restricted regions

⚠️ **Carrier Compatibility:**
- Not all carriers support all LTE/5G bands
- Contact your carrier for compatible APN and settings

## Support & Issues

For issues, suggestions, or contributions:

1. **Check existing issues:** [GitHub Issues](https://github.com/DomainDevelop/Cellular-Modem-APN_Config/issues)
2. **Create new issue:** Include:
   - Firmware version (`uname -a`)
   - Error messages (from `logread`)
   - Device model & modem chipset
3. **Submit PR:** Welcome for improvements!

## License

This project is provided as-is for use with GiNet XE-3000 Puli AX routers running OpenWrt.

## References

- [GiNet XE-3000 Product Page](https://www.gl-inet.com/products/gl-xe3000/)
- [Quectel RM520N-GL Documentation](https://www.quectel.com/product/rm520n-gl/)
- [OpenWrt QMI Guide](https://openwrt.org/docs/guide-user/network/wan/wwan/using_qmi_wwan)
- [OpenWrt XE-3000 Techdata](https://openwrt.org/toh/hwdata/gl.inet/gl.inet_gl-xe3000)
- [MediaTek Filogic](https://mediatek.com)

## Contributors

- **DomainDevelop** - Original package author

---

**Last Updated:** July 2026  
**Package Version:** 1.0  
**Compatible Firmware:** OpenWrt 21.02+, GL.iNet custom builds
