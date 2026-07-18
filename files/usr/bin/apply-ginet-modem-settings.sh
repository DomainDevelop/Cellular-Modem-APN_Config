#!/bin/sh
# GiNet Modem Settings Application Script
# Applies the active cellular/APN profile from UCI to OpenWrt network settings.

set -e

. /lib/functions.sh

DEVICE_QMI="/dev/cdc-wdm0"
DEVICE_SERIAL="/dev/ttyUSB0"
CONFIG_NAME="ginet_modem"
NETWORK_CONFIG="network"
LOG_FILE="/var/log/ginet_modem_apply.log"

log_msg() {
	mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

have_command() {
	command -v "$1" >/dev/null 2>&1
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

ensure_defaults() {
	uci -q get ginet_modem.settings >/dev/null 2>&1 || uci set ginet_modem.settings='modem'
	uci -q get ginet_modem.sim1 >/dev/null 2>&1 || uci set ginet_modem.sim1='apn'
	uci -q get ginet_modem.sim2 >/dev/null 2>&1 || uci set ginet_modem.sim2='apn'
	uci -q get ginet_modem.settings.enabled >/dev/null 2>&1 || uci set ginet_modem.settings.enabled='1'
	uci -q get ginet_modem.settings.allow_imei_edit >/dev/null 2>&1 || uci set ginet_modem.settings.allow_imei_edit='1'
	uci -q get ginet_modem.settings.imei_scope >/dev/null 2>&1 || uci set ginet_modem.settings.imei_scope='global'
	uci -q get ginet_modem.settings.active_slot >/dev/null 2>&1 || uci set ginet_modem.settings.active_slot='sim1'
	uci -q get ginet_modem.settings.profile_to_edit >/dev/null 2>&1 || uci set ginet_modem.settings.profile_to_edit='sim1'
	uci -q get ginet_modem.settings.network_mode >/dev/null 2>&1 || uci set ginet_modem.settings.network_mode='auto'
	uci -q get ginet_modem.settings.supported_network_modes >/dev/null 2>&1 || uci set ginet_modem.settings.supported_network_modes='auto,5g,4g,3g,2g'
	uci -q get ginet_modem.sim1.name >/dev/null 2>&1 || uci set ginet_modem.sim1.name='SIM 1'
	uci -q get ginet_modem.sim1.apn >/dev/null 2>&1 || uci set ginet_modem.sim1.apn='internet'
	uci -q get ginet_modem.sim1.apn_protocol >/dev/null 2>&1 || uci set ginet_modem.sim1.apn_protocol='ipv4v6'
	uci -q get ginet_modem.sim1.apn_roaming_protocol >/dev/null 2>&1 || uci set ginet_modem.sim1.apn_roaming_protocol='ipv4v6'
	uci -q get ginet_modem.sim1.network_type >/dev/null 2>&1 || uci set ginet_modem.sim1.network_type='auto'
	uci -q get ginet_modem.sim2.name >/dev/null 2>&1 || uci set ginet_modem.sim2.name='SIM 2'
	uci -q get ginet_modem.sim2.apn >/dev/null 2>&1 || uci set ginet_modem.sim2.apn='internet'
	uci -q get ginet_modem.sim2.apn_protocol >/dev/null 2>&1 || uci set ginet_modem.sim2.apn_protocol='ipv4v6'
	uci -q get ginet_modem.sim2.apn_roaming_protocol >/dev/null 2>&1 || uci set ginet_modem.sim2.apn_roaming_protocol='ipv4v6'
	uci -q get ginet_modem.sim2.network_type >/dev/null 2>&1 || uci set ginet_modem.sim2.network_type='auto'
	uci commit ginet_modem
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

send_at_command() {
	local device="$1"
	local command="$2"

	[ -c "$device" ] || return 1

	if have_command gcom; then
		printf '%s\n' "$command" | gcom -d "$device" 2>&1 || true
	else
		sh -c "printf '%s\\r' \"$command\" > '$device'; sleep 1; head -n 5 '$device'" 2>/dev/null || true
	fi
}

get_active_slot() {
	case "$(uci_get_value settings active_slot)" in
		sim2) echo "sim2" ;;
		*) echo "sim1" ;;
	esac
}

get_profile_value() {
	local value
	value="$(uci_get_value "$1" "$2")"
	if [ -n "$value" ]; then
		echo "$value"
	else
		echo "$3"
	fi
}

get_effective_network_mode() {
	local slot value
	slot="$1"
	value="$(uci_get_value "$slot" network_type)"
	if [ -n "$value" ] && [ "$value" != "auto" ]; then
		echo "$value"
	else
		echo "$(get_config_value settings network_mode auto)"
	fi
}

update_legacy_uci_from_args() {
	local slot="$1"
	local apn="$2"
	local imei="$3"
	local username="$4"
	local ******

	[ -n "$apn" ] && uci set ginet_modem."$slot".apn="$apn"
	[ -n "$imei" ] && uci set ginet_modem.settings.imei="$imei"
	[ -n "$username" ] && uci set ginet_modem."$slot".username="$username"
	[ -n "$password" ] && uci set ginet_modem."$slot".******
	uci commit ginet_modem
}

apply_imei_at() {
	local imei="$1"
	local device="$2"
	local allow_edit

	allow_edit="$(get_config_value settings allow_imei_edit 1)"
	[ "$allow_edit" = "1" ] || {
		log_msg "IMEI editing disabled by configuration"
		return 0
	}

	[ -n "$imei" ] && [ "$imei" != "N/A" ] || return 0
	case "$imei" in
		*[!0-9]*|??????????????|????????????????*)
			log_msg "Skipping IMEI update because the value is not exactly 15 digits"
			return 0
			;;
	esac

	[ -c "$device" ] || {
		log_msg "Skipping IMEI update because no serial modem control device is available"
		return 0
	}

	for cmd in "AT+CGSN=$imei" "AT+QCFGEXT=\"shadow_imei\",$imei"; do
		log_msg "Sending IMEI AT command: $cmd"
		response="$(send_at_command "$device" "$cmd")"
		log_msg "IMEI modem response: ${response:-no response}"
	done
}

