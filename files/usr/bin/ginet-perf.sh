#!/bin/sh
# Apply performance-only tuning for the cellular + WireGuard data path:
#   - TCP MSS clamping to the path MTU (fixes fragmentation/black-holing that
#     tanks throughput on cellular + WireGuard links)
#   - fq_codel / SQM queueing discipline on the WAN device (fights bufferbloat)
#   - software (and optional hardware) flow offload for higher NAT throughput
#
# NONE of these weaken the security/hardening controls. Flow offload is
# FAIL-CLOSED: it self-disables whenever a kill-switch is configured or TTL
# normalization is active, because those controls must see every packet.

set -eu

MSS_NFT_FILE="/etc/nftables.d/97-ginet-perf-mss.nft"
OFFLOAD_NFT_FILE="/etc/nftables.d/96-ginet-perf-offload.nft"

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

lan_ifname() {
	ifname=$(uci -q get network.lan.device 2>/dev/null || true)
	[ -n "$ifname" ] || ifname=$(uci -q get network.lan.ifname 2>/dev/null || true)
	echo "${ifname:-br-lan}"
}

# The kill-switch and TTL normalization rely on netfilter seeing every packet.
# Offloaded flows bypass those hooks, so refuse to offload while either is
# active. This keeps hardening intact ("fail closed").
offload_would_conflict() {
	enabled "settings.ttl_normalize" && return 0
	for section in sim1 sim2; do
		if [ "$(uci_get "$section.vpn_enabled" 0)" = "1" ] && \
		   [ "$(uci_get "$section.block_without_vpn" 0)" = "1" ]; then
			return 0
		fi
	done
	return 1
}

reload_firewall() {
	/etc/init.d/firewall reload >/dev/null 2>&1 || true
}

apply_mss() {
	if enabled "settings.mss_clamp"; then
		mkdir -p /etc/nftables.d
		cat > "$MSS_NFT_FILE" <<'EOFNFT'
# Managed by ginet-perf.sh - clamp TCP MSS to the path MTU (PMTU) so cellular +
# WireGuard links do not silently fragment/black-hole large segments.
chain forward_ginet_mss {
	type filter hook forward priority mangle + 1; policy accept;
	tcp flags syn tcp option maxseg size set rt mss
}
EOFNFT
	else
		rm -f "$MSS_NFT_FILE"
	fi
}

apply_offload() {
	# Remove first so a disabled/conflicting state never leaves a stale rule.
	rm -f "$OFFLOAD_NFT_FILE"

	enabled "settings.flow_offloading" || return 0

	if offload_would_conflict; then
		logger -t ginet-perf \
			"Flow offload disabled: kill-switch or TTL normalization is active (fail-closed)"
		return 0
	fi

	wan=$(wan_ifname)
	lan=$(lan_ifname)
	# Only offload across devices that actually exist to avoid a broken ruleset.
	[ -d "/sys/class/net/$wan" ] || { logger -t ginet-perf "WAN device '$wan' missing; skipping offload"; return 0; }
	[ -d "/sys/class/net/$lan" ] || { logger -t ginet-perf "LAN device '$lan' missing; skipping offload"; return 0; }

	ft_flags=""
	if enabled "settings.flow_offloading_hw"; then
		ft_flags="	flags offload;"
	fi

	mkdir -p /etc/nftables.d
	cat > "$OFFLOAD_NFT_FILE" <<EOFNFT
# Managed by ginet-perf.sh - software flow offload for higher NAT throughput.
flowtable ginet_ft {
	hook ingress priority filter;
	devices = { "$wan", "$lan" };
$ft_flags
}
chain forward_ginet_offload {
	type filter hook forward priority filter + 1; policy accept;
	ip protocol { tcp, udp } flow add @ginet_ft
	ip6 nexthdr { tcp, udp } flow add @ginet_ft
}
EOFNFT

	# Validate the full ruleset before relying on it; back out (fail-closed) if
	# the target/kernel does not support the requested offload.
	if command -v fw4 >/dev/null 2>&1; then
		if ! fw4 check >/dev/null 2>&1; then
			logger -t ginet-perf "Flow offload rejected by fw4 check; reverting"
			rm -f "$OFFLOAD_NFT_FILE"
		fi
	fi
}

apply_sqm() {
	if enabled "settings.sqm_enabled"; then
		qdisc=$(uci_get "settings.sqm_qdisc" fq_codel)
		case "$qdisc" in
			fq_codel|cake|fq|sfq) : ;;
			*) qdisc=fq_codel ;;
		esac
		ifname=$(wan_ifname)
		if [ -d "/sys/class/net/$ifname" ] && command -v tc >/dev/null 2>&1; then
			tc qdisc replace dev "$ifname" root "$qdisc" 2>/dev/null || \
				logger -t ginet-perf "Failed to set $qdisc qdisc on $ifname"
		fi
	fi
}

apply() {
	apply_mss
	apply_offload
	reload_firewall
	apply_sqm
}

case "${1:-apply}" in
	apply|boot) apply ;;
	mss) apply_mss; reload_firewall ;;
	offload) apply_offload; reload_firewall ;;
	sqm) apply_sqm ;;
	*) echo "Usage: $0 [apply|boot|mss|offload|sqm]" >&2; exit 1 ;;
esac
