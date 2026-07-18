#!/bin/sh
# GiNet Modem Status Script
# Outputs JSON for LuCI and keeps capability checks defensive.

set -e

. /lib/functions.sh

DEVICE_QMI="/dev/cdc-wdm0"
DEVICE_SERIAL="/dev/ttyUSB0"
CONFIG_NAME="ginet_modem"
STATUS_FILE="/tmp/ginet_modem_status.json"

have_command() {
	command -v "$1" >/dev/null 2>&1
}

json_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

uci_get_value() {
	uci -q get "$CONFIG_NAME.$1.$2" 2>/dev/null || true
}

get_config_value() {
	local value
	value="$(uci_get_value "$1" "$2")"
	if [ -n "$value" ]; then
		echo "$value"
	else
		echo "$3"
	fi
}

parse_json_string() {
	printf '%s' "$1" | sed -n "s/.*\"$2\":[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
}

parse_json_number() {
	printf '%s' "$1" | sed -n "s/.*\"$2\":[[:space:]]*\(-*[0-9][0-9]*\).*/\1/p" | head -n 1
}

detect_modem_device() {
	if [ -c "$DEVICE_QMI" ]; then
		echo "$DEVICE_QMI"
	elif [ -c "$DEVICE_SERIAL" ]; then
		echo "$DEVICE_SERIAL"
	else
		echo ""
	fi
}

get_imei() {
	local imei
	imei="$(uci_get_value settings imei)"

	if [ -z "$imei" ] && [ -c "$DEVICE_QMI" ] && have_command uqmi; then
		imei="$(timeout 3 uqmi -d "$DEVICE_QMI" --get-device-serial 2>/dev/null | tr -d '"' | head -n 1 || true)"
	fi

	if [ -z "$imei" ] && [ -c "$DEVICE_SERIAL" ]; then
		imei="$(timeout 3 sh -c "printf 'AT+CGSN\r' > '$DEVICE_SERIAL'; sleep 1; head -n 5 '$DEVICE_SERIAL'" 2>/dev/null | grep -Eo '[0-9]{15}' | head -n 1 || true)"
	fi

	echo "${imei:-N/A}"
}

get_active_slot() {
	case "$(uci_get_value settings active_slot)" in
		sim2) echo "sim2" ;;
		*) echo "sim1" ;;
	esac
}

get_sim_status() {
	local sim_status="Unknown"
	if [ -c "$DEVICE_QMI" ] && have_command uqmi; then
		local output
		output="$(timeout 3 uqmi -d "$DEVICE_QMI" --get-sim-state 2>/dev/null || timeout 3 uqmi -d "$DEVICE_QMI" --get-sim-status 2>/dev/null || true)"
		sim_status="$(parse_json_string "$output" status)"
		[ -n "$sim_status" ] || sim_status="$(parse_json_string "$output" sim_state)"
		[ -n "$sim_status" ] || sim_status="Unknown"
	fi
	echo "$sim_status"
}

get_sim_inserted() {
	case "$(get_sim_status)" in
		*ready*|*Ready*|*pin*|*PIN*|*locked*|*Locked*) echo "Yes" ;;
		*absent*|*Absent*|*missing*|*Missing*|"N/A") echo "No" ;;
		*) echo "Unknown" ;;
	esac
}

get_carrier() {
	local carrier="Unknown"
	if [ -c "$DEVICE_QMI" ] && have_command uqmi; then
		local output
		output="$(timeout 3 uqmi -d "$DEVICE_QMI" --get-home-network 2>/dev/null || true)"
		carrier="$(parse_json_string "$output" description)"
		if [ -z "$carrier" ]; then
			output="$(timeout 3 uqmi -d "$DEVICE_QMI" --get-serving-system 2>/dev/null || true)"
			carrier="$(parse_json_string "$output" description)"
		fi
	fi
	echo "${carrier:-Unknown}"
}

get_signal_strength() {
	local signal=""
	if [ -c "$DEVICE_QMI" ] && have_command uqmi; then
		local output
		output="$(timeout 3 uqmi -d "$DEVICE_QMI" --get-signal-info 2>/dev/null || true)"
		signal="$(parse_json_number "$output" rssi)"
	fi
	echo "${signal:-N/A}"
}

