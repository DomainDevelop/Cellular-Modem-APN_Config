local uci = require "luci.model.uci".cursor()
local sys = require "luci.sys"

m = Map("ginet_modem", translate("Stealth / Privacy"),
	translate("Reduce common passive fingerprinting vectors (tethering detection, " ..
		"device MAC tracking). These controls reduce common detection but do NOT " ..
		"guarantee that a carrier or observer cannot identify tethering, the device, " ..
		"or its location."))

-- Traffic normalization -----------------------------------------------------
s = m:section(NamedSection, "settings", "stealth", translate("Traffic Normalization"))
s.addremove = false

ttl = s:option(Flag, "ttl_normalize", translate("Normalize TTL / Hop Limit"))
ttl.default = 0
ttl.description = translate("Rewrites the outbound TTL/hop-limit to a fixed value so all " ..
	"traffic appears to originate from a single device. Defeats the most common " ..
	"passive tethering check, but not DPI or volume-based heuristics.")

ttlv = s:option(Value, "ttl_value", translate("TTL Value"))
ttlv.datatype = "range(1,255)"
ttlv.default = "65"
ttlv:depends("ttl_normalize", "1")
ttlv.description = translate("Typical values: 64 (Linux/macOS), 65 (to mimic one hop from a phone), 128 (Windows).")

mtu = s:option(Value, "wan_mtu", translate("WAN MTU"))
mtu.datatype = "range(0,9000)"
mtu.default = "0"
mtu.description = translate("Pin the WAN MTU to blend traffic profiles. 0 leaves it unchanged.")

hide = s:option(Flag, "hide_tethering", translate("Hide Tethering (bundle hint)"))
hide.default = 0
hide.description = translate("Convenience reminder: for best tethering concealment, enable TTL " ..
	"normalization above and route DNS through the VPN. No router-side change can " ..
	"guarantee a carrier cannot detect tethering.")

-- MAC randomization ---------------------------------------------------------
mac_modes = {
	{ "off",          translate("Off") },
	{ "on-boot",      translate("On boot") },
	{ "on-reconnect", translate("On reconnect") },
	{ "scheduled",    translate("Scheduled (interval)") },
}

ap = m:section(NamedSection, "ap", "macrand", translate("MAC Randomization - Access Point"),
	translate("Randomizing the AP BSSID disconnects connected clients at each rotation. " ..
		"'On boot' is recommended for the AP."))
ap.addremove = false

ap_if = ap:option(Value, "ifname", translate("Interface"))
ap_if.default = "wlan0"
ap_if.datatype = "maxlength(32)"

ap_mode = ap:option(ListValue, "mode", translate("Mode"))
for _, v in ipairs(mac_modes) do ap_mode:value(v[1], v[2]) end
ap_mode.default = "off"

ap_int = ap:option(Value, "interval_minutes", translate("Interval (minutes)"))
ap_int.datatype = "range(5,1440)"
ap_int.default = "60"
ap_int:depends("mode", "scheduled")

sta = m:section(NamedSection, "sta", "macrand", translate("MAC Randomization - Client / STA"),
	translate("For an upstream client (STA) or wired interface. Leave interface blank to disable."))
sta.addremove = false

sta_if = sta:option(Value, "ifname", translate("Interface"))
sta_if.datatype = "maxlength(32)"

sta_mode = sta:option(ListValue, "mode", translate("Mode"))
for _, v in ipairs(mac_modes) do sta_mode:value(v[1], v[2]) end
sta_mode.default = "off"

sta_int = sta:option(Value, "interval_minutes", translate("Interval (minutes)"))
sta_int.datatype = "range(5,1440)"
sta_int.default = "15"
sta_int:depends("mode", "scheduled")

function m.on_after_commit(self)
	sys.call("/usr/bin/ginet-stealth.sh apply >/dev/null 2>&1")
	-- Refresh the scheduled-randomization cron entries.
	sys.call("/etc/init.d/ginet-stealth reload >/dev/null 2>&1")
end

return m
