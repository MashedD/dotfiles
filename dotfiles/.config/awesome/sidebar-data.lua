-- One collector per session, independent of screen/widget lifetimes.
local M = {}
-- Source samples are refreshed every 60s; allow one missed cycle.
M.SOURCE_MAX_AGE = 120

function M.new(runtime)
    local collectors = {}
    local service = {collectors = collectors}
    local function stale(c)
        if c.state.updated == nil then return false end
        local age = runtime.now() - c.state.updated
        return c.state.error ~= nil or age < 0 or age >= (c.max_age or 2 * c.interval)
    end
    local function equal(a, b)
        if a == b then return true end
        if type(a) ~= "table" or type(b) ~= "table" then return false end
        -- Sample timestamps are metadata; they alone do not represent new data.
        for key, value in pairs(a) do
            if key ~= "now" and key ~= "source_updated" and not equal(value, b[key]) then return false end
        end
        for key in pairs(b) do
            if key ~= "now" and key ~= "source_updated" and a[key] == nil then return false end
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
    local function accept(c, value, err)
        local old_stale, old_error, old_value = c.state.stale, c.state.error, c.state.value
        if value ~= nil then
            local old_revision = type(old_value) == "table" and tonumber(old_value.revision)
            local new_revision = type(value) == "table" and tonumber(value.revision)
            if old_revision and new_revision and new_revision < old_revision then return false end
            local source_updated = type(value) == "table" and value.source_updated or nil
            c.state.value, c.state.updated, c.state.error = value, source_updated or runtime.now(), nil
        else
            c.state.error = err or "Unavailable"
        end
        publish_if_changed(c, old_stale, old_error, old_value)
        return true
    end
    function service.define(name, interval, fetch, max_age)
        assert(not collectors[name], "duplicate collector: " .. name)
        collectors[name] = {interval = interval, max_age = max_age,
            fetch = fetch, listeners = {}, state = {}, generation = 0}
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
            accept(c, value, err)
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
    function service.publish(name, value, err)
        local c = assert(collectors[name], name)
        return accept(c, value, err)
    end
    function service.state(name)
        local c = assert(collectors[name], name)
        c.state.stale = stale(c)
        return c.state
    end
    return service
end

