#!/bin/sh
# Apply stealth/privacy network mitigations:
#   - TTL / hop-limit normalization (reduces common tethering detection)
#   - WAN MTU pinning (blends traffic profiles)
#
# These reduce common passive fingerprinting vectors. They do NOT guarantee
# that a carrier or observer cannot identify tethering, the device, or its
# location.

set -eu

TTL_NFT_FILE="/etc/nftables.d/98-ginet-stealth.nft"

uci_get() {
	uci -q get "ginet_modem.$1" 2>/dev/null || echo "${2:-}"
}

enabled() {
	[ "$(uci_get "$1" 0)" = "1" ]
}

wan_ifname() {
	# Prefer the L3 device backing the wan interface; fall back to wwan/wan.
	ifname=$(uci -q get network.wan.device 2>/dev/null || true)
	[ -n "$ifname" ] || ifname=$(uci -q get network.wan.ifname 2>/dev/null || true)
	[ -n "$ifname" ] || ifname=$(uci -q get network.wwan.device 2>/dev/null || true)
	echo "${ifname:-wan}"
}

apply_ttl() {
	if enabled "settings.ttl_normalize"; then
		ttl=$(uci_get "settings.ttl_value" 65)
		case "$ttl" in
			''|*[!0-9]*) ttl=65 ;;
		esac
		if [ "$ttl" -lt 1 ] || [ "$ttl" -gt 255 ]; then
			ttl=65
		fi
		mkdir -p /etc/nftables.d
		cat > "$TTL_NFT_FILE" <<EOFNFT
# Managed by ginet-stealth.sh - normalize outbound TTL/hop-limit.
chain mangle_postrouting_ginet_ttl {
	type filter hook postrouting priority mangle; policy accept;
	ip ttl set $ttl
	ip6 hoplimit set $ttl
}
EOFNFT
	else
		rm -f "$TTL_NFT_FILE"
	fi
	/etc/init.d/firewall reload >/dev/null 2>&1 || true
}

apply_mtu() {
	mtu=$(uci_get "settings.wan_mtu" 0)
	case "$mtu" in
		''|*[!0-9]*) mtu=0 ;;
	esac
	[ "$mtu" -gt 0 ] || return 0
	if [ "$mtu" -lt 576 ] || [ "$mtu" -gt 9000 ]; then
		logger -t ginet-stealth "Ignoring out-of-range wan_mtu=$mtu"
		return 0
	fi
	ifname=$(wan_ifname)
	if [ -n "$ifname" ] && [ -d "/sys/class/net/$ifname" ]; then
		ip link set dev "$ifname" mtu "$mtu" 2>/dev/null || \
			logger -t ginet-stealth "Failed to set MTU $mtu on $ifname"
	fi
}

apply() {
	apply_ttl
	apply_mtu
}

case "${1:-apply}" in
	apply|boot) apply ;;
	ttl) apply_ttl ;;
	mtu) apply_mtu ;;
	*) echo "Usage: $0 [apply|boot|ttl|mtu]" >&2; exit 1 ;;
esac
