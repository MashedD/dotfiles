-- Private-copy instrumentation only. No arguments, output, or document contents recorded.
local clock = function() return require('lgi').GLib.get_monotonic_time() / 1000000 end
local P = {phase = 'startup', buckets = {}, collectors = {}, intervals = {}}
local unpack = table.unpack
local function bucket(name)
    local key = P.phase .. ':' .. name
    P.buckets[key] = P.buckets[key] or {count=0, values={}}
    return P.buckets[key]
end
function P.count(name)
    local b = bucket(name); b.count = b.count + 1
end
function P.sample(name, value, started)
    local b = bucket(name); b.count = b.count + 1
    if #b.values < 10000 then b.values[#b.values+1] = value end
    if started and P.phase == 'measured' and #P.intervals < 10000 then
        P.intervals[#P.intervals+1] = {started, clock(), name}
    end
end
function P.wrap(name, callback)
    return function(...)
        local started = clock()
        local result = table.pack(pcall(callback, ...))
        P.sample(name, clock()-started, started)
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2, result.n)
    end
end
function P.fetch(name, callback)
    return function(done)
        local started, phase, completed = clock(), P.phase, false
        P.count('request.' .. name)
        return P.wrap('sync.' .. name, callback)(function(...)
            if not completed then
                completed = true
                if phase == P.phase then P.sample('latency.' .. name, clock()-started) end
            end
            return done(...)
        end)
    end
end
function P.notify(callback)
    return function(c)
        return P.wrap('notify.' .. c.name, callback)(c)
    end
end
function P.install_spawn()
    local awful = require('awful')
    local original = awful.spawn.easy_async
    awful.spawn.easy_async = function(argv, callback)
        local executable = type(argv) == 'table' and argv[1] or ''
        local category = executable:match('([^/]+)$') or 'other'
        if category == 'timeout' and argv[4] then category = argv[4]:match('([^/]+)$') end
        local allowed = {wpctl=true, playerctl=true, curl=true, ['crypto-prices']=true, ['codex-usage']=true}
        if not allowed[category] then category = 'other' end
        P.count('spawn.' .. category)
        return original(argv, function(stdout, stderr, reason, code)
            P.count('exit.' .. category .. '.' .. tostring(code))
            return callback(stdout, stderr, reason, code)
        end)
    end
end
function P.begin()
    P.phase = 'measured'
    P.last_beat = clock()
    P.heartbeat = require('gears').timer {timeout=0.1, autostart=true, callback=function()
        local now = clock()
        local late = math.max(0, now-P.last_beat-0.1)
        P.sample('heartbeat.lateness', late)
        if late > 0.01 then
            for _, interval in ipairs(P.intervals) do
                if interval[2] >= P.last_beat and interval[1] <= now then
                    P.count('overlap.' .. interval[3])
                end
            end
        end
        P.last_beat = now
    end}
end
local function percentile(values, fraction)
    if #values == 0 then return 0 end
    return values[math.max(1, math.ceil(#values*fraction))]
end
function P.finish()
    if P.heartbeat then P.heartbeat:stop() end
    local lines = {'IDLE_BEGIN'}
    for key, b in pairs(P.buckets) do
        table.sort(b.values)
        lines[#lines+1] = string.format('%s\t%d\t%d\t%.9f\t%.9f\t%.9f', key, b.count,
            #b.values, percentile(b.values, 0.5), percentile(b.values, 0.95), b.values[#b.values] or 0)
    end
    for name, c in pairs(P.collectors) do
        local listeners=0; for _ in pairs(c.listeners) do listeners=listeners+1 end
        lines[#lines+1] = string.format('collector:%s\t%d\t%d\t%d\t0\t0', name, c.interval, listeners, c.requests or 0)
    end
    lines[#lines+1] = 'IDLE_END'
    P.phase = 'finished'
    return table.concat(lines, '\n')
end
return P