apply_network_mode_at() {
	local mode="$1"
	local device="$2"
	local at_value=""

	case "$mode" in
		auto) at_value="AUTO" ;;
		5g) at_value="NR5G" ;;
		4g) at_value="LTE" ;;
		3g) at_value="WCDMA" ;;
		2g) at_value="GSM" ;;
		1g|"") return 0 ;;
		*)
			log_msg "Skipping unsupported network mode request: $mode"
			return 0
			;;
	esac

	[ -c "$device" ] || {
		log_msg "Skipping network mode change because no serial modem control device is available"
		return 0
	}

	response="$(send_at_command "$device" "AT+QNWPREFCFG=\"mode_pref\",$at_value")"
	log_msg "Network mode response for $mode: ${response:-no response}"
}

apply_profile_to_network_config() {
	local slot="$1"
	local apn="$2"
	local username="$3"
	local ******
	local protocol="$5"

	uci -q get "$NETWORK_CONFIG.wwan" >/dev/null 2>&1 || uci set "$NETWORK_CONFIG.wwan=interface"
	uci set "$NETWORK_CONFIG.wwan.proto=qmi"
	uci set "$NETWORK_CONFIG.wwan.device=$DEVICE_QMI"
	uci set "$NETWORK_CONFIG.wwan.apn=${apn:-internet}"
	uci set "$NETWORK_CONFIG.wwan.pdptype=${protocol:-ipv4v6}"
	uci set "$NETWORK_CONFIG.wwan.metric=10"

	if [ -n "$username" ] || [ -n "$password" ]; then
		uci set "$NETWORK_CONFIG.wwan.auth=both"
		uci set "$NETWORK_CONFIG.wwan.username=$username"
		uci set "$NETWORK_CONFIG.wwan.******"
	else
		uci set "$NETWORK_CONFIG.wwan.auth=none"
		uci -q delete "$NETWORK_CONFIG.wwan.username"
		uci -q delete "$NETWORK_CONFIG.wwan.password"
	fi

	uci commit "$NETWORK_CONFIG"
	log_msg "Updated network.wwan from $slot profile"
}