function M.weather_url(latitude, longitude)
    return string.format(
        "https://api.open-meteo.com/v1/forecast?latitude=%.6f&longitude=%.6f"
        .. "&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m&timezone=auto",
        tonumber(latitude) or 53.1235, tonumber(longitude) or 17.9871)
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
    if stdout:match('^%s*STALE') then return nil end
    local display = stdout:gsub("#%b[]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local btc, eth, ltc = display:match("^BTC%s+(%S+)%s+ETH%s+(%S+)%s+LTC%s+(%S+)$")
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
    if stdout:match('^%s*C%*') then return nil end
    local display, dates = stdout:match("^(.-)\t([^\r\n]+)")
    display = (display or stdout):gsub("#%b[]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if not display:match('^C%s+') then return nil end
    display = display:gsub('^C%s+', '')
    local five, five_reset, week, week_reset = display:match(
        "^5h%s+(%d+)%%@([%a]+%s+%d%d:%d%d)%s+7d%s+(%d+)%%@([%a]+%s+%d%d:%d%d)$")
    five, week = tonumber(five), tonumber(week)
    if not five or not week or five > 100 or week > 100 then return nil end
    return {five = five, five_reset = five_reset, week = week, week_reset = week_reset,
        resets = dates and dates ~= "--" and dates:gsub(" · ", "\n") or "--"}
end

-- Machine channels retain the source's confirmation time, not helper invocation time.
local function source_sample(stdout,kind,parse,now)
    local status,stamp,body=stdout:gsub('[\r\n]+$',''):match('^'..kind..'%-v1\t([a-z]+)\t(%d+)\t([^\r\n]+)$')
    if not status then return nil,'Missing source freshness metadata' end
    if status~='fresh' then return nil,'Source '..status..'; current value unavailable' end
    stamp=tonumber(stamp); now=now or os.time()
    if not stamp or stamp<=0 or stamp>now or now-stamp>=M.SOURCE_MAX_AGE then return nil,'Source sample expired or clock invalid' end
    local value=parse(body)
    if not value then return nil,'Invalid source response' end
    value.source_updated=stamp
    return value
end
function M.parse_codex_sample(stdout,now) return source_sample(stdout,'codex',M.parse_codex,now) end
function M.parse_crypto_sample(stdout,now) return source_sample(stdout,'crypto',M.parse_crypto,now) end

local function split_fields(line)
    local fields, start = {}, 1
    while true do
        local separator = line:find("\t", start, true)
        if not separator then
            fields[#fields + 1] = line:sub(start)
            return fields
        end
        fields[#fields + 1] = line:sub(start, separator - 1)
        start = separator + 1
    end
end
local function unquote(value)
    if value:gsub("%%[%x][%x]", ""):find("%", 1, true) then return nil end
    return (value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end
function M.parse_news(stdout)
    local lines = {}
    for line in stdout:gmatch("[^\r\n]+") do lines[#lines + 1] = line end
    if #lines == 0 then return nil, "Empty news snapshot" end
    local header = split_fields(lines[1])
    if #header ~= 4 or header[1] ~= "news-v2" then return nil, "Invalid news snapshot header" end
    local revision, source_updated, last_attempt = tonumber(header[2]), tonumber(header[3]), tonumber(header[4])
    if not revision or revision < 0 or not source_updated or source_updated < 0 or not last_attempt then
        return nil, "Invalid news snapshot metadata"
    end
    local result = {revision = revision, source_updated = source_updated, last_attempt = last_attempt,
        categories = {}, category_map = {}, feeds = {}, items = {}, unread = 0}
    for index = 2, #lines do
        local fields = split_fields(lines[index])
        if fields[1] == "category" then
            local label = #fields == 3 and unquote(fields[3]) or nil
            if #fields ~= 3 or not fields[2]:match("^[a-z0-9][a-z0-9_-]*$")
                or fields[2] == "all" or #fields[2] > 32 or not label or label == ""
                or result.category_map[fields[2]] then
                return nil, "Invalid news category record"
            end
            local category = {id = fields[2], label = label}
            result.categories[#result.categories + 1] = category
            result.category_map[category.id] = category
        elseif fields[1] == "feed" then
            if #fields ~= 6 or not result.category_map[fields[3]] then return nil, "Invalid news feed record" end
            local label, status = unquote(fields[4]), unquote(fields[5])
            local last_success = tonumber(fields[6])
            if not fields[2]:match("^[0-9a-f]+$") or #fields[2] < 16 or #fields[2] > 32
                or not label or not status or not last_success then
                return nil, "Invalid news feed metadata"
            end
            result.feeds[#result.feeds + 1] = {id = fields[2], category = fields[3],
                label = label, error = status, last_success = last_success}
        elseif fields[1] == "item" then
            if #fields ~= 9 or not fields[3]:match("^[a-z0-9][a-z0-9_-]*$") or #fields[3] > 32 then
                return nil, "Invalid news item record"
            end
            local source, title, summary, url = unquote(fields[4]), unquote(fields[7]),
                unquote(fields[8]), unquote(fields[9])
            local published = tonumber(fields[5])
            if not fields[2]:match("^[0-9a-f]+$") or #fields[2] ~= 32 or not source or not title or not summary
                or not published or (fields[6] ~= "0" and fields[6] ~= "1") then
                return nil, "Invalid news item fields"
            end
            if url and url ~= "" and not url:match("^https?://[^%s]+$") then
                return nil, "Invalid news item link"
            end
            local item = {id = fields[2], category = fields[3], source = source,
                published = published, read = fields[6] == "1", title = title, summary = summary,
                url = url ~= "" and url or nil}
            result.items[#result.items + 1] = item
            if not item.read then result.unread = result.unread + 1 end
        else
            return nil, "Unknown news snapshot record"
        end
    end
    return result
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
        local parsed, value, reason = pcall(parse, stdout)
        if not parsed or value == nil then done(nil, parsed and reason or "Invalid response") else done(value) end
    end)
    if not ok or type(pid) ~= "number" then done(nil, tostring(pid or "Could not start command")) end
end
local home = assert(os.getenv("HOME"))
local weather_location = {latitude = 53.1235, longitude = 17.9871}
function service.configure(preferences)
    if type(preferences) == "table"
        and type(preferences.latitude) == "number" and type(preferences.longitude) == "number" then
        weather_location = {latitude = preferences.latitude, longitude = preferences.longitude}
    end
end
service.define("weather", 1800, function(done)
    local url = M.weather_url(weather_location.latitude, weather_location.longitude)
    service.command({"curl", "--fail", "--silent", "--show-error", "--max-time", "12", url},
        M.parse_weather, done)
end)
service.define("crypto", 60, function(done)
    service.command({home .. "/.local/bin/crypto-prices", "--sidebar-data"}, M.parse_crypto_sample, done)
end, M.SOURCE_MAX_AGE)
service.define("codex", 60, function(done)
    service.command({home .. "/.local/bin/codex-usage", "--sidebar-data"}, M.parse_codex_sample, done)
end, M.SOURCE_MAX_AGE)
service.define("news", 1800, function(done)
    local helper = home .. "/.local/bin/desktop-news"
    -- Publish cached stories immediately while the bounded feed refresh runs.
    service.command({helper, "snapshot"}, M.parse_news, function(value)
        if value then service.publish("news", value) end
    end)
    service.command({helper, "refresh"}, M.parse_news, done)
end, 3600)
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
