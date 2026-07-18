#!/bin/sh
# Apply VPN policy controls (always-on and kill-switch)

set -eu

PENDING_FILE="/tmp/ginet_wireguard_update.pending"
KILLSWITCH_FILE="/etc/nftables.d/99-ginet-killswitch.nft"

vpn_enabled() {
	section="$1"
	uci -q get "ginet_modem.$section.vpn_enabled" 2>/dev/null | grep -q '^1$'
}

kill_switch_enabled() {
	section="$1"
	uci -q get "ginet_modem.$section.block_without_vpn" 2>/dev/null | grep -q '^1$'
}

always_on_enabled() {
	section="$1"
	uci -q get "ginet_modem.$section.always_on_vpn" 2>/dev/null | grep -q '^1$'
}

active_tunnel_ifname() {
	section="$1"
	tunnel_name=$(uci -q get "ginet_modem.$section.active_tunnel" 2>/dev/null || true)
	[ -n "$tunnel_name" ] || return 1
	echo "wg_$tunnel_name" | tr -c 'A-Za-z0-9_' '_'
}

write_killswitch() {
	wg_if="$1"
	mkdir -p /etc/nftables.d
	cat > "$KILLSWITCH_FILE" <<EOFNFT
chain output_ginet_killswitch {
	type filter hook output priority 0; policy accept;
	oifname "wan" ip daddr != 127.0.0.1 meta oifname != "$wg_if" reject
}
EOFNFT
}

remove_killswitch() {
	rm -f "$KILLSWITCH_FILE"
}

apply() {
	applied=0
	for section in sim1 sim2; do
		if vpn_enabled "$section" && kill_switch_enabled "$section"; then
			wg_if=$(active_tunnel_ifname "$section" || true)
			if [ -n "${wg_if:-}" ]; then
				write_killswitch "$wg_if"
				applied=1
				break
			fi
		fi
	done

	[ "$applied" -eq 1 ] || remove_killswitch
	/etc/init.d/firewall reload >/dev/null 2>&1 || true
}

check_pending_install() {
	[ -f "$PENDING_FILE" ] || return 0
	opkg update >/dev/null 2>&1 || true
	if opkg list-upgradable 2>/dev/null | grep -q '^wireguard-tools '; then
		opkg upgrade wireguard-tools >/dev/null 2>&1 || true
	fi
	rm -f "$PENDING_FILE"
}

ensure_always_on_boot_order() {
	if always_on_enabled sim1 || always_on_enabled sim2; then
		/etc/init.d/ginet-vpn enable >/dev/null 2>&1 || true
	fi
}

case "${1:-apply}" in
	apply) apply ;;
	boot) check_pending_install; ensure_always_on_boot_order; apply ;;
	*) echo "Usage: $0 [apply|boot]" >&2; exit 1 ;;
esac