get_connection_type() {
	local connection="Disconnected"
	if [ -c "$DEVICE_QMI" ] && have_command uqmi; then
		local output
		output="$(timeout 3 uqmi -d "$DEVICE_QMI" --get-serving-system 2>/dev/null || true)"
		case "$output" in
			*nr5g*true*|*5gnr*true*) connection="5G NR" ;;
			*lte*true*) connection="4G LTE" ;;
			*umts*true*|*wcdma*true*) connection="3G UMTS" ;;
			*gsm*true*) connection="2G GSM" ;;
			*registered*) connection="Registered" ;;
		esac
	fi
	echo "$connection"
}

get_data_status() {
	local status="Disconnected"
	if [ -c "$DEVICE_QMI" ] && have_command uqmi; then
		local output current
		output="$(timeout 3 uqmi -d "$DEVICE_QMI" --get-data-status 2>/dev/null || true)"
		current="$(parse_json_string "$output" current)"
		case "$current" in
			*connected*) status="Connected" ;;
			*connecting*) status="Connecting" ;;
			*disconnected*) status="Disconnected" ;;
		esac
	fi
	echo "$status"
}

get_preferred_network_mode() {
	local slot value
	slot="$(get_active_slot)"
	value="$(uci_get_value "$slot" network_type)"
	[ -n "$value" ] || value="$(uci_get_value settings network_mode)"
	echo "${value:-auto}"
}

get_supported_network_modes() {
	local modes
	modes="$(uci_get_value settings supported_network_modes)"
	if [ -z "$modes" ]; then
		if [ -c "$DEVICE_SERIAL" ]; then
			modes="auto,5g,4g,3g,2g"
		else
			modes="auto"
		fi
	fi
	echo "$modes"
}

get_imei_scope() {
	echo "$(get_config_value settings imei_scope global)"
}

get_imei_editable() {
	local allow_edit
	allow_edit="$(get_config_value settings allow_imei_edit 1)"
	if [ "$allow_edit" = "1" ] && [ -c "$DEVICE_SERIAL" ]; then
		echo "1"
	else
		echo "0"
	fi
}

get_active_profile_name() {
	local slot
	slot="$(get_active_slot)"
	echo "$(get_config_value "$slot" name "$slot")"
}

get_apn() {
	local slot apn
	slot="$(get_active_slot)"
	apn="$(uci_get_value "$slot" apn)"
	[ -n "$apn" ] || apn="$(uci_get_value settings apn)"
	echo "${apn:-internet}"
}

main() {
	local modem_device imei apn signal connection data_status sim_status sim_inserted carrier
	local active_slot preferred_mode supported_modes imei_scope imei_editable active_profile

	modem_device="$(detect_modem_device)"
	imei="$(get_imei)"
	apn="$(get_apn)"
	signal="$(get_signal_strength)"
	connection="$(get_connection_type)"
	data_status="$(get_data_status)"
	sim_status="$(get_sim_status)"
	sim_inserted="$(get_sim_inserted)"
	carrier="$(get_carrier)"
	active_slot="$(get_active_slot)"
	preferred_mode="$(get_preferred_network_mode)"
	supported_modes="$(get_supported_network_modes)"
	imei_scope="$(get_imei_scope)"
	imei_editable="$(get_imei_editable)"
	active_profile="$(get_active_profile_name)"

	cat <<EOF_JSON
{
  "status": "ok",
  "device": "$(json_escape "${modem_device:-Not detected}")",
  "imei": "$(json_escape "$imei")",
  "apn": "$(json_escape "$apn")",
  "carrier": "$(json_escape "$carrier")",
  "signal": "$(json_escape "$signal")",
  "signal_unit": "dBm",
  "connection_type": "$(json_escape "$connection")",
  "data_status": "$(json_escape "$data_status")",
  "sim_status": "$(json_escape "$sim_status")",
  "sim_inserted": "$(json_escape "$sim_inserted")",
  "active_slot": "$(json_escape "$active_slot")",
  "active_profile": "$(json_escape "$active_profile")",
  "preferred_network_mode": "$(json_escape "$preferred_mode")",
  "supported_network_modes": "$(json_escape "$supported_modes")",
  "imei_scope": "$(json_escape "$imei_scope")",
  "imei_editable": "$(json_escape "$imei_editable")",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF_JSON
}

if [ "$1" = "daemon" ]; then
	while true; do
		main > "$STATUS_FILE" 2>/dev/null || true
		sleep 60
	done
else
	main
fi
