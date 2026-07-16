-- GiNet Cell Modem LuCI Controller
-- Registers the Cell Modem configuration interface in LuCI menu

module("luci.controller.ginet_modem", package.seeall)

function index()
	entry(
		{"admin", "network", "ginet_modem"},
		cbi("ginet_modem"),
		_("Cell Modem"),
		70
	).leaf = true
end
