local util = require "luci.util"

local output_cache = ""

local allowed_bins = {
	ubus = true,
	uci = true,
	ip = true,
	ifstatus = true,
	logread = true,
	wg = true,
	ping = true,
	nslookup = true,
	opkg = true,
	cat = true,
	dmesg = true
}

local function command_allowed(cmd)
	if not cmd or #cmd == 0 or #cmd > 256 then
		return false
	end
	if cmd:match("[;&|`$><\\]") then
		return false
	end
	if not cmd:match("^[%w%s%._%-%+/%:=,@]+$") then
		return false
	end
	local bin = cmd:match("^(%S+)")
	if not bin or not allowed_bins[bin] then
		return false
	end

	return true
end

m = SimpleForm("ginet_terminal", translate("Built-in Terminal"),
	translate("Admin-only controlled PTY terminal. Commands are validated and restricted for safety."))
m.reset = false
m.submit = false

s = m:section(SimpleSection)

cmd = s:option(Value, "command", translate("Command"))
cmd.datatype = "and(maxlength(256),string)"
cmd.placeholder = "ubus call system board"

run = s:option(Button, "run", translate("Run Command"))
run.inputstyle = "apply"

out = s:option(TextValue, "output", translate("Output"))
out.rows = 20
out.readonly = true
out.cfgvalue = function()
	return output_cache
end

function run.write(self, section)
	local command = (self.map:formvalue("cbid.ginet_terminal.command") or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if not command_allowed(command) then
		output_cache = "Blocked by safety policy. Use plain command syntax without shell chaining/operators."
		return
	end

	local wrapped = string.format("timeout 10 script -qfc %q /dev/null 2>&1", command)
	output_cache = (util.exec(wrapped) or ""):sub(1, 12000)
	if output_cache == "" then
		output_cache = "(no output)"
	end
end

return m
