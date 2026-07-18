local uci = require "luci.model.uci".cursor()
local fs = require "nixio.fs"
local sys = require "luci.sys"

local function tunnel_names_for_sim(sim)
	local names = {}
	uci:foreach("ginet_modem", "wireguard_tunnel", function(s)
		if (s.sim_slot or "1") == sim then
			local label = s.name or s[".name"]
			names[#names + 1] = { id = s[".name"], label = label }
		end
	end)
	return names
end

m = Map("ginet_modem", translate("Cellular VPN"),
	translate("Configure WireGuard behavior per SIM slot with fail-closed policy controls."))

local pending = fs.access("/tmp/ginet_wireguard_update.pending") and translate("Pending install on next reboot") or translate("Up to date")

s = m:section(NamedSection, "sim1", "vpn", translate("SIM Slot 1"))
s.addremove = false

sim_present = s:option(Flag, "sim_present", translate("SIM Present"))
sim_present.default = 1
sim_present.rmempty = false

vpn_enabled = s:option(Flag, "vpn_enabled", translate("Enable VPN"))
vpn_enabled.default = 0

wg_auto = s:option(Flag, "auto_update_wireguard", translate("Auto Update WireGuard"))
wg_auto.default = 0
wg_auto.description = translate("Checks every 24h and stages package updates for next reboot")

always_on = s:option(Flag, "always_on_vpn", translate("Always-on VPN"))
always_on.default = 0

kill_switch = s:option(Flag, "block_without_vpn", translate("Block Connections without VPN"))
kill_switch.default = 1
kill_switch.rmempty = false

active = s:option(ListValue, "active_tunnel", translate("Active Tunnel"))
active:value("", translate("None"))
for _, t in ipairs(tunnel_names_for_sim("1")) do
	active:value(t.id, t.label)
end

status1 = s:option(DummyValue, "_wg_update_status", translate("WireGuard Update Status"))
status1.rawhtml = true
status1.default = string.format("<strong>%s</strong>", pending)

s2 = m:section(NamedSection, "sim2", "vpn", translate("SIM Slot 2"))
s2.addremove = false

sim2_present = s2:option(Flag, "sim_present", translate("SIM Present"))
sim2_present.default = 0
sim2_present.rmempty = false

vpn2 = s2:option(Flag, "vpn_enabled", translate("Enable VPN"))
vpn2.default = 0
vpn2:depends("sim_present", "1")

wg2 = s2:option(Flag, "auto_update_wireguard", translate("Auto Update WireGuard"))
wg2.default = 0
wg2:depends("sim_present", "1")

always2 = s2:option(Flag, "always_on_vpn", translate("Always-on VPN"))
always2.default = 0
always2:depends("sim_present", "1")

kill2 = s2:option(Flag, "block_without_vpn", translate("Block Connections without VPN"))
kill2.default = 1
kill2.rmempty = false
kill2:depends("sim_present", "1")

active2 = s2:option(ListValue, "active_tunnel", translate("Active Tunnel"))
active2:value("", translate("None"))
for _, t in ipairs(tunnel_names_for_sim("2")) do
	active2:value(t.id, t.label)
end
active2:depends("sim_present", "1")

status2 = s2:option(DummyValue, "_wg_update_status", translate("WireGuard Update Status"))
status2.rawhtml = true
status2.default = string.format("<strong>%s</strong>", pending)

st = m:section(TypedSection, "wireguard_tunnel", translate("WireGuard Tunnels"),
	translate("Only one tunnel can be active per SIM slot."))
st.addremove = true
st.anonymous = true
st.template = "cbi/tblsection"

name = st:option(Value, "name", translate("Tunnel Name"))
name.rmempty = false
name.datatype = "and(uciname,maxlength(48))"

sim = st:option(ListValue, "sim_slot", translate("SIM Slot"))
sim:value("1", "SIM 1")
sim:value("2", "SIM 2")
sim.default = "1"

enabled = st:option(Flag, "enabled", translate("Enabled"))
enabled.default = 0

private_key = st:option(Value, "private_key", translate("Private Key"))
private_key.password = true
private_key.datatype = "maxlength(200)"

address = st:option(Value, "address", translate("Interface Address"))
address.placeholder = "10.10.0.2/32"
address.datatype = "or(ipaddr,ip6addr,string)"

dns = st:option(Value, "dns", translate("DNS"))
dns.placeholder = "1.1.1.1"
dns.datatype = "or(ipaddr,ip6addr,string)"

pub = st:option(Value, "public_key", translate("Peer Public Key"))
pub.datatype = "maxlength(200)"

psk = st:option(Value, "preshared_key", translate("Peer Preshared Key"))
psk.password = true
psk.datatype = "maxlength(200)"

endpoint_host = st:option(Value, "endpoint_host", translate("Endpoint Host"))
endpoint_host.datatype = "host"

endpoint_port = st:option(Value, "endpoint_port", translate("Endpoint Port"))
endpoint_port.datatype = "port"
endpoint_port.default = "51820"

allowed = st:option(Value, "allowed_ips", translate("Allowed IPs"))
allowed.placeholder = "0.0.0.0/0,::/0"
allowed.datatype = "maxlength(200)"

ka = st:option(Value, "persistent_keepalive", translate("Persistent Keepalive"))
ka.datatype = "uinteger"
ka.default = "25"

mtu = st:option(Value, "mtu", translate("MTU"))
mtu.datatype = "range(1280,1500)"
mtu.placeholder = "1420"
mtu.description = translate("Pin the tunnel MTU to normalize packet sizes and avoid fragmentation fingerprints. Leave blank for the default.")

obfs = st:option(Flag, "obfuscation", translate("Obfuscation"))
obfs.default = 0
obfs.description = translate("Wrap the tunnel transport to resist DPI. Requires an obfuscator " ..
	"package (e.g. udp2raw) installed AND the same obfuscation configured on the VPN server.")

obfs_type = st:option(ListValue, "obfs_type", translate("Obfuscation Type"))
obfs_type:value("udp2raw", "udp2raw")
obfs_type.default = "udp2raw"
obfs_type:depends("obfuscation", "1")

obfs_params = st:option(Value, "obfs_params", translate("Obfuscation Parameters"))
obfs_params.datatype = "maxlength(200)"
obfs_params.placeholder = "-k mypassword --raw-mode faketcp"
obfs_params:depends("obfuscation", "1")

-- Adaptive VPN watchdog -----------------------------------------------------
wd = m:section(NamedSection, "settings", "vpn_watchdog", translate("Adaptive VPN Watchdog"),
	translate("Only reconnects the VPN when the underlying link degrades past a sustained " ..
		"threshold, with hysteresis and cooldown so it does not flap."))
wd.addremove = false

wd_en = wd:option(Flag, "enabled", translate("Enable watchdog"))
wd_en.default = 0

wd_int = wd:option(Value, "interval_minutes", translate("Check interval (minutes)"))
wd_int.datatype = "range(1,60)"
wd_int.default = "2"
wd_int:depends("enabled", "1")

wd_host = wd:option(Value, "probe_host", translate("Probe host"))
wd_host.datatype = "host"
wd_host.default = "1.1.1.1"
wd_host:depends("enabled", "1")

wd_lat = wd:option(Value, "max_latency_ms", translate("Max latency (ms)"))
wd_lat.datatype = "range(1,10000)"
wd_lat.default = "800"
wd_lat:depends("enabled", "1")

wd_thr = wd:option(Value, "fail_threshold", translate("Fail threshold (consecutive bad samples)"))
wd_thr.datatype = "range(1,20)"
wd_thr.default = "3"
wd_thr:depends("enabled", "1")

wd_cd = wd:option(Value, "cooldown_seconds", translate("Cooldown (seconds)"))
wd_cd.datatype = "range(30,3600)"
wd_cd.default = "300"
wd_cd:depends("enabled", "1")

wd_fo = wd:option(Flag, "failover", translate("Fail over to next tunnel"))
wd_fo.default = 0
wd_fo:depends("enabled", "1")
wd_fo.description = translate("On repeated failure, switch to the next configured tunnel for the active SIM.")

function m.on_after_commit(self)
	uci:foreach("ginet_modem", "vpn", function(v)
		local sim_slot = v.sim_slot or ((v[".name"] == "sim2") and "2" or "1")
		local active_tunnel = v.active_tunnel or ""
		if active_tunnel ~= "" then
			uci:foreach("ginet_modem", "wireguard_tunnel", function(t)
				if (t.sim_slot or "1") == sim_slot then
					local target = t[".name"] == active_tunnel and "1" or "0"
					if (t.enabled or "0") ~= target then
						uci:set("ginet_modem", t[".name"], "enabled", target)
					end
				end
			end)
		end
	end)
	uci:commit("ginet_modem")
	local rc = sys.call("/etc/init.d/ginet-vpn reload >/dev/null 2>&1")
	if rc ~= 0 then
		sys.syslog("warning", "ginet-vpn reload failed with exit code " .. tostring(rc))
	end
	-- Apply obfuscation wrappers and refresh watchdog cron scheduling.
	sys.call("/usr/bin/ginet-wg-obfs.sh apply >/dev/null 2>&1")
	sys.call("/etc/init.d/ginet-stealth reload >/dev/null 2>&1")
end

return m
