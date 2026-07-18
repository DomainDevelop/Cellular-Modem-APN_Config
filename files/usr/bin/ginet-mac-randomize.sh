#!/bin/sh
# MAC randomization scheduler.
#
# Modes (per macrand section):
#   off          - no randomization
#   on-boot      - randomize once, at boot
#   on-reconnect - randomize when the interface link comes up
#   scheduled    - randomize every interval_minutes (driven by cron)
#
# AP (wifi) interfaces are handled through UCI wireless (option macaddr) so the
# change survives wifi reloads; STA / plain interfaces are set directly with ip.
# Randomizing an AP BSSID drops connected clients, so callers should prefer
# on-boot for the AP.

set -eu

# Generate a locally-administered, unicast random MAC.
#   - second-least-significant bit of the first octet set (locally administered)
#   - least-significant bit of the first octet cleared (unicast)
random_mac() {
	hexrand() {
		# Prefer the kernel RNG; fall back to awk if unavailable.
		if [ -r /dev/urandom ]; then
			od -An -N1 -tu1 /dev/urandom | tr -d ' '
		else
			awk 'BEGIN{srand();print int(rand()*256)}'
		fi
	}
	first=$(( $(hexrand) ))
	first=$(( (first & 0xFC) | 0x02 ))
	printf '%02x:%02x:%02x:%02x:%02x:%02x' \
		"$first" "$(hexrand)" "$(hexrand)" "$(hexrand)" "$(hexrand)" "$(hexrand)"
}

uci_get() {
	uci -q get "ginet_modem.$1" 2>/dev/null || echo "${2:-}"
}

# Find the wireless iface UCI section whose ifname matches, if any.
wifi_section_for() {
	target="$1"
	found=""
	for s in $(uci -q show wireless 2>/dev/null | sed -n "s/^wireless\.\([^.]*\)=wifi-iface$/\1/p"); do
		ifn=$(uci -q get "wireless.$s.ifname" 2>/dev/null || true)
		if [ "$ifn" = "$target" ]; then
			found="$s"
			break
		fi
	done
	echo "$found"
}

randomize_iface() {
	section="$1"
	ifname=$(uci_get "$section.ifname")
	[ -n "$ifname" ] || return 0
	mac=$(random_mac)

	wsec=$(wifi_section_for "$ifname")
	if [ -n "$wsec" ]; then
		uci set "wireless.$wsec.macaddr=$mac"
		uci commit wireless
		wifi reload >/dev/null 2>&1 || /sbin/wifi up >/dev/null 2>&1 || true
		logger -t ginet-mac "Randomized wifi $ifname ($section) -> $mac"
	elif [ -d "/sys/class/net/$ifname" ]; then
		ip link set dev "$ifname" down 2>/dev/null || true
		ip link set dev "$ifname" address "$mac" 2>/dev/null || \
			logger -t ginet-mac "Failed to set MAC on $ifname"
		ip link set dev "$ifname" up 2>/dev/null || true
		logger -t ginet-mac "Randomized $ifname ($section) -> $mac"
	fi
}

process_section() {
	section="$1"
	trigger="$2"
	mode=$(uci_get "$section.mode" off)
	case "$mode" in
		off) return 0 ;;
		on-boot)      [ "$trigger" = "boot" ] && randomize_iface "$section" ;;
		on-reconnect) [ "$trigger" = "reconnect" ] && randomize_iface "$section" ;;
		scheduled)    [ "$trigger" = "scheduled" ] && randomize_iface "$section" ;;
	esac
}

run() {
	trigger="$1"
	for section in ap sta; do
		[ -n "$(uci -q get "ginet_modem.$section" 2>/dev/null || true)" ] || continue
		process_section "$section" "$trigger"
	done
}

case "${1:-scheduled}" in
	boot) run boot ;;
	reconnect) run reconnect ;;
	scheduled) run scheduled ;;
	now)
		# Force-randomize all configured interfaces regardless of mode.
		for section in ap sta; do
			[ "$(uci_get "$section.mode" off)" = "off" ] || randomize_iface "$section"
		done
		;;
	*) echo "Usage: $0 [boot|reconnect|scheduled|now]" >&2; exit 1 ;;
esac
