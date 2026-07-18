#!/bin/sh
# WireGuard obfuscation helper.
#
# Optionally wraps a WireGuard tunnel's UDP transport in an obfuscation layer so
# the handshake does not look like WireGuard to DPI. This is OPT-IN and gated on
# the obfuscator binary being installed.
#
# IMPORTANT: Obfuscation only works if BOTH ends run the same obfuscator with
# matching parameters. Your VPN server must be configured to match.
#
# Supported obfs_type values:
#   udp2raw  - requires the 'udp2raw' package (kmod-... + udp2raw)
#
# The obfuscator listens locally and forwards to the real endpoint; the tunnel's
# endpoint should then point at the local obfuscator (127.0.0.1:<local_port>).

set -eu

RUN_DIR="/var/run/ginet-obfs"

uci_get() {
	uci -q get "ginet_modem.$1" 2>/dev/null || echo "${2:-}"
}

obfs_binary() {
	case "$1" in
		udp2raw) command -v udp2raw 2>/dev/null || command -v udp2raw_amd64 2>/dev/null ;;
		*) return 1 ;;
	esac
}

tunnel_sections() {
	uci -q show ginet_modem 2>/dev/null | \
		sed -n "s/^ginet_modem\.\([^.]*\)=wireguard_tunnel$/\1/p"
}

pidfile_for() {
	echo "$RUN_DIR/$1.pid"
}

stop_one() {
	sec="$1"
	pf=$(pidfile_for "$sec")
	if [ -f "$pf" ]; then
		pid=$(cat "$pf" 2>/dev/null || true)
		if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			kill "$pid" 2>/dev/null || true
		fi
		rm -f "$pf"
	fi
}

start_one() {
	sec="$1"
	[ "$(uci_get "$sec.enabled" 0)" = "1" ] || { stop_one "$sec"; return 0; }
	[ "$(uci_get "$sec.obfuscation" 0)" = "1" ] || { stop_one "$sec"; return 0; }

	otype=$(uci_get "$sec.obfs_type" udp2raw)
	bin=$(obfs_binary "$otype" || true)
	if [ -z "$bin" ]; then
		logger -t ginet-wg-obfs "Obfuscator '$otype' not installed; skipping $sec"
		return 0
	fi

	host=$(uci_get "$sec.endpoint_host")
	port=$(uci_get "$sec.endpoint_port" 51820)
	params=$(uci_get "$sec.obfs_params")
	[ -n "$host" ] || { logger -t ginet-wg-obfs "No endpoint_host for $sec"; return 0; }

	# Derive a stable local listen port from the section name.
	local_port=$(( 40000 + $(printf '%s' "$sec" | cksum | cut -d' ' -f1) % 20000 ))

	mkdir -p "$RUN_DIR"
	stop_one "$sec"

	case "$otype" in
		udp2raw)
			# Client mode: listen locally, raw-forward to the real endpoint.
			# shellcheck disable=SC2086
			"$bin" -c -l "127.0.0.1:$local_port" -r "$host:$port" $params >/dev/null 2>&1 &
			echo $! > "$(pidfile_for "$sec")"
			logger -t ginet-wg-obfs "Started $otype for $sec: 127.0.0.1:$local_port -> $host:$port"
			;;
	esac
}

case "${1:-apply}" in
	apply|start)
		for s in $(tunnel_sections); do start_one "$s"; done
		;;
	stop)
		for s in $(tunnel_sections); do stop_one "$s"; done
		;;
	*) echo "Usage: $0 [apply|start|stop]" >&2; exit 1 ;;
esac
