require("luci.sys")
require("luci.util")

local fs = require "nixio.fs"
local util = require "luci.util"

local function parse_csv_list(value)
	local items = {}
	for item in (value or ""):gmatch("[^,]+") do
		item = item:gsub("^%s+", ""):gsub("%s+$", "")
		if item ~= "" then
			items[#items + 1] = item
		end
	end
	return items
end

local function mode_label(mode)
	local labels = {
		auto = translate("Auto"),
		["5g"] = translate("5G"),
		["4g"] = translate("4G / LTE"),
		["3g"] = translate("3G"),
		["2g"] = translate("2G"),
		["1g"] = translate("1G")
	}
	return labels[mode] or mode:upper()
end

local function validate_integer_range(value, minimum, maximum, empty_allowed)
	if not value or value == "" then
		return empty_allowed and value or nil
	end

	if not value:match("^%d+$") then
		return nil
	end

	local numeric_value = tonumber(value)
	if numeric_value and numeric_value >= minimum and numeric_value <= maximum then
		return tostring(numeric_value)
	end

	return nil
end

local function get_uci(section, option, default)
	local value = uci:get("ginet_modem", section, option)
	if value == nil or value == "" then
		return default
	end
	return value
end

local function ensure_defaults()
	local changed = false

	if not uci:get("ginet_modem", "settings") then
		uci:section("ginet_modem", "modem", "settings", {})
		changed = true
	end
	if not uci:get("ginet_modem", "sim1") then
		uci:section("ginet_modem", "apn", "sim1", {})
		changed = true
	end
	if not uci:get("ginet_modem", "sim2") then
		uci:section("ginet_modem", "apn", "sim2", {})
		changed = true
	end

	local defaults = {
		settings = {
			enabled = "1",
			allow_imei_edit = "1",
			imei_scope = "global",
			active_slot = "sim1",
			profile_to_edit = "sim1",
			network_mode = "auto",
			supported_network_modes = "auto,5g,4g,3g,2g"
		},
		sim1 = {
			name = "SIM 1",
			apn = "internet",
			apn_protocol = "ipv4v6",
			apn_roaming_protocol = "ipv4v6",
			network_type = "auto"
		},
		sim2 = {
			name = "SIM 2",
			apn = "internet",
			apn_protocol = "ipv4v6",
			apn_roaming_protocol = "ipv4v6",
			network_type = "auto"
		}
	}

	for section, options in pairs(defaults) do
		for option, value in pairs(options) do
			if uci:get("ginet_modem", section, option) == nil then
				uci:set("ginet_modem", section, option, value)
				changed = true
			end
		end
	end

	if changed then
		uci:save("ginet_modem")
		uci:commit("ginet_modem")
	end
	return changed
end

local APN_PATTERN = "^[%w%._%-]+$"

local function safe_text(v, fallback)
	v = tostring(v or fallback or "")
	v = v:gsub("&", "&amp;")
	v = v:gsub("<", "&lt;")
	v = v:gsub(">", "&gt;")
	v = v:gsub('"', "&quot;")
	return v
end

local function read_modem_status()
	local modem_status = {
		imei = "N/A",
		apn = get_uci("sim1", "apn", "internet"),
		carrier = "Unknown",
		signal = "N/A",
		connection_type = "Disconnected",
		data_status = "Disconnected",
		sim_status = "Unknown",
		sim_inserted = "Unknown",
		device = "Not detected",
		active_slot = get_uci("settings", "active_slot", "sim1"),
		preferred_network_mode = get_uci("settings", "network_mode", "auto"),
		supported_network_modes = get_uci("settings", "supported_network_modes", "auto,5g,4g,3g,2g"),
		imei_scope = get_uci("settings", "imei_scope", "global"),
		imei_editable = "0"
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
function o.validate(self, value)
	if value and value:match(APN_PATTERN) then
		return value
	end
	return nil, translate("APN can only contain letters, numbers, dots, underscores, and dashes")
end

local enabled = s_config:option(Flag, "enabled", translate("Enable Cellular Modem"))
enabled.default = 1
enabled.rmempty = false

function m.on_save(self)
	local apn = self.uci:get("ginet_modem", "settings", "apn")
	local enabled = self.uci:get("ginet_modem", "settings", "enabled")

	if enabled == "1" and apn and #apn <= 64 and apn:match(APN_PATTERN) then
		local rc = luci.sys.call(string.format("/usr/bin/apply-ginet-modem-settings.sh %q >/dev/null 2>&1", apn))
		if rc ~= 0 then
			luci.sys.syslog("warning", "apply-ginet-modem-settings.sh failed with exit code " .. tostring(rc))
		else
			util.exec("/usr/bin/ginet-modem-status.sh > /tmp/ginet_modem_status.json 2>/dev/null &")
		end
	end
end

local status_value = apn_info:option(DummyValue, "_profile_status", translate("Profile Status"))
function status_value.cfgvalue(self, section)
	return section == active_slot and translate("Active") or translate("Inactive")
end

local imei_profile = apn_info:option(DummyValue, "_profile_imei", translate("IMEI / Modem Identity"))
function imei_profile.cfgvalue(self, section)
	if (modem_status.imei_scope or "global") == "global" then
		return (modem_status.imei or "N/A") .. " — " .. translate("shared across SIM profiles")
	end
	return modem_status.imei or "N/A"
end

local name = apn_info:option(Value, "name", translate("Name"))
name.placeholder = translate("Carrier label")
name.rmempty = false

local apn = apn_info:option(Value, "apn", translate("APN"))
apn.placeholder = "internet"
apn.rmempty = false

local proxy = apn_info:option(Value, "proxy", translate("Proxy"))
proxy.rmempty = true

local port = apn_info:option(Value, "port", translate("Port"))
port.rmempty = true
function port.validate(self, value)
	local validated = validate_integer_range(value, 1, 65535, true)
	if validated ~= nil then
		return validated
	end
	return nil, translate("Port must be between 1 and 65535.")
end

local username = apn_info:option(Value, "username", translate("Username"))
username.rmempty = true

local password = apn_info:option(Value, "password", translate("Password"))
password.password = true
password.rmempty = true

local server = apn_info:option(Value, "server", translate("Server"))
server.rmempty = true

local apn_type = apn_info:option(Value, "apn_type", translate("APN Type"))
apn_type.placeholder = "default,supl"
apn_type.rmempty = true

local mmsc = apn_info:option(Value, "mmsc", translate("MMSC"))
mmsc.rmempty = true

local mms_proxy = apn_info:option(Value, "mms_proxy", translate("MMS Proxy"))
mms_proxy.rmempty = true

local apn_protocol = apn_info:option(ListValue, "apn_protocol", translate("APN Protocol"))
apn_protocol:value("ipv4", "IPv4")
apn_protocol:value("ipv6", "IPv6")
apn_protocol:value("ipv4v6", "IPv4 / IPv6")
apn_protocol.default = "ipv4v6"

local roaming_protocol = apn_info:option(ListValue, "apn_roaming_protocol", translate("APN Roaming Protocol"))
roaming_protocol:value("ipv4", "IPv4")
roaming_protocol:value("ipv6", "IPv6")
roaming_protocol:value("ipv4v6", "IPv4 / IPv6")
roaming_protocol.default = "ipv4v6"

local network_type = apn_info:option(ListValue, "network_type", translate("Network Type"))
add_network_mode_choices(network_type)
network_type.default = "auto"

function m.on_after_commit(self)
	sys.call("/usr/bin/apply-ginet-modem-settings.sh --from-uci >/tmp/ginet_modem_apply.last 2>&1 &")
	sys.call("/usr/bin/ginet-modem-status.sh > /tmp/ginet_modem_status.json 2>/dev/null &")
end

return m
