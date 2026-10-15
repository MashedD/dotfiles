-- One collector per session, independent of screen/widget lifetimes.
local M = {}

function M.new(runtime)
    local collectors = {}
    local service = {collectors = collectors}
    local function stale(c)
        return c.state.updated ~= nil and (c.state.error ~= nil
            or runtime.now() - c.state.updated >= 2 * c.interval)
    end
    local function equal(a, b)
        if a == b then return true end
        if type(a) ~= "table" or type(b) ~= "table" then return false end
        -- Sample timestamps are metadata; they alone do not represent new data.
        for key, value in pairs(a) do
            if key ~= "now" and not equal(value, b[key]) then return false end
        end
        for key in pairs(b) do
            if key ~= "now" and a[key] == nil then return false end
        end
        return true
    end
    local function notify(c)
        for listener in pairs(c.listeners) do
            local ok, err = pcall(listener, c.state)
            if not ok and runtime.log then runtime.log(err) end
        end
    end
    local function publish_if_changed(c, old_stale, old_error, old_value)
        c.state.stale = stale(c)
        if old_stale ~= c.state.stale or old_error ~= c.state.error
            or not equal(old_value, c.state.value) then notify(c) end
    end
    function service.define(name, interval, fetch)
        assert(not collectors[name], "duplicate collector: " .. name)
        collectors[name] = {interval = interval, fetch = fetch, listeners = {}, state = {}, generation = 0}
    end
    function service.refresh(name)
        local c = assert(collectors[name], name)
        if not next(c.listeners) then return end
        local old_stale, old_error, old_value = c.state.stale, c.state.error, c.state.value
        c.state.stale = stale(c)
        if old_stale ~= c.state.stale then notify(c) end
        if c.pending then return end
        c.pending = true
        c.requests = (c.requests or 0) + 1
        local generation, completed = c.generation, false
        local function done(value, err)
            if completed or generation ~= c.generation then return end
            completed, c.pending, c.cancel = true, false, nil
            old_stale, old_error, old_value = c.state.stale, c.state.error, c.state.value
            if value ~= nil then
                c.state.value, c.state.updated, c.state.error = value, runtime.now(), nil
            else
                c.state.error = err or "Unavailable"
            end
            publish_if_changed(c, old_stale, old_error, old_value)
        end
        local ok, cancel = pcall(c.fetch, done)
        if not ok then
            done(nil, tostring(cancel))
        elseif type(cancel) == "function" then
            if generation ~= c.generation then pcall(cancel)
            elseif not completed then c.cancel = cancel end
        end
    end
    function service.subscribe(name, listener)
        local c = assert(collectors[name], name)
        c.listeners[listener] = true
        c.state.stale = stale(c)
        local ok, err = pcall(listener, c.state)
        if not ok and runtime.log then runtime.log(err) end
        if not c.timer then
            c.timer = runtime.timer {timeout = c.interval, autostart = true,
                callback = function() service.refresh(name) end}
            service.refresh(name)
        end
        local stopped = false
        return {timeout = c.interval, stop = function()
            if stopped then return end
            stopped = true
            c.listeners[listener] = nil
            if not next(c.listeners) then
                c.timer:stop()
                c.timer, c.pending = nil, false
                c.generation = c.generation + 1
                local cancel = c.cancel
                c.cancel = nil
                if cancel then
                    local ok, err = pcall(cancel)
                    if not ok and runtime.log then runtime.log(err) end
                end
            end
        end}
    end
    function service.state(name)
        local c = assert(collectors[name], name)
        c.state.stale = stale(c)
        return c.state
    end
    return service
end

function M.parse_weather(stdout)
    local current = stdout:match('"current"%s*:%s*{([^}]+)}')
    local function field(name)
        return current and tonumber(current:match('"' .. name .. '"%s*:%s*([%-0-9.]+)'))
    end
    local t, apparent, condition, wind = field("temperature_2m"), field("apparent_temperature"),
        field("weather_code"), field("wind_speed_10m")
    if not t or not apparent or not condition or not wind or condition < 0 or wind < 0 then return nil end
    return {temperature = t, apparent = apparent, condition = condition, wind = wind}
