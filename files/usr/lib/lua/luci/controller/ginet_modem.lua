module("luci.controller.ginet_modem", package.seeall)

local fs = require "nixio.fs"

function index()
	if not fs.access("/etc/config/ginet_modem") then
		return
	end

	entry({"admin", "network", "ginet_modem"}, cbi("ginet_modem"), _("Cell Modem"), 70).leaf = true
	entry({"admin", "network", "ginet_vpn"}, cbi("ginet_vpn"), _("Cellular VPN"), 71).leaf = true
	entry({"admin", "system", "ginet_terminal"}, cbi("ginet_terminal"), _("System Terminal"), 95).leaf = true
end
