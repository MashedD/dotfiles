-- Executable preflight plus immediate-spawn diagnostics; never wait for app exit.
local M = {}
local function xml_escape(text)
    return tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
        :gsub('"', "&quot;"):gsub("'", "&apos;")
end
function M.new(deps)
    local service = {}
    local function notify(label, message)
        local ok, err = pcall(deps.notify, label, message)
        if not ok and deps.log then deps.log("Quick Launch [" .. label .. "]: " .. tostring(err)) end
    end
    function service.missing(entry)
        for _, executable in ipairs(entry.requires or {entry.argv[1]}) do
            local resolved = executable:sub(1, 1) == "/" and executable or deps.resolve(executable)
            local ok, usable = false, false
            if resolved then ok, usable = pcall(deps.executable, resolved) end
            if not ok or not usable then return executable end
        end
        return nil
    end
    function service.run(entry)
        local missing = service.missing(entry)
        if missing then
            notify(entry.label, "Missing executable: " .. missing)
            return false, missing
        end
        local ok, pid, secondary = pcall(deps.spawn, entry.argv)
        if not ok or type(pid) ~= "number" then
            local reason = tostring(ok and (pid or secondary) or pid)
            notify(entry.label, "Could not start " .. entry.argv[1] .. ": " .. reason)
            return false, reason
        end
        return true, pid
    end
    function service.tooltip(entry)
        local missing = service.missing(entry)
        return xml_escape(missing and (entry.label .. " · Missing: " .. missing) or entry.label)
    end
    return service
end
if not awesome then return M end
local awful = require("awful")
local gears = require("gears")
local GLib = require("lgi").GLib
return M.new {
    resolve = function(name) return GLib.find_program_in_path(name) end,
    executable = gears.filesystem.file_executable,
    spawn = awful.spawn,
    notify = function(label, message)
        local ok, pid = pcall(awful.spawn, {"notify-send", "Quick Launch · " .. label, message})
        if not ok or type(pid) ~= "number" then
            io.stderr:write("Quick Launch [" .. label .. "]: " .. message .. "\n")
        end
    end,
}
