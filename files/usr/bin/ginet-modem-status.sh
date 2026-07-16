#!/bin/sh
# GiNet Modem Status Script
# Queries the Quectel RM520N-GL modem for IMEI, APN, signal, connection type
# Outputs JSON for LuCI web interface
# 
# Targets: GiNet XE-3000 Puli AX (GL-XE3000) with RM520N-GL modem
# Chipset: MediaTek Filogic

set -e

. /lib/functions.sh

# Configuration
DEVICE_QMI="/dev/cdc-wdm0"
DEVICE_SERIAL="/dev/ttyUSB0"
CONFIG_FILE="/etc/config/ginet_modem"
STATUS_FILE="/tmp/ginet_modem_status.json"
LOG_FILE="/var/log/ginet_modem.log"

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

# Get IMEI from UCI config first, then try modem
get_imei() {
	local imei=""
	
	# Try from config file first
	[ -f "$CONFIG_FILE" ] && {
		config_load ginet_modem 2>/dev/null
		config_get imei settings imei
	}
	
	# If not set, try to query modem
	if [ -z "$imei" ] && [ -c "$DEVICE_QMI" ]; then
		imei=$(timeout 3 uqmi -d "$DEVICE_QMI" --get-device-serial 2>/dev/null | tr -d '"' || true)
	fi
	
	# Fallback: try AT command on serial device
	if [ -z "$imei" ] && [ -c "$DEVICE_SERIAL" ]; then
		imei=$(timeout 2 sh -c "echo 'AT+CGSN' > $DEVICE_SERIAL; sleep 1; cat $DEVICE_SERIAL" 2>/dev/null | grep -oE '[0-9]{15}' | head -1 || true)
	fi
	
	echo "${imei:-N/A}"
}

# Get APN from config
get_apn() {
	local apn=""
	
	[ -f "$CONFIG_FILE" ] && {
		config_load ginet_modem 2>/dev/null
		config_get apn settings apn
	}
	
	# Fallback: check network config
	if [ -z "$apn" ]; then
		apn=$(uci -q get network.wwan.apn 2>/dev/null || echo "")
	fi
	
	echo "${apn:-internet}"
}

# Get signal strength in dBm
get_signal_strength() {
	local signal=""
	
	if [ -c "$DEVICE_QMI" ]; then
		signal=$(timeout 3 uqmi -d "$DEVICE_QMI" --get-signal-info 2>/dev/null | grep -oP '"rssi":\s*\K-?\d+' | head -1 || true)
	fi
	
	echo "${signal:-N/A}"
}

# Get connection type (5G, 4G, etc.)
get_connection_type() {
	local connection="Disconnected"
	local network_type=""
	
	if [ -c "$DEVICE_QMI" ]; then
		# Get serving system info (5G, LTE, etc.)
		local sys_info=$(timeout 3 uqmi -d "$DEVICE_QMI" --get-serving-system 2>/dev/null || true)
		
		# Check for 5G
		echo "$sys_info" | grep -q "nr5g.*true" && connection="5G NR (NSA)" && return 0
		echo "$sys_info" | grep -q "5gnr.*true" && connection="5G NR (SA)" && return 0
		
		# Check for 4G/LTE
		echo "$sys_info" | grep -q "lte.*true" && connection="4G LTE" && return 0
		
		# Try alternative: get network type
		network_type=$(echo "$sys_info" | grep -oP '"registration":\s*"\K[^"]+' | head -1 || true)
		
		case "$network_type" in
			*"5g"*|*"nr"*) connection="5G NR" ;;
			*"lte"*|*"4g"*) connection="4G LTE" ;;
			*"3g"*|*"umts"*) connection="3G UMTS" ;;
			*) connection="Searching..." ;;
		esac
	fi
	
	echo "$connection"
}

# Get data connection status
get_data_status() {
	local status="Disconnected"
	
	if [ -c "$DEVICE_QMI" ]; then
		local data_status=$(timeout 3 uqmi -d "$DEVICE_QMI" --get-data-status 2>/dev/null | grep -oP '"current":\s*"\K[^"]+' || true)
		
		if echo "$data_status" | grep -q "connected"; then
			status="Connected"
		elif echo "$data_status" | grep -q "disconnected"; then
			status="Disconnected"
		fi
	fi
	
	echo "$status"
}

# Get SIM status
get_sim_status() {
	local sim_status=""
	
	if [ -c "$DEVICE_QMI" ]; then
		sim_status=$(timeout 3 uqmi -d "$DEVICE_QMI" --get-sim-status 2>/dev/null | grep -oP '"status":\s*"\K[^"]+' || true)
	fi
	
	echo "${sim_status:-Unknown}"
}

# Main function
main() {
	local modem_device=$(detect_modem_device)
	
	# If no device found, return error state
	if [ -z "$modem_device" ]; then
		cat <<EOF
{
  "status": "error",
  "message": "Modem device not found",
  "device": "Not detected",
  "imei": "N/A",
  "apn": "Not configured",
  "signal": "N/A",
  "signal_unit": "dBm",
  "connection_type": "No device",
  "data_status": "Disconnected",
  "sim_status": "N/A",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
		return 1
	fi
	
	# Query all modem information
	local imei=$(get_imei)
	local apn=$(get_apn)
	local signal=$(get_signal_strength)
	local connection=$(get_connection_type)
	local data_status=$(get_data_status)
	local sim_status=$(get_sim_status)
	
	# Output JSON status
	cat <<EOF
{
  "status": "ok",
  "device": "$modem_device",
  "imei": "$imei",
  "apn": "$apn",
  "signal": "$signal",
  "signal_unit": "dBm",
  "connection_type": "$connection",
  "data_status": "$data_status",
  "sim_status": "$sim_status",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

# Background loop mode: continuously update status
if [ "$1" = "daemon" ] || [ -z "$1" ]; then
	# If called with 'daemon' or no args, run continuously
	if [ "$1" = "daemon" ]; then
		while true; do
			main > "$STATUS_FILE" 2>/dev/null
			sleep 60
		done
	else
		# Single execution (for testing or manual calls)
		main
	fi
else
	# Argument provided: run specific function
	case "$1" in
		imei) get_imei ;;
		apn) get_apn ;;
		signal) get_signal_strength ;;
		connection) get_connection_type ;;
		status) get_data_status ;;
		sim) get_sim_status ;;
		*) main ;;
	esac
fi
