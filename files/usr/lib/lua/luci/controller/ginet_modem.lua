module("luci.controller.ginet_modem", package.seeall)

local fs = require "nixio.fs"
local sys = require "luci.sys"

function index()
	if not fs.access("/etc/config/ginet_modem") then
		sys.syslog("warning", "ginet_modem config not found; LuCI pages not registered")
		return
	end

	entry({"admin", "network", "ginet_modem"}, cbi("ginet_modem"), _("Cell Modem"), 70).leaf = true
	entry({"admin", "network", "ginet_vpn"}, cbi("ginet_vpn"), _("Cellular VPN"), 71).leaf = true
	entry({"admin", "network", "ginet_stealth"}, cbi("ginet_stealth"), _("Stealth / Privacy"), 72).leaf = true
	entry({"admin", "network", "ginet_cellwatch"}, cbi("ginet_cellwatch"), _("Cell Watch"), 73).leaf = true
	entry({"admin", "system", "ginet_terminal"}, cbi("ginet_terminal"), _("System Terminal"), 95).leaf = true
end
