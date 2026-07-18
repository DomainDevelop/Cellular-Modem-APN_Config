#!/bin/sh
# Query modem status and emit JSON for LuCI

set -eu

. /lib/functions.sh

DEVICE_QMI="/dev/cdc-wdm0"
DEVICE_SERIAL="/dev/ttyUSB0"
CONFIG_FILE="/etc/config/ginet_modem"
STATUS_FILE="/tmp/ginet_modem_status.json"

json_escape() {
	echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

detect_modem_device() {
	if [ -e "$DEVICE_QMI" ]; then
		echo "$DEVICE_QMI"
	elif [ -e "$DEVICE_SERIAL" ]; then
		echo "$DEVICE_SERIAL"
	else
		echo ""
	fi
}

get_imei() {
	imei=""
	if [ -f "$CONFIG_FILE" ]; then
		config_load ginet_modem 2>/dev/null || true
		config_get imei settings imei
	fi
	if [ -z "$imei" ] && [ -c "$DEVICE_QMI" ]; then
		imei=$(timeout 3 uqmi -d "$DEVICE_QMI" --get-device-serial 2>/dev/null | tr -d '"' || true)
	fi
	if [ -z "$imei" ] && [ -c "$DEVICE_SERIAL" ]; then
		imei=$(timeout 2 sh -c "echo 'AT+CGSN' > $DEVICE_SERIAL; sleep 1; cat $DEVICE_SERIAL" 2>/dev/null | grep -Eo '[0-9]{15}' | head -1 || true)
	fi
	echo "${imei:-N/A}"
}

get_apn() {
	apn=""
	if [ -f "$CONFIG_FILE" ]; then
		config_load ginet_modem 2>/dev/null || true
		config_get apn settings apn
	fi
	if [ -z "$apn" ]; then
		apn=$(uci -q get network.wwan.apn 2>/dev/null || echo "")
	fi
	echo "${apn:-internet}"
}

extract_json_string() {
	key="$1"
	printf '%s' "$2" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

extract_json_number() {
	key="$1"
	printf '%s' "$2" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\(-\?[0-9]\+\).*/\1/p" | head -1
}

get_signal_strength() {
	signal=""
	if [ -c "$DEVICE_QMI" ]; then
		info=$(timeout 3 uqmi -d "$DEVICE_QMI" --get-signal-info 2>/dev/null || true)
		signal=$(extract_json_number rssi "$info")
	fi
	echo "${signal:-N/A}"
}

get_connection_type() {
	connection="Disconnected"
	if [ -c "$DEVICE_QMI" ]; then
		sys_info=$(timeout 3 uqmi -d "$DEVICE_QMI" --get-serving-system 2>/dev/null || true)
		echo "$sys_info" | grep -q "nr5g.*true" && echo "5G NR (NSA)" && return 0
		echo "$sys_info" | grep -q "5gnr.*true" && echo "5G NR (SA)" && return 0
		echo "$sys_info" | grep -q "lte.*true" && echo "4G LTE" && return 0
		registration=$(extract_json_string registration "$sys_info")
		case "$registration" in
			*5g*|*nr*) connection="5G NR" ;;
			*lte*|*4g*) connection="4G LTE" ;;
			*3g*|*umts*) connection="3G UMTS" ;;
			*) connection="Searching..." ;;
		esac
	fi
	echo "$connection"
}

get_data_status() {
	status="Disconnected"
	if [ -c "$DEVICE_QMI" ]; then
		data_status=$(timeout 3 uqmi -d "$DEVICE_QMI" --get-data-status 2>/dev/null || true)
		current=$(extract_json_string current "$data_status")
		if echo "$current" | grep -qi "connected"; then
			status="Connected"
		fi
	fi
	echo "$status"
}

get_sim_status() {
	sim_status=""
	if [ -c "$DEVICE_QMI" ]; then
		resp=$(timeout 3 uqmi -d "$DEVICE_QMI" --get-sim-status 2>/dev/null || true)
		sim_status=$(extract_json_string status "$resp")
	fi
	echo "${sim_status:-Unknown}"
}

main() {
	modem_device=$(detect_modem_device)
	if [ -z "$modem_device" ]; then
		cat <<EOFJSON
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
EOFJSON
		return 1
	fi

	imei=$(json_escape "$(get_imei)")
	apn=$(json_escape "$(get_apn)")
	signal=$(json_escape "$(get_signal_strength)")
	connection=$(json_escape "$(get_connection_type)")
	data_status=$(json_escape "$(get_data_status)")
	sim_status=$(json_escape "$(get_sim_status)")
	device=$(json_escape "$modem_device")

	cat <<EOFJSON
{
  "status": "ok",
  "device": "$device",
  "imei": "$imei",
  "apn": "$apn",
  "signal": "$signal",
  "signal_unit": "dBm",
  "connection_type": "$connection",
  "data_status": "$data_status",
  "sim_status": "$sim_status",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOFJSON
}

if [ "${1:-}" = "daemon" ]; then
	while true; do
		main > "$STATUS_FILE" 2>/dev/null || true
		sleep 60
	done
elif [ -z "${1:-}" ]; then
	main
else
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