end
function M.parse_crypto(stdout)
    local display = stdout:gsub("#%b[]", ""):gsub("%s+$", "")
    local btc, eth, ltc = display:match("BTC%s+(%S+)%s+ETH%s+(%S+)%s+LTC%s+(%S+)")
    local result = {}
    for key, value in pairs({BTC = btc, ETH = eth, LTC = ltc}) do
        value = value:gsub("^%$", "")
        if not value:match("^%d[%d.,]*$") then return nil end
        result[key] = value
    end
    if not result.BTC or not result.ETH or not result.LTC then return nil end
    return result
end
function M.parse_codex(stdout)
    local display, dates = stdout:match("^(.-)\t([^\r\n]+)")
    display = (display or stdout):gsub("#%b[]", ""):gsub("^C%*?%s*", ""):gsub("%s+$", "")
    local five, five_reset, week, week_reset = display:match(
        "5h%s+(%d+)%%@([%a]+%s+%d%d:%d%d)%s+7d%s+(%d+)%%@([%a]+%s+%d%d:%d%d)")
    five, week = tonumber(five), tonumber(week)
    if not five or not week or five > 100 or week > 100 then return nil end
    return {five = five, five_reset = five_reset, week = week, week_reset = week_reset,
        resets = dates and dates ~= "--" and dates:gsub(" · ", "\n") or "--"}
end

-- Injectable runtime above permits deterministic lifecycle/failure tests without X11.
if not awesome then return M end
local gears = require("gears")
local awful = require("awful")
local Gio = require("lgi").Gio
local service = M.new {now = os.time, timer = gears.timer,
    log = function(err) io.stderr:write("sidebar collector: " .. tostring(err) .. "\n") end}
service.parsers = M
function service.command(argv, parse, done)
    local command = {"timeout", "--kill-after=2s", "20s"}
    for _, arg in ipairs(argv) do command[#command + 1] = arg end
    local ok, pid = pcall(awful.spawn.easy_async, command, function(stdout, _, _, code)
        if code ~= 0 then
            done(nil, code == 124 and "Request timed out" or "Command failed (" .. tostring(code) .. ")")
            return
        end
        local parsed, value = pcall(parse, stdout)
        if not parsed or value == nil then done(nil, "Invalid response") else done(value) end
    end)
    if not ok or type(pid) ~= "number" then done(nil, tostring(pid or "Could not start command")) end
end
local home = assert(os.getenv("HOME"))
service.define("weather", 1800, function(done)
    service.command({"curl", "--fail", "--silent", "--show-error", "--max-time", "12",
        "https://api.open-meteo.com/v1/forecast?latitude=53.1235&longitude=17.9871"
        .. "&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m&timezone=Europe%2FWarsaw"},
        M.parse_weather, done)
end)
service.define("crypto", 60, function(done)
    service.command({home .. "/.local/bin/crypto-prices"}, M.parse_crypto, done)
end)
service.define("codex", 60, function(done)
    service.command({home .. "/.local/bin/codex-usage", "--sidebar"}, M.parse_codex, done)
end)
service.define("volume", 3, function(done)
    service.command({"wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"}, function(stdout)
        local level = tonumber(stdout:match("Volume:%s+([%d.]+)"))
        return level and {level = level, muted = stdout:find("MUTED", 1, true) ~= nil} or nil
    end, done)
end)
service.define("media", 5, function(done)
    service.command({"playerctl", "metadata", "--format", "{{artist}} — {{title}}"},
        function(stdout) return stdout:gsub("%s+$", "") end, function(value)
            -- No running player is an ordinary empty state, not a stale track.
            done(value or "")
        end)
end)
service.define("trash", 30, function(done)
    local ok, value = pcall(function()
        local enumerator = Gio.File.new_for_uri("trash:///"):enumerate_children("standard::name", 0)
        local read_ok, child = pcall(function() return enumerator:next_file() end)
        pcall(function() enumerator:close() end)
        if not read_ok then error("Cannot read Trash") end
        return {full = child ~= nil}
    end)
    done(ok and value or nil, "Cannot read Trash")
end)
return service
