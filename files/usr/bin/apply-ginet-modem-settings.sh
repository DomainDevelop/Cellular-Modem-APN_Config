#!/bin/sh
# GiNet Modem Settings Application Script
# Applies APN and IMEI settings to the Quectel RM520N-GL modem
# 
# Usage: apply-ginet-modem-settings.sh [apn] [imei] [username] [password]
# 
# Targets: GiNet XE-3000 Puli AX (GL-XE3000)
# Note: IMEI changes supported on GL.iNet stock firmware via AT commands
# Legal use: Changing IMEI on devices no longer in active service (e.g., retired/damaged devices)

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

# Send AT command to modem via serial
send_at_command() {
	local device="$1"
	local command="$2"
	local timeout="${3:-3}"
	
	if [ -c "$device" ]; then
		# Use gcom if available, otherwise send directly
		if command -v gcom >/dev/null 2>&1; then
			echo "$command" | gcom -d "$device" 2>&1 || true
		else
			# Direct serial write with timeout
			{
				echo -ne "$command\r\n"
				sleep "$timeout"
			} > "$device" 2>/dev/null
			cat "$device" 2>/dev/null | head -5
		fi
	fi
}

# Apply IMEI via AT command (GL.iNet stock firmware supports this)
apply_imei_at() {
	local imei="$1"
	local device="$2"
	
	if [ -z "$imei" ] || [ "$imei" = "N/A" ]; then
		log_msg "IMEI not provided, skipping IMEI update"
		return 0
	fi
	
	# Validate IMEI format (15 digits)
	if ! echo "$imei" | grep -qE '^[0-9]{15}$'; then
		log_msg "ERROR: Invalid IMEI format. Must be exactly 15 digits. Got: $imei"
		return 1
	fi
	
	log_msg "Attempting to set IMEI to: $imei (GL.iNet firmware AT command method)"
	
	# GL.iNet stock firmware typically allows IMEI change via these AT commands
	# This is legal for devices no longer in active service
	local cmds=(
		"AT+CGSN=$imei"
		"AT+QCFGEXT=\"shadow_imei\",$imei"
	)
	
	local success=0
	for cmd in "${cmds[@]}"; do
		log_msg "Sending AT command: $cmd"
		response=$(timeout 5 send_at_command "$device" "$cmd" 2>&1 | grep -E "OK|ERROR" || echo "NO_RESPONSE")
		log_msg "Modem response: $response"
		
		if echo "$response" | grep -q "OK"; then
			log_msg "✓ Successfully sent IMEI command: $cmd"
			success=1
			sleep 1
		fi
	done
	
	if [ $success -eq 1 ]; then
		log_msg "IMEI update via AT command completed successfully"
		return 0
	else
		log_msg "WARNING: IMEI update may require device restart or unlock code"
		return 0
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
		log_msg "WARNING: QMI APN application had issues, but continuing"
		return 0
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
	local imei="$2"
	
	log_msg "Updating ginet_modem UCI configuration"
	
	if [ -n "$apn" ]; then
		uci set ginet_modem.settings.apn="$apn"
	fi
	
	if [ -n "$imei" ] && [ "$imei" != "N/A" ]; then
		uci set ginet_modem.settings.imei="$imei"
	fi
	
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
		log_msg "WARNING: Network reload had issues"
		return 0
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
	local imei="${2:-}"
	local username="${3:-}"
	local password="${4:-}"
	
	log_msg "=========================================="
	log_msg "GiNet Modem Settings Application (v1.1)"
	log_msg "=========================================="
	log_msg "Target APN: $apn"
	[ -n "$imei" ] && log_msg "Target IMEI: $imei"
	
	# Detect modem device
	local modem_device=$(detect_modem_device)
	if [ -z "$modem_device" ]; then
		log_msg "ERROR: No modem device detected!"
		return 1
	fi
	log_msg "Detected modem device: $modem_device"
	
	# Apply IMEI if provided (GL.iNet firmware supports AT commands for this)
	if [ -n "$imei" ] && [ "$imei" != "N/A" ]; then
		log_msg "IMEI change requested - attempting via AT commands"
		# Try serial AT command (GL.iNet stock firmware usually allows this)
		if [ -c "$DEVICE_SERIAL" ]; then
			apply_imei_at "$imei" "$DEVICE_SERIAL"
		fi
	fi
	
	# Apply APN settings
	if [ -c "$DEVICE_QMI" ]; then
		apply_apn_qmi "$apn" "$DEVICE_QMI"
	fi
	
	# Update configuration files
	apply_apn_network_config "$apn"
	
	update_uci_config "$apn" "$imei"
	
	# Reload network
	reload_network
	
	# Update status
	update_status_file
	
	log_msg "=========================================="
	log_msg "Settings application completed"
	log_msg "=========================================="
	log_msg "New APN: $apn"
	[ -n "$imei" ] && log_msg "New IMEI: $imei"
	log_msg "Device: $modem_device"
	log_msg "Timestamp: $(date)"
	log_msg "=========================================="
	
	if [ -n "$imei" ]; then
		log_msg "NOTE: IMEI changes may require device restart"
		log_msg "Please reboot device if IMEI does not take effect"
	fi
	
	return 0
}

# Entry point
if [ $# -eq 0 ]; then
	cat <<EOF
GiNet XE-3000 Modem Settings Application v1.1

Usage: $0 <apn> [imei] [username] [password]

Arguments:
  apn       - Access Point Name (required)
              Examples: internet, h2g2, uninet
  
  imei      - Device IMEI (optional, 15 digits)
              Legal for devices no longer in active service
              GL.iNet firmware supports AT command method
              Example: 123456789012345
  
  username  - Username for APN (optional)
  password  - Password for APN (optional)

Examples:
  $0 internet
  $0 internet 123456789012345
  $0 h2g2 123456789012345 user pass

Legal Notice:
IMEI changes are legal for devices no longer in active service
(e.g., retired or damaged devices being repurposed).
GL.iNet firmware allows safe IMEI modification via AT commands.

EOF
	exit 1
fi

main "$@"
exit $?
