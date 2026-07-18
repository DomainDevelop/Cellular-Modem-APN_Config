#!/bin/sh
# Cell watch: rogue-tower / IMSI-catcher HEURISTICS and coarse tower-based
# location.
#
# HONESTY NOTE: This does not perform true IMSI-catcher detection. Most modems
# do not expose raw baseband / full neighbor-cell data over QMI. What this can
# reliably flag is the classic forced 2G/3G downgrade and unexpected serving
# Cell ID / LAC changes, which catch the common case. Treat alerts as hints,
# not proof.
#
# Location lookup is coarse (hundreds of metres to kilometres) and uses a LOCAL
# offline CSV database only, so cell identifiers are never sent to the network.

set -eu

DEVICE_QMI="/dev/cdc-wdm0"
STATE_FILE="/tmp/ginet_cellwatch_state"
OUTPUT_FILE="/tmp/ginet_cellwatch.json"

uci_get() {
	uci -q get "ginet_modem.$1" 2>/dev/null || echo "${2:-}"
}

enabled() {
	[ "$(uci_get "$1" 0)" = "1" ]
}

json_escape() {
	echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

extract_json_string() {
	key="$1"
	printf '%s' "$2" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

extract_json_number() {
	key="$1"
	printf '%s' "$2" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\(-\?[0-9]\+\).*/\1/p" | head -1
}

# Determine radio access technology from serving-system data.
detect_rat() {
	info="$1"
	if echo "$info" | grep -qi "nr5g.*true\|5gnr.*true"; then echo "5G"; return; fi
	if echo "$info" | grep -qi "lte.*true"; then echo "4G"; return; fi
	if echo "$info" | grep -qi "umts.*true\|wcdma.*true\|hsdpa\|hsupa"; then echo "3G"; return; fi
	if echo "$info" | grep -qi "gsm.*true\|gprs\|edge"; then echo "2G"; return; fi
	reg=$(extract_json_string registration "$info")
	case "$reg" in
		*5g*|*nr*) echo "5G" ;;
		*lte*|*4g*) echo "4G" ;;
		*3g*|*umts*|*wcdma*) echo "3G" ;;
		*2g*|*gsm*) echo "2G" ;;
		*) echo "Unknown" ;;
	esac
}

rat_rank() {
	case "$1" in
		5G) echo 5 ;; 4G) echo 4 ;; 3G) echo 3 ;; 2G) echo 2 ;; *) echo 0 ;;
	esac
}

# Lookup coarse location from the offline CSV database.
# Expected CSV columns: mcc,mnc,lac,cid,lat,lon
lookup_location() {
	mcc="$1"; mnc="$2"; lac="$3"; cid="$4"
	db=$(uci_get "settings.location_db" /etc/ginet/cell_db.csv)
	[ -f "$db" ] || return 1
	[ -n "$mcc$mnc$lac$cid" ] || return 1
	awk -F',' -v mcc="$mcc" -v mnc="$mnc" -v lac="$lac" -v cid="$cid" '
		$1==mcc && $2==mnc && $3==lac && $4==cid { print $5","$6; found=1; exit }
		END { if (!found) exit 1 }
	' "$db" 2>/dev/null
}

write_output() {
	rat="$1"; mcc="$2"; mnc="$3"; lac="$4"; cid="$5"; signal="$6"
	alerts="$7"; lat="$8"; lon="$9"
	cat > "$OUTPUT_FILE" <<EOFJSON
{
  "enabled": true,
  "rat": "$(json_escape "$rat")",
  "mcc": "$(json_escape "$mcc")",
  "mnc": "$(json_escape "$mnc")",
  "lac": "$(json_escape "$lac")",
  "cell_id": "$(json_escape "$cid")",
  "signal_dbm": "$(json_escape "$signal")",
  "latitude": "$(json_escape "$lat")",
  "longitude": "$(json_escape "$lon")",
  "alerts": [$alerts],
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOFJSON
}

run() {
	if ! enabled "settings.enabled"; then
		echo '{ "enabled": false }' > "$OUTPUT_FILE"
		return 0
	fi

	if [ ! -c "$DEVICE_QMI" ]; then
		echo '{ "enabled": true, "status": "no-modem" }' > "$OUTPUT_FILE"
		return 0
	fi

	sys_info=$(timeout 3 uqmi -d "$DEVICE_QMI" --get-serving-system 2>/dev/null || true)
	sig_info=$(timeout 3 uqmi -d "$DEVICE_QMI" --get-signal-info 2>/dev/null || true)

	rat=$(detect_rat "$sys_info")
	mcc=$(extract_json_number mcc "$sys_info")
	mnc=$(extract_json_number mnc "$sys_info")
	lac=$(extract_json_number lac "$sys_info")
	cid=$(extract_json_number cid "$sys_info")
	[ -n "$cid" ] || cid=$(extract_json_number cell_id "$sys_info")
	signal=$(extract_json_number rssi "$sig_info")

	alerts=""
	add_alert() {
		if [ -n "$alerts" ]; then alerts="$alerts, "; fi
		alerts="$alerts\"$(json_escape "$1")\""
	}

	# Load previous state.
	prev_rat=""; prev_cid=""; prev_lac=""
	if [ -f "$STATE_FILE" ]; then
		# shellcheck disable=SC1090
		. "$STATE_FILE" 2>/dev/null || true
		prev_rat="${CW_RAT:-}"
		prev_cid="${CW_CID:-}"
		prev_lac="${CW_LAC:-}"
	fi

	# Heuristic 1: forced downgrade to 2G/3G.
	if enabled "settings.alert_downgrade" && [ -n "$prev_rat" ] && [ "$rat" != "Unknown" ]; then
		cur_rank=$(rat_rank "$rat")
		prev_rank=$(rat_rank "$prev_rat")
		if [ "$cur_rank" -lt "$prev_rank" ] && [ "$cur_rank" -le 3 ] && [ "$cur_rank" -gt 0 ]; then
			add_alert "Downgrade from $prev_rat to $rat (possible forced downgrade)"
		fi
	fi

	# Heuristic 2: unexpected serving Cell ID / LAC change.
	if enabled "settings.alert_cellid_change" && [ -n "$prev_cid" ] && [ -n "$cid" ]; then
		if [ "$cid" != "$prev_cid" ]; then
			add_alert "Serving Cell ID changed ($prev_cid -> $cid)"
		fi
	fi
	if enabled "settings.alert_cellid_change" && [ -n "$prev_lac" ] && [ -n "$lac" ]; then
		if [ "$lac" != "$prev_lac" ]; then
			add_alert "LAC/TAC changed ($prev_lac -> $lac)"
		fi
	fi

	lat=""; lon=""
	if enabled "settings.location_enabled"; then
		loc=$(lookup_location "$mcc" "$mnc" "$lac" "$cid" || true)
		if [ -n "$loc" ]; then
			lat=$(echo "$loc" | cut -d',' -f1)
			lon=$(echo "$loc" | cut -d',' -f2)
		fi
	fi

	write_output "$rat" "$mcc" "$mnc" "$lac" "$cid" "$signal" "$alerts" "$lat" "$lon"

	# Persist current state for next comparison.
	cat > "$STATE_FILE" <<EOFSTATE
CW_RAT="$rat"
CW_CID="$cid"
CW_LAC="$lac"
EOFSTATE
}

case "${1:-run}" in
	run) run ;;
	*) echo "Usage: $0 [run]" >&2; exit 1 ;;
esac
