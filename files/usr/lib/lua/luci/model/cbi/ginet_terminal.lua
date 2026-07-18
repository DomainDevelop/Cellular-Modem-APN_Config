local util = require "luci.util"

local output_cache = ""

local command_catalog = {
	board = "ubus call system board",
	sysinfo = "ubus call system info",
	ipaddr = "ip address",
	wwan = "ifstatus wwan",
	wgshow = "wg show",
	logread = "logread"
}

local function catalog_command_safe(cmd)
	return cmd and cmd:match("^[%w%s%._%-]+$") ~= nil
end

m = SimpleForm("ginet_terminal", translate("Built-in Terminal"),
	translate("Admin-only controlled PTY terminal with restricted diagnostic command set."))
m.reset = false
m.submit = false

s = m:section(SimpleSection)

cmd = s:option(ListValue, "command", translate("Command"))
cmd:value("board", "ubus call system board")
cmd:value("sysinfo", "ubus call system info")
cmd:value("ipaddr", "ip address")
cmd:value("wwan", "ifstatus wwan")
cmd:value("wgshow", "wg show")
cmd:value("logread", "logread")
cmd.default = "board"

run = s:option(Button, "run", translate("Run Command"))
run.inputstyle = "apply"

out = s:option(TextValue, "output", translate("Output"))
out.rows = 20
out.readonly = true
out.cfgvalue = function()
	return output_cache
end

function run.write(self, section)
	local command_id = self.map:formvalue("cbid.ginet_terminal.command") or ""
	local command = command_catalog[command_id]
	if not command or not catalog_command_safe(command) then
		output_cache = "Blocked by safety policy."
		return
	end

	local wrapped = string.format("timeout 10 script -qfc %q /dev/null 2>&1", command)
	local raw = util.exec(wrapped) or ""
	if #raw > 12000 then
		output_cache = raw:sub(1, 12000) .. "\n\n[output truncated to 12000 bytes]"
	else
		output_cache = raw ~= "" and raw or "(no output)"
	end
end

return m
