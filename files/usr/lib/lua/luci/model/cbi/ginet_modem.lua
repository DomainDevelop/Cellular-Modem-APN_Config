local fs = require "nixio.fs"
local sys = require "luci.sys"
local util = require "luci.util"
local uci = require("luci.model.uci").cursor()

local json_available, json = pcall(require, "luci.jsonc")
if not json_available then
	json_available, json = pcall(require, "cjson")
end

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

	local status_file = "/tmp/ginet_modem_status.json"
	if fs.access(status_file) then
		local handle = io.open(status_file, "r")
		if handle then
			local payload = handle:read("*a")
			handle:close()
			if json_available and json and payload and payload ~= "" then
				local ok, parsed = pcall(function()
					if json.parse then
						return json.parse(payload)
					end
					return json.decode(payload)
				end)
				if ok and type(parsed) == "table" then
					for key, value in pairs(parsed) do
						modem_status[key] = value
					end
				end
			end
		end
	end

	return modem_status
end

ensure_defaults()
local modem_status = read_modem_status()
local active_slot = modem_status.active_slot == "sim2" and "sim2" or "sim1"
local supported_modes = parse_csv_list(modem_status.supported_network_modes or "auto")
if #supported_modes == 0 then
	supported_modes = { "auto" }
end

m = Map("ginet_modem", translate("Cellular & APNs"),
	translate("Manage modem status, active SIM preferences, and APN profiles for GL.iNet XE-3000 compatible cellular routers."))

local cellular = m:section(NamedSection, "settings", "modem", translate("Cellular"),
	translate("Primary modem controls and live modem status."))
cellular.addremove = false
cellular.anonymous = true

local o = cellular:option(DummyValue, "_device", translate("Modem Device"))
o.rawhtml = true
o.default = modem_status.device ~= "Not detected"
	and ('<strong>' .. modem_status.device .. '</strong>')
	or '<span style="color:#a00;"><strong>' .. translate("Not detected") .. '</strong></span>'

o = cellular:option(DummyValue, "_sim_inserted", translate("SIM Inserted"))
o.default = modem_status.sim_inserted or translate("Unknown")

o = cellular:option(DummyValue, "_sim_status", translate("SIM Status"))
o.default = modem_status.sim_status or translate("Unknown")

o = cellular:option(DummyValue, "_carrier", translate("Carrier / Operator"))
o.default = modem_status.carrier or translate("Unknown")

o = cellular:option(DummyValue, "_connection_type", translate("Connection Type"))
o.default = modem_status.connection_type or translate("Disconnected")

o = cellular:option(DummyValue, "_data_status", translate("Data Session"))
o.default = modem_status.data_status or translate("Disconnected")

o = cellular:option(DummyValue, "_signal", translate("Signal Strength"))
o.default = modem_status.signal ~= "N/A"
	and string.format("%s dBm", modem_status.signal)
	or translate("Unavailable")

o = cellular:option(ListValue, "active_slot", translate("Active SIM / Slot"),
	translate("The selected SIM profile is applied to network.wwan and can stay active while the other profile remains editable."))
o:value("sim1", translate("SIM 1"))
o:value("sim2", translate("SIM 2"))
o.default = active_slot

local imei_value = modem_status.imei or get_uci("settings", "imei", "N/A")
o = cellular:option(DummyValue, "_imei", translate("IMEI In Use"))
o.default = imei_value

if tostring(modem_status.imei_editable or "0") == "1" then
	o = cellular:option(Value, "imei", translate("Editable IMEI"),
		translate("Only shown when the modem/backend exposes a writable IMEI control path."))
	o.placeholder = imei_value ~= "N/A" and imei_value or "123456789012345"
	o.rmempty = true
	function o.validate(self, value)
		if not value or value == "" then
			return value
		end
		if value:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d$") then
			return value
		end
		return nil, translate("IMEI must contain exactly 15 digits.")
	end
else
	o = cellular:option(DummyValue, "_imei_note", translate("IMEI Capability"))
	o.rawhtml = true
	o.default = '<span style="color:#666;">' ..
		translate("This modem currently exposes one shared IMEI. Per-SIM IMEI switching/editing is unavailable, so only the active modem IMEI is shown.") ..
		'</span>'
end

o = cellular:option(ListValue, "network_mode", translate("Preferred Network Mode"),
	translate("Only advertised modem modes are listed. Unsupported generations stay hidden."))
for _, mode in ipairs(supported_modes) do
	o:value(mode, mode_label(mode))
end
o.default = modem_status.preferred_network_mode or "auto"

local ttl = cellular:option(Value, "ttl", translate("TTL"),
	translate("Persist a TTL override. Runtime application is attempted only when firewall tooling is present."))
ttl.placeholder = "64"
ttl.rmempty = true
function ttl.validate(self, value)
	local validated = validate_integer_range(value, 1, 255, true)
	if validated ~= nil then
		return validated
	end
	return nil, translate("TTL must be a whole number between 1 and 255.")
end

o = cellular:option(Flag, "enabled", translate("Enable Cellular Settings Application"),
	translate("When disabled, APN profiles still persist but modem/network changes are not actively applied."))
o.default = get_uci("settings", "enabled", "1")
o.rmempty = false

local apn_info = m:section(TypedSection, "apn", translate("APNs"),
	translate("Each SIM profile stays editable even when inactive. The currently selected active SIM is highlighted below."))
apn_info.addremove = false
apn_info.anonymous = false

function apn_info.cfgsections()
	return { "sim1", "sim2" }
end

function apn_info.sectiontitle(self, section)
	local label = get_uci(section, "name", section == "sim1" and "SIM 1" or "SIM 2")
	local state = section == active_slot and translate("Active") or translate("Inactive")
	return string.format("%s (%s)", label, state)
end

local function add_network_mode_choices(option)
	for _, mode in ipairs(supported_modes) do
		option:value(mode, mode_label(mode))
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
