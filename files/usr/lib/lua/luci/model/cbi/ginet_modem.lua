-- GiNet Cell Modem Configuration CBI (Configurable Binding Interface)
-- Web interface for displaying and configuring cellular modem settings
-- Compatible with: GiNet XE-3000 Puli AX, Quectel RM520N-GL
-- Supports IMEI changes for legally-repurposed devices (GL.iNet firmware)

require("luci.sys")
require("luci.util")
require("luci.ip")

local json_available, json = pcall(require, "cjson")

-- Try to read modem status from JSON file
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
	
	-- Try to read file
	if nixio.fs.access(status_file) then
		local f = io.open(status_file, "r")
		if f then
			local json_str = f:read("*a")
			f:close()
			
			-- Simple JSON parsing
			if json_available and json then
				local success, data = pcall(json.parse, json_str)
				if success then
					modem_status = data
				end
			else
				-- Manual parsing without JSON library
				modem_status.imei = string.match(json_str, '"imei"%s*:%s*"([^"]*)"') or modem_status.imei
				modem_status.apn = string.match(json_str, '"apn"%s*:%s*"([^"]*)"') or modem_status.apn
				modem_status.signal = string.match(json_str, '"signal"%s*:%s*(-?%d+)') or modem_status.signal
				modem_status.connection_type = string.match(json_str, '"connection_type"%s*:%s*"([^"]*)"') or modem_status.connection_type
				modem_status.data_status = string.match(json_str, '"data_status"%s*:%s*"([^"]*)"') or modem_status.data_status
				modem_status.sim_status = string.match(json_str, '"sim_status"%s*:%s*"([^"]*)"') or modem_status.sim_status
				modem_status.device = string.match(json_str, '"device"%s*:%s*"([^"]*)"') or modem_status.device
			end
		end
	end
	
	return modem_status
end

-- Main map definition
m = Map("ginet_modem", translate("Cell Modem Settings"), 
	translate("Configure IMEI and APN settings for your GiNet XE-3000 Puli AX cellular modem (Quectel RM520N-GL)"))

-- Get current modem status
local modem_status = read_modem_status()

-- =====================================================
-- STATUS SECTION (Read-only display)
-- =====================================================

s_status = m:section(NamedSection, "settings", "modem", translate("Current Modem Status"))
s_status.addremove = false
s_status.anonymous = true

-- Device info
o = s_status:option(DummyValue, "_status_device", translate("Modem Device"))
o.rawhtml = true
if modem_status.device and modem_status.device ~= "Not detected" then
	o.default = '<span style="color: green;"><strong>' .. modem_status.device .. '</strong></span>'
else
	o.default = '<span style="color: red;"><strong>Not detected</strong></span>'
end

-- IMEI display
o = s_status:option(DummyValue, "_status_imei", translate("Device IMEI"))
o.rawhtml = true
o.default = modem_status.imei or "Unknown"

-- Current APN display
o = s_status:option(DummyValue, "_status_apn", translate("Current APN"))
o.rawhtml = true
o.default = modem_status.apn or "Not configured"

-- Connection Status
o = s_status:option(DummyValue, "_status_connection", translate("Connection Type"))
o.rawhtml = true
local conn_type = modem_status.connection_type or "Disconnected"
local conn_color = "red"
if string.find(conn_type, "5G") then
	conn_color = "darkgreen"
elseif string.find(conn_type, "4G") or string.find(conn_type, "LTE") then
	conn_color = "green"
elseif string.find(conn_type, "Connected") then
	conn_color = "green"
end
o.default = '<span style="color: ' .. conn_color .. ';"><strong>' .. conn_type .. '</strong></span>'

-- Data Status
o = s_status:option(DummyValue, "_status_data", translate("Data Connection"))
o.rawhtml = true
local data_status = modem_status.data_status or "Disconnected"
local data_color = "green"
if string.find(data_status, "Disconnected") then
	data_color = "red"
end
o.default = '<span style="color: ' .. data_color .. ';"><strong>' .. data_status .. '</strong></span>'

-- Signal Strength
o = s_status:option(DummyValue, "_status_signal", translate("Signal Strength"))
o.rawhtml = true
local signal = modem_status.signal or "N/A"
if signal ~= "N/A" then
	local signal_color = "red"
	local signal_bars = "📶"
	local sig_num = tonumber(signal) or -999
	if sig_num >= -85 then
		signal_color = "darkgreen"
		signal_bars = "📶📶📶📶"
	elseif sig_num >= -95 then
		signal_color = "green"
		signal_bars = "📶📶📶"
	elseif sig_num >= -105 then
		signal_color = "orange"
		signal_bars = "📶📶"
	end
	o.default = '<span style="color: ' .. signal_color .. ';"><strong>' .. signal .. ' dBm</strong></span> ' .. signal_bars
else
	o.default = '<span style="color: red;"><strong>No Signal</strong></span>'
end

-- SIM Status
o = s_status:option(DummyValue, "_status_sim", translate("SIM Card Status"))
o.rawhtml = true
local sim_status = modem_status.sim_status or "Unknown"
local sim_color = "orange"
if string.find(sim_status, "ready") or string.find(sim_status, "Ready") then
	sim_color = "green"
elseif string.find(sim_status, "not") or string.find(sim_status, "No") then
	sim_color = "red"
end
o.default = '<span style="color: ' .. sim_color .. ';"><strong>' .. sim_status .. '</strong></span>'

-- Last Update Time
o = s_status:option(DummyValue, "_status_update", translate("Last Updated"))
o.rawhtml = true
if modem_status.timestamp then
	o.default = '<small>' .. modem_status.timestamp .. '</small>'
else
	o.default = '<small>' .. os.date("%Y-%m-%d %H:%M:%S") .. '</small>'
end

