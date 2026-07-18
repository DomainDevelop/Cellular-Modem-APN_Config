local sys = require "luci.sys"
local fs = require "nixio.fs"
local util = require "luci.util"

m = Map("ginet_modem", translate("Cell Watch"),
	translate("Rogue-tower / IMSI-catcher HEURISTICS and coarse tower-based location. " ..
		"This is not true IMSI-catcher detection: most modems do not expose raw " ..
		"baseband data. Alerts (forced 2G/3G downgrade, unexpected Cell ID changes) " ..
		"are hints, not proof."))

-- Live status --------------------------------------------------------------
live = m:section(SimpleSection, translate("Current Serving Cell"))

status = live:option(DummyValue, "_status")
status.rawhtml = true
function status.cfgvalue()
	local raw = fs.readfile("/tmp/ginet_cellwatch.json") or ""
	if raw == "" then
		return "<em>" .. translate("No data yet. Enable Cell Watch and wait for the first poll.") .. "</em>"
	end
	local function field(k)
		return raw:match('"' .. k .. '"%s*:%s*"([^"]*)"') or ""
	end
	local enabled = raw:match('"enabled"%s*:%s*(%a+)') or "false"
	if enabled ~= "true" then
		return "<em>" .. translate("Cell Watch is disabled.") .. "</em>"
	end
	local rat = field("rat")
	local mcc, mnc = field("mcc"), field("mnc")
	local lac, cid = field("lac"), field("cell_id")
	local sig = field("signal_dbm")
	local lat, lon = field("latitude"), field("longitude")
	local ts = field("timestamp")

	local rows = {}
	local function row(label, val)
		if val and val ~= "" then
			rows[#rows + 1] = string.format("<tr><td style='padding-right:1em'><strong>%s</strong></td><td>%s</td></tr>",
				util.pcdata(label), util.pcdata(val))
		end
	end
	row(translate("Radio Access"), rat)
	row(translate("MCC / MNC"), (mcc ~= "" and (mcc .. " / " .. mnc)) or "")
	row(translate("LAC / TAC"), lac)
	row(translate("Cell ID"), cid)
	row(translate("Signal (dBm)"), sig)
	if lat ~= "" and lon ~= "" then
		row(translate("Approx. Location"), lat .. ", " .. lon ..
			string.format(" (<a href='https://www.openstreetmap.org/?mlat=%s&mlon=%s#map=14/%s/%s' target='_blank' rel='noopener'>map</a>)",
				lat, lon, lat, lon))
	end
	row(translate("Updated"), ts)

	local html = "<table>" .. table.concat(rows) .. "</table>"

	-- Alerts array.
	local alerts_blob = raw:match('"alerts"%s*:%s*%[(.-)%]')
	if alerts_blob and alerts_blob:match('%S') then
		local items = {}
		for a in alerts_blob:gmatch('"([^"]+)"') do
			items[#items + 1] = "<li>" .. util.pcdata(a) .. "</li>"
		end
		if #items > 0 then
			html = html .. "<div style='margin-top:0.5em;color:#a00'><strong>" ..
				translate("Alerts") .. ":</strong><ul>" .. table.concat(items) .. "</ul></div>"
		end
	end
	return html
end

-- Settings -----------------------------------------------------------------
s = m:section(NamedSection, "settings", "cellwatch", translate("Settings"))
s.addremove = false

en = s:option(Flag, "enabled", translate("Enable Cell Watch"))
en.default = 0

interval = s:option(Value, "interval_minutes", translate("Poll interval (minutes)"))
interval.datatype = "range(1,60)"
interval.default = "5"
interval:depends("enabled", "1")

dg = s:option(Flag, "alert_downgrade", translate("Alert on 2G/3G downgrade"))
dg.default = 1
dg:depends("enabled", "1")

cc = s:option(Flag, "alert_cellid_change", translate("Alert on unexpected Cell ID / LAC change"))
cc.default = 1
cc:depends("enabled", "1")

loc = s:option(Flag, "location_enabled", translate("Coarse location (offline DB)"))
loc.default = 0
loc:depends("enabled", "1")
loc.description = translate("Resolves the serving cell to approximate coordinates using a LOCAL " ..
	"offline CSV database only (cell IDs are never sent to the network). Accuracy is " ..
	"coarse (hundreds of metres to kilometres).")

db = s:option(Value, "location_db", translate("Offline cell database path"))
db.default = "/etc/ginet/cell_db.csv"
db.datatype = "maxlength(128)"
db:depends("location_enabled", "1")
db.description = translate("CSV with columns: mcc,mnc,lac,cid,lat,lon")

function m.on_after_commit(self)
	sys.call("/etc/init.d/ginet-stealth reload >/dev/null 2>&1")
	sys.call("/usr/bin/ginet-cell-monitor.sh run >/dev/null 2>&1 &")
end

return m
