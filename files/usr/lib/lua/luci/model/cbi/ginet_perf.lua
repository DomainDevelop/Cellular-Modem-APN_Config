local sys = require "luci.sys"

m = Map("ginet_modem", translate("Performance"),
	translate("Speed up the cellular + WireGuard data path. These controls are " ..
		"performance-only and do NOT weaken the kill-switch, VPN enforcement, TTL/MAC " ..
		"privacy, or Cell Watch controls. All options default to off; enable only what you need."))

s = m:section(NamedSection, "settings", "perf", translate("Data Path Tuning"))
s.addremove = false

mss = s:option(Flag, "mss_clamp", translate("Clamp TCP MSS to path MTU"))
mss.default = 0
mss.description = translate("Fixes silent fragmentation / black-holing of large TCP segments on " ..
	"cellular + WireGuard links. This is the single biggest throughput win and has no security trade-off.")

sqm = s:option(Flag, "sqm_enabled", translate("Bufferbloat control (SQM)"))
sqm.default = 0
sqm.description = translate("Apply a fair-queueing discipline on the WAN device to keep latency low " ..
	"under load. Queueing only — it does not change firewall or VPN policy.")

qd = s:option(ListValue, "sqm_qdisc", translate("Queue discipline"))
qd:value("fq_codel", "fq_codel")
qd:value("cake", "cake (needs kmod-sched-cake)")
qd:value("fq", "fq")
qd:value("sfq", "sfq")
qd.default = "fq_codel"
qd:depends("sqm_enabled", "1")

off = s:option(Flag, "flow_offloading", translate("Software flow offload"))
off.default = 0
off.description = translate("Raises NAT throughput and lowers CPU per packet. FAIL-CLOSED: it " ..
	"automatically self-disables whenever a kill-switch is configured or TTL normalization is on, " ..
	"because those controls must inspect every packet.")

offhw = s:option(Flag, "flow_offloading_hw", translate("Hardware flow offload"))
offhw.default = 0
offhw.description = translate("Additionally request hardware offload where the target supports it. " ..
	"Only honored while software offload is active and safe; reverted automatically if the ruleset is rejected.")
offhw:depends("flow_offloading", "1")

function m.on_after_commit(self)
	sys.call("/usr/bin/ginet-perf.sh apply >/dev/null 2>&1")
end

return m
