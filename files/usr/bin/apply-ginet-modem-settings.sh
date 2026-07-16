#!/bin/sh
# GiNet Modem Settings Application Script
# Applies APN and other settings to the Quectel RM520N-GL modem
# 
# Usage: apply-ginet-modem-settings.sh [apn] [username] [password]
# 
# Targets: GiNet XE-3000 Puli AX (GL-XE3000)

set -e

. /lib/functions.sh

# Configuration
DEVICE_QMI="/dev/cdc-wdm0"
DEVICE_SERIAL="/dev/ttyUSB0"
CONFIG_FILE="/etc/config/ginet_modem"
NETWORK_CONFIG="/etc/config/network"
LOG_FILE="/var/log/ginet_modem_apply.log"

# Function to log messages
log_msg() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Detect actual device
detect_modem_device() {
	if [ -e "$DEVICE_QMI" ]; then
		echo "$DEVICE_QMI"
	elif [ -e "$DEVICE_SERIAL" ]; then
		echo "$DEVICE_SERIAL"
	else
		echo ""
	fi
}

# Apply APN via QMI
apply_apn_qmi() {
	local apn="$1"
	local device="$2"
	
	log_msg "Applying APN '$apn' via QMI device $device"
	
	# Set data profile with APN
	if timeout 5 uqmi -d "$device" --set-data-profile --profile=apn="$apn" 2>&1 | tee -a "$LOG_FILE"; then
		log_msg "Successfully set APN to: $apn"
		return 0
	else
		log_msg "ERROR: Failed to set APN via QMI"
		return 1
	fi
}

# Apply APN to network config
apply_apn_network_config() {
	local apn="$1"
	
	log_msg "Updating network configuration with APN: $apn"
	
	# Check if wwan interface exists
	if ! uci -q get network.wwan >/dev/null 2>&1; then
		log_msg "Creating new WWAN interface"
		uci set network.wwan="interface"
		uci set network.wwan.proto="qmi"
		uci set network.wwan.device="/dev/cdc-wdm0"
	fi
	
	# Update APN
	uci set network.wwan.apn="$apn"
	
	# Optional: set other parameters
	uci -q set network.wwan.pdptype="ipv4v6"
	uci -q set network.wwan.auth="none"
	
	# Commit changes
	uci commit network
	log_msg "Network configuration updated"
	
	return 0
}

# Update UCI config
update_uci_config() {
	local apn="$1"
	
	log_msg "Updating ginet_modem UCI configuration"
	
	uci set ginet_modem.settings.apn="$apn"
	uci set ginet_modem.settings.enabled="1"
	uci commit ginet_modem
	
	log_msg "UCI configuration updated"
}

# Reload network to apply changes
reload_network() {
	log_msg "Reloading network configuration"
	
	if /etc/init.d/network reload 2>&1 | tee -a "$LOG_FILE"; then
		log_msg "Network reloaded successfully"
		return 0
	else
		log_msg "WARNING: Network reload had issues (may not be critical)"
		return 1
	fi
}

# Update modem status file
update_status_file() {
	log_msg "Updating modem status file"
	
	if [ -x "/usr/bin/ginet-modem-status.sh" ]; then
		/usr/bin/ginet-modem-status.sh > /tmp/ginet_modem_status.json 2>/dev/null || true
	fi
}

# Main function
main() {
	local apn="${1:-internet}"
	local username="${2:-}"
	local password="${3:-}"
	
	log_msg "=========================================="
	log_msg "GiNet Modem Settings Application"
	log_msg "=========================================="
	log_msg "Target APN: $apn"
	
	# Detect modem device
	local modem_device=$(detect_modem_device)
	if [ -z "$modem_device" ]; then
		log_msg "ERROR: No modem device detected!"
		return 1
	fi
	log_msg "Detected modem device: $modem_device"
	
	# Apply settings
	if [ -c "$DEVICE_QMI" ]; then
		apply_apn_qmi "$apn" "$DEVICE_QMI" || log_msg "WARNING: QMI APN application had issues"
	fi
	
	# Update configuration files
	apply_apn_network_config "$apn" || {
		log_msg "ERROR: Failed to update network config"
		return 1
	}
	
	update_uci_config "$apn" || {
		log_msg "ERROR: Failed to update UCI config"
		return 1
	}
	
	# Reload network
	reload_network
	
	# Update status
	update_status_file
	
	log_msg "=========================================="
	log_msg "Settings application completed"
	log_msg "=========================================="
	log_msg "New APN: $apn"
	log_msg "Device: $modem_device"
	log_msg "Timestamp: $(date)"
	
	return 0
}

# Entry point
if [ $# -eq 0 ]; then
	log_msg "ERROR: APN parameter required"
	echo "Usage: $0 <apn> [username] [password]"
	echo "Example: $0 internet"
	exit 1
fi

main "$@"
exit $?
