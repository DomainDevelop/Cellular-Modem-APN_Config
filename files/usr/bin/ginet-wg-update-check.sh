#!/bin/sh
# Stage WireGuard tool updates for next reboot when enabled.

set -eu

PENDING_FILE="/tmp/ginet_wireguard_update.pending"

has_auto_update() {
	section="$1"
	uci -q get "ginet_modem.$section.auto_update_wireguard" 2>/dev/null | grep -q '^1$'
}

if has_auto_update sim1 || has_auto_update sim2; then
	opkg update >/dev/null 2>&1 || true
	if opkg list-upgradable 2>/dev/null | grep -q '^wireguard-tools '; then
		touch "$PENDING_FILE"
	fi
fi