-- =====================================================
-- CONFIGURATION SECTION (Editable settings)
-- =====================================================

s_config = m:section(NamedSection, "settings", "modem", translate("Configuration"))
s_config.addremove = false
s_config.anonymous = true

-- APN Configuration
o = s_config:option(Value, "apn", translate("Access Point Name (APN)"),
	translate("Enter your carrier's APN. Common examples: internet (AT&T), h2g2 (T-Mobile), uninet (Verizon)"))
o.placeholder = "internet"
o.datatype = "string"
o.rmempty = false

-- Enabled Flag
o = s_config:option(Flag, "enabled", translate("Enable Cellular Modem"),
	translate("Enable or disable cellular data connection"))
o.default = 1
o.rmempty = false

-- IMEI Configuration (Editable for GL.iNet firmware)
-- Legal for devices no longer in active service (e.g., repurposed devices)
o = s_config:option(Value, "imei", translate("Device IMEI"),
	translate("International Mobile Equipment Identity (15 digits). GL.iNet firmware supports changes for legally-repurposed devices. Legal use: devices no longer in active service."))
o.placeholder = "123456789012345"
o.datatype = "string"
o.rmempty = true

-- =====================================================
-- LEGAL NOTICE SECTION
-- =====================================================

s_legal = m:section(NamedSection, "settings", "modem", translate("⚠️ Legal Notice - IMEI Changes"))
s_legal.addremove = false
s_legal.anonymous = true

o = s_legal:option(DummyValue, "_legal_notice", translate("Important Information"))
o.rawhtml = true
o.default = [[
<div style="background: #fff3cd; border: 1px solid #ffc107; padding: 12px; border-radius: 4px; margin: 10px 0;">
	<strong>⚠️ IMEI Change - Legal Use Only</strong><br/><br/>
	IMEI (International Mobile Equipment Identity) changes are <strong>legal</strong> in the following cases:<br/>
	<ul style="margin: 8px 0; padding-left: 20px;">
		<li>Device is no longer in active service (e.g., damaged, broken, retired)</li>
		<li>Device is being repurposed with legally-obtained IMEI sources</li>
		<li>You own both the device and the IMEI being transferred</li>
		<li>Local laws permit such changes</li>
	</ul><br/>
	
	<strong>⛔ IMEI changes are ILLEGAL if:</strong><br/>
	<ul style="margin: 8px 0; padding-left: 20px;">
		<li>Device is still in active service by another person</li>
		<li>IMEI is from a stolen or unauthorized device</li>
		<li>Used to evade carrier contracts or regulations</li>
		<li>Your country/region prohibits IMEI changes</li>
	</ul><br/>
	
	<em style="color: #666;">GL.iNet firmware enables IMEI changes via AT commands for flexibility in device repurposing.</em>
</div>
]]

-- =====================================================
-- CARRIER PRESETS (Optional)
-- =====================================================

s_presets = m:section(TypedSection, "modem", translate("Quick APN Presets"))
s_presets.addremove = false
s_presets.template = "cbi/tblsection"

-- Note about presets
o = s_presets:option(DummyValue, "_presets_help", translate("Preset APNs"))
o.rawhtml = true
o.default = [[
<div style="background: #f9f9f9; padding: 10px; border-radius: 5px; margin-bottom: 10px;">
	<strong>Common Carriers (manual entry):</strong><br/>
	<ul style="margin: 5px 0; padding-left: 20px;">
		<li><strong>AT&T:</strong> internet</li>
		<li><strong>Verizon:</strong> uninet</li>
		<li><strong>T-Mobile:</strong> h2g2</li>
		<li><strong>Sprint:</strong> sprint</li>
		<li><strong>Generic:</strong> internet.local</li>
	</ul>
	<p style="font-size: 12px; color: #666; margin: 5px 0;">
		<em>⚠️ Not sure about your APN? Contact your carrier or check their documentation.</em>
	</p>
</div>
]]

-- =====================================================
-- ADVANCED SECTION (Info about device)
-- =====================================================

s_info = m:section(NamedSection, "settings", "modem", translate("Device Information"))
s_info.addremove = false
s_info.anonymous = true

o = s_info:option(DummyValue, "_info_device", translate("Supported Device"))
o.default = "GiNet XE-3000 Puli AX (GL-XE3000)"

o = s_info:option(DummyValue, "_info_modem", translate("Modem Chipset"))
o.default = "Quectel RM520N-GL (5G/4G)"

o = s_info:option(DummyValue, "_info_cpu", translate("Router CPU"))
o.default = "MediaTek Filogic (dual-core @ 1.3 GHz)"

o = s_info:option(DummyValue, "_info_interface", translate("Modem Interface"))
o.default = "QMI (Qualcomm MSM Interface) / CDC-WDM"

-- =====================================================
-- Handle form submission
-- =====================================================

function m.on_save(self)
	-- Get the new APN and IMEI values
	local apn = self.uci:get("ginet_modem", "settings", "apn")
	local imei = self.uci:get("ginet_modem", "settings", "imei")
	local enabled = self.uci:get("ginet_modem", "settings", "enabled")
	
	if apn and enabled == "1" then
		-- Build command with APN and optional IMEI
		local cmd = "/usr/bin/apply-ginet-modem-settings.sh '" .. apn:gsub("'", "'\\''") .. "'"
		
		if imei and imei ~= "" then
			cmd = cmd .. " '" .. imei:gsub("'", "'\\''") .. "'"
		end
		
		cmd = cmd .. " 2>&1"
		
		-- Call backend script to apply settings
		local result = luci.sys.call(cmd)
		
		if result == 0 then
			luci.util.exec("/usr/bin/ginet-modem-status.sh > /tmp/ginet_modem_status.json 2>/dev/null &")
		end
	end
end

return m
