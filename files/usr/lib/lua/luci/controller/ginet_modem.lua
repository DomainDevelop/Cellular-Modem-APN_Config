module("luci.controller.ginet_modem", package.seeall)

function index()
	entry(
		{"admin", "network", "ginet_modem"},
		cbi("ginet_modem"),
		_("Cellular"),
		70
	).leaf = true
end
