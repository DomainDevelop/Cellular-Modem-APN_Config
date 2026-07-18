require("luci.sys")
require("luci.util")

local fs = require "nixio.fs"
local util = require "luci.util"

local json_available, json = pcall(require, "cjson")

local function safe_text(v, fallback)
	v = tostring(v or fallback or "")
	v = v:gsub("[<>&\"]", {
		["<"] = "&lt;",
		[">"] = "&gt;",
		["&"] = "&amp;",
		['"'] = "&quot;"
	})
	return v
end

local function read_modem_status()
	local status_file = "/tmp/ginet_modem_status.json"
	local modem_status = {
		imei = "N/A",
		apn = "N/A",
		signal = "N/A",
		connection_type = "Disconnected",
		data_status = "Disconnected",
		sim_status = "Unknown",
		device = "Not detected"
	}

	if fs.access(status_file) then
		local f = io.open(status_file, "r")
		if f then
			local json_str = f:read("*a")
			f:close()

			if json_available and json then
				local success, data = pcall(json.parse, json_str)
				if success and type(data) == "table" then
					for k, v in pairs(data) do
						modem_status[k] = v
					end
				end
			end
		end
	end

	return modem_status
end

m = Map("ginet_modem", translate("Cell Modem Settings"),
	translate("Configure APN and monitor cellular modem status."))

local modem_status = read_modem_status()

s_status = m:section(NamedSection, "settings", "modem", translate("Current Modem Status"))
s_status.addremove = false
s_status.anonymous = true

local o = s_status:option(DummyValue, "_status_device", translate("Modem Device"))
o.rawhtml = true
o.default = string.format("<strong>%s</strong>", safe_text(modem_status.device, "Not detected"))

o = s_status:option(DummyValue, "_status_imei", translate("Device IMEI"))
o.default = safe_text(modem_status.imei, "N/A")

o = s_status:option(DummyValue, "_status_apn", translate("Current APN"))
o.default = safe_text(modem_status.apn, "internet")

o = s_status:option(DummyValue, "_status_connection", translate("Connection Type"))
o.default = safe_text(modem_status.connection_type, "Disconnected")

o = s_status:option(DummyValue, "_status_data", translate("Data Connection"))
o.default = safe_text(modem_status.data_status, "Disconnected")

o = s_status:option(DummyValue, "_status_signal", translate("Signal Strength"))
local signal = modem_status.signal or "N/A"
o.default = safe_text(signal ~= "N/A" and (tostring(signal) .. " dBm") or "No Signal", "No Signal")

o = s_status:option(DummyValue, "_status_sim", translate("SIM Card Status"))
o.default = safe_text(modem_status.sim_status, "Unknown")

o = s_status:option(DummyValue, "_status_update", translate("Last Updated"))
o.default = safe_text(modem_status.timestamp or os.date("%Y-%m-%d %H:%M:%S"), "")

s_config = m:section(NamedSection, "settings", "modem", translate("Configuration"))
s_config.addremove = false
s_config.anonymous = true

o = s_config:option(Value, "apn", translate("Access Point Name (APN)"))
o.placeholder = "internet"
o.datatype = "and(maxlength(64),string)"
o.rmempty = false

local enabled = s_config:option(Flag, "enabled", translate("Enable Cellular Modem"))
enabled.default = 1
enabled.rmempty = false

function m.on_save(self)
	local apn = self.uci:get("ginet_modem", "settings", "apn")
	local enabled = self.uci:get("ginet_modem", "settings", "enabled")

	if enabled == "1" and apn and #apn <= 64 and apn:match("^[%w%._%-]+$") then
		luci.sys.call(string.format("/usr/bin/apply-ginet-modem-settings.sh %q >/dev/null 2>&1", apn))
		util.exec("/usr/bin/ginet-modem-status.sh > /tmp/ginet_modem_status.json 2>/dev/null &")
	end
end

return m
