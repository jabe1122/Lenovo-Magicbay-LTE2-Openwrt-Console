local http = require "luci.http"
local util = require "luci.util"

module("luci.controller.mbim_lenovo", package.seeall)

local function run(action)
	local allowed = {
		status = true,
		["ui-start"] = true,
		["ui-stop"] = true,
		["ui-restart"] = true
	}

	if not allowed[action] then
		return "error=bad_action\n"
	end

	return util.exec("/usr/bin/mbim-lenovo-up.sh " .. action .. " 2>/dev/null")
end

local function write_text(text)
	http.prepare_content("text/plain; charset=utf-8")
	http.write(text or "")
end

function index()
	entry({"admin", "services", "mbim_lenovo"}, template("mbim_lenovo/status"), _("Lenovo MagicBay LTE2控制台"), 60).dependent = false
	entry({"admin", "services", "mbim_lenovo", "status"}, call("action_status"), nil).leaf = true
	entry({"admin", "services", "mbim_lenovo", "start"}, call("action_start"), nil).leaf = true
	entry({"admin", "services", "mbim_lenovo", "stop"}, call("action_stop"), nil).leaf = true
	entry({"admin", "services", "mbim_lenovo", "restart"}, call("action_restart"), nil).leaf = true
end

function action_status()
	write_text(run("status"))
end

function action_start()
	write_text(run("ui-start"))
end

function action_stop()
	write_text(run("ui-stop"))
end

function action_restart()
	write_text(run("ui-restart"))
end
