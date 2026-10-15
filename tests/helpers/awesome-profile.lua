-- Private-copy instrumentation only. No arguments, output, or document contents recorded.
local clock = function() return require('lgi').GLib.get_monotonic_time() / 1000000 end
local P = {phase = 'startup', buckets = {}, collectors = {}, intervals = {}, cache = {builds=0,releases=0,bytes=0,peak=0}}
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
    b.total = (b.total or 0) + value
    if #b.values < 10000 then b.values[#b.values+1] = value end
    if started and P.phase == 'measured' and #P.intervals < 10000 then
        P.intervals[#P.intervals+1] = {started, clock(), name}
    end
end
function P.wrap(name, callback, intervals)
    return function(...)
        local started = clock()
        local result = table.pack(pcall(callback, ...))
        P.sample(name, clock()-started, intervals~=false and started or nil)
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
function P.cache_event(kind,bytes,duration)
    if kind=='build' then
        P.cache.builds=P.cache.builds+1;P.cache.bytes=P.cache.bytes+bytes
        P.cache.peak=math.max(P.cache.peak,P.cache.bytes)
        P.sample('cache.build',duration)
    else P.cache.releases=P.cache.releases+1;P.cache.bytes=P.cache.bytes-bytes end
end
function P.install_rendering()
    local background=require('wibox.container.background')
    for _,method in ipairs({'draw','before_draw_children','after_draw_children'}) do
        local original=background[method]
        if original then
            local wrappers={}
            background[method]=function(self,context,...)
                local screen=context and context.screen
                local label='paint.background.'..method..'.screen'..tostring(screen and screen.index or 'unknown')
                wrappers[label]=wrappers[label] or P.wrap(label,original,false)
                return wrappers[label](self,context,...)
            end
        end
    end
end
function P.bind_rendering()
    for s in screen do
        for _,name in ipairs({'panel','sidebar','sidebar_scrollbar_panel'}) do
            local box=s[name]
            if box then
                local drawable=assert(box._drawable,'Missing private drawable: '..name)
                local label=name..'.screen'..s.index
                drawable._do_redraw=P.wrap('redraw.'..label,drawable._do_redraw,false)
                local request=drawable.draw
                drawable.draw=function(...)
                    P.count('redraw_request.'..label)
                    return request(...)
                end
                if name=='sidebar' then
                    local root=drawable.widget
                    for _,method in ipairs({'fit','layout'}) do
                        if type(root[method])=='function' then
                            root[method]=P.wrap('root.'..method..'.'..label,root[method],false)
                        end
                    end
                    -- Validate the hooks once in warm-up; steady-state layouts
                    -- can then legitimately remain cached without any callbacks.
                    if root.emit_signal then root:emit_signal('widget::layout_changed') end
                end
            end
        end
        s.sidebar_clock.draw=P.wrap('draw.clock.screen'..s.index,s.sidebar_clock.draw,false)
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
        lines[#lines+1] = string.format('%s\t%d\t%d\t%.9f\t%.9f\t%.9f\t%.9f', key, b.count,
            #b.values, percentile(b.values, 0.5), percentile(b.values, 0.95), b.values[#b.values] or 0,b.total or 0)
    end
    for name, c in pairs(P.collectors) do
        local listeners=0; for _ in pairs(c.listeners) do listeners=listeners+1 end
        lines[#lines+1] = string.format('collector:%s\t%d\t%d\t%d\t0\t0', name, c.interval, listeners, c.requests or 0)
    end
    for name,value in pairs(P.cache) do
        lines[#lines+1]=string.format('cachemeta:%s\t%d\t0\t0\t0\t0',name,value)
    end
    lines[#lines+1] = 'IDLE_END'
    P.phase = 'finished'
    return table.concat(lines, '\n')
end
return P