apply_ttl() {
	local ttl="$1"

	[ -n "$ttl" ] || {
		log_msg "TTL is empty; leaving TTL rules unchanged"
		return 0
	}

	case "$ttl" in
		*[!0-9]*|0)
			log_msg "Ignoring invalid TTL value: $ttl"
			return 0
			;;
	esac

	if have_command iptables; then
		while iptables -t mangle -D POSTROUTING -j TTL --ttl-set "$ttl" >/dev/null 2>&1; do :; done
		if iptables -t mangle -A POSTROUTING -j TTL --ttl-set "$ttl" >/dev/null 2>&1; then
			log_msg "Applied TTL via iptables: $ttl"
			return 0
		fi
	fi

	if have_command nft; then
		nft add table inet ginet_modem >/dev/null 2>&1 || true
		nft add chain inet ginet_modem postrouting '{ type filter hook postrouting priority mangle; policy accept; }' >/dev/null 2>&1 || true
		handles="$(nft -a list chain inet ginet_modem postrouting 2>/dev/null | sed -n 's/.*handle \([0-9][0-9]*\)$/\1/p')"
		for handle in $handles; do
			nft delete rule inet ginet_modem postrouting handle "$handle" >/dev/null 2>&1 || true
		done
		nft add rule inet ginet_modem postrouting ip ttl set "$ttl" comment 'ginet-modem-ttl' >/dev/null 2>&1 || true
		nft add rule inet ginet_modem postrouting ip6 hoplimit set "$ttl" comment 'ginet-modem-ttl' >/dev/null 2>&1 || true
		log_msg "Applied TTL via nft: $ttl"
		return 0
	fi

	log_msg "No supported firewall tooling found for TTL application"
}

reload_network() {
	if [ -x /etc/init.d/network ]; then
		/etc/init.d/network reload >/dev/null 2>&1 || log_msg "Network reload returned a non-zero status"
	fi
}

update_status_file() {
	if [ -x /usr/bin/ginet-modem-status.sh ]; then
		/usr/bin/ginet-modem-status.sh > /tmp/ginet_modem_status.json 2>/dev/null || true
	fi
}

main() {
	local slot enabled apn imei username password protocol network_mode ttl modem_device

	ensure_defaults
	slot="$(get_active_slot)"

	if [ $# -gt 0 ] && [ "$1" != "--from-uci" ]; then
		update_legacy_uci_from_args "$slot" "$1" "$2" "$3" "$4"
	fi

	enabled="$(get_config_value settings enabled 1)"
	apn="$(get_profile_value "$slot" apn internet)"
	imei="$(uci_get_value settings imei)"
	username="$(get_profile_value "$slot" username '')"
	******$slot" password '')"
	protocol="$(get_profile_value "$slot" apn_protocol ipv4v6)"
	network_mode="$(get_effective_network_mode "$slot")"
	ttl="$(uci_get_value settings ttl)"
	modem_device="$(detect_modem_device)"

	log_msg "Applying modem settings for slot=$slot apn=$apn mode=$network_mode ttl=${ttl:-unset}"

	apply_profile_to_network_config "$slot" "$apn" "$username" "$password" "$protocol"

	if [ "$enabled" = "1" ]; then
		if [ -n "$modem_device" ] && [ -c "$DEVICE_SERIAL" ]; then
			apply_imei_at "$imei" "$DEVICE_SERIAL"
			apply_network_mode_at "$network_mode" "$DEVICE_SERIAL"
		else
			log_msg "No modem control device available; persisted settings only"
		fi
		apply_ttl "$ttl"
		reload_network
	else
		log_msg "Cellular modem is disabled; persisted settings without modem actions"
	fi

	update_status_file
}

main "$@"
exit $?
