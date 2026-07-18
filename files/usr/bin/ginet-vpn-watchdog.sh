#!/bin/sh
# Adaptive/regulated VPN watchdog.
#
# Only bounces the VPN when the underlying link degrades past a sustained
# threshold, using hysteresis (fail_threshold consecutive bad samples) and a
# cooldown between corrective actions so it "regulates" instead of thrashing.
# Optionally fails over to the next configured tunnel for the active SIM.

set -eu

STATE_FILE="/tmp/ginet_vpn_watchdog_state"

uci_get() {
	uci -q get "ginet_modem.$1" 2>/dev/null || echo "${2:-}"
}

enabled() {
	[ "$(uci_get "$1" 0)" = "1" ]
}

num() {
	# Sanitize to a non-negative integer with a fallback default.
	v="$1"; d="$2"
	case "$v" in
		''|*[!0-9]*) echo "$d" ;;
		*) echo "$v" ;;
	esac
}

active_vpn_section() {
	for section in sim1 sim2; do
		if enabled "$section.vpn_enabled"; then
			t=$(uci_get "$section.active_tunnel")
			if [ -n "$t" ]; then
				echo "$section"
				return 0
			fi
		fi
	done
	return 1
}

# Ordered list of tunnel section names for a SIM slot.
tunnels_for_slot() {
	slot="$1"
	uci -q show ginet_modem 2>/dev/null | \
		sed -n "s/^ginet_modem\.\([^.]*\)=wireguard_tunnel$/\1/p" | while read -r s; do
		ts=$(uci_get "$s.sim_slot" 1)
		[ "$ts" = "$slot" ] && echo "$s"
	done
}

probe() {
	host="$1"
	max_ms="$2"
	# One quick ping; treat loss or timeout as failure.
	out=$(ping -c 1 -W 2 "$host" 2>/dev/null || true)
	echo "$out" | grep -q 'bytes from' || return 1
	rtt=$(echo "$out" | sed -n 's/.*time=\([0-9]*\)\.\?[0-9]* ms.*/\1/p' | head -1)
	[ -n "$rtt" ] || return 0
	[ "$rtt" -le "$max_ms" ]
}

now() { date +%s; }

run() {
	enabled "settings.enabled" || return 0

	section=$(active_vpn_section || true)
	[ -n "${section:-}" ] || return 0

	host=$(uci_get "settings.probe_host" 1.1.1.1)
	max_ms=$(num "$(uci_get "settings.max_latency_ms" 800)" 800)
	threshold=$(num "$(uci_get "settings.fail_threshold" 3)" 3)
	cooldown=$(num "$(uci_get "settings.cooldown_seconds" 300)" 300)

	fails=0
	last_action=0
	if [ -f "$STATE_FILE" ]; then
		# shellcheck disable=SC1090
		. "$STATE_FILE" 2>/dev/null || true
		fails=$(num "${WD_FAILS:-0}" 0)
		last_action=$(num "${WD_LAST_ACTION:-0}" 0)
	fi

	if probe "$host" "$max_ms"; then
		fails=0
	else
		fails=$(( fails + 1 ))
	fi

	if [ "$fails" -ge "$threshold" ]; then
		elapsed=$(( $(now) - last_action ))
		if [ "$elapsed" -ge "$cooldown" ]; then
			logger -t ginet-vpn-watchdog "Link degraded ($fails>=$threshold bad samples); regulating VPN for $section"

			if enabled "settings.failover"; then
				slot=$(uci_get "$section.sim_slot" 1)
				current=$(uci_get "$section.active_tunnel")
				list=$(tunnels_for_slot "$slot")
				next=""
				pick_next=0
				for t in $list; do
					if [ "$pick_next" = "1" ]; then next="$t"; break; fi
					[ "$t" = "$current" ] && pick_next=1
				done
				# Wrap around to the first tunnel if we were at the end.
				if [ -z "$next" ]; then
					next=$(echo "$list" | head -1)
				fi
				if [ -n "$next" ] && [ "$next" != "$current" ]; then
					uci set "ginet_modem.$section.active_tunnel=$next"
					uci commit ginet_modem
					logger -t ginet-vpn-watchdog "Failover $section: $current -> $next"
				fi
			fi

			/etc/init.d/ginet-vpn reload >/dev/null 2>&1 || true
			last_action=$(now)
			fails=0
		fi
	fi

	cat > "$STATE_FILE" <<EOFSTATE
WD_FAILS="$fails"
WD_LAST_ACTION="$last_action"
EOFSTATE
}

case "${1:-run}" in
	run) run ;;
	*) echo "Usage: $0 [run]" >&2; exit 1 ;;
esac
