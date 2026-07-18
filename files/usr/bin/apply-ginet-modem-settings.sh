#!/bin/sh
# Apply APN settings for cellular modem

set -eu

DEVICE_QMI="/dev/cdc-wdm0"
LOG_FILE="/var/log/ginet_modem_apply.log"

log_msg() {
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

validate_apn() {
	case "$1" in
		""|*[!A-Za-z0-9._-]*) return 1 ;;
	esac
	[ "${#1}" -le 64 ]
}

apply_apn_qmi() {
	apn="$1"
	if [ -c "$DEVICE_QMI" ]; then
		if timeout 5 uqmi -d "$DEVICE_QMI" --set-data-profile --profile="apn=$apn" >> "$LOG_FILE" 2>&1; then
			log_msg "Applied APN via QMI"
		else
			log_msg "QMI APN application failed; continuing with UCI network config"
		fi
	fi
}

apply_apn_network_config() {
	apn="$1"

	if ! uci -q get network.wwan >/dev/null 2>&1; then
		uci set network.wwan="interface"
		uci set network.wwan.proto="qmi"
		uci set network.wwan.device="$DEVICE_QMI"
	fi

	uci set network.wwan.apn="$apn"
	uci -q set network.wwan.pdptype="ipv4v6"
	uci -q set network.wwan.auth="none"
	uci commit network

	uci set ginet_modem.settings.apn="$apn"
	uci set ginet_modem.settings.enabled="1"
	uci commit ginet_modem
}

reload_network() {
	/etc/init.d/network reload >> "$LOG_FILE" 2>&1 || true
}

update_status_file() {
	if [ -x "/usr/bin/ginet-modem-status.sh" ]; then
		/usr/bin/ginet-modem-status.sh > /tmp/ginet_modem_status.json 2>/dev/null || true
	fi
}

main() {
	apn="${1:-}"

	if ! validate_apn "$apn"; then
		echo "Invalid APN. Allowed: letters, numbers, '.', '_' and '-' (max 64 chars)." >&2
		return 1
	fi

	log_msg "Applying APN: $apn"
	apply_apn_qmi "$apn"
	apply_apn_network_config "$apn"
	reload_network
	update_status_file
	log_msg "APN apply complete"
}

if [ "$#" -lt 1 ]; then
	echo "Usage: $0 <apn>" >&2
	exit 1
fi

main "$1"
