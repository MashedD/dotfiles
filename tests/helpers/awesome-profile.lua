-- Private-copy instrumentation only. No arguments, output, or document contents recorded.
local clock = function() return require('lgi').GLib.get_monotonic_time() / 1000000 end
local P = {
    phase = 'startup', buckets = {}, collectors = {}, intervals = {},
    drawables = setmetatable({}, {__mode='k'}),
    cache = {builds=0,releases=0,bytes=0,peak=0},
}
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
function P.install_rendering_attribution()
    local allowed_roles = {
        calendar=true, todo=true, ['quick-launch']=true, ['system-status']=true,
        codex=true, crypto=true, weather=true, ['now-playing']=true,
        wallpaper=true, clock=true, header=true,
    }
    local allowed_properties = {text=true, markup=true, visible=true, value=true, color=true}
    P.widget_roles = setmetatable({}, {__mode='k'})
    P.tag_widget_tree = function(root, role, screen_index)
        if not allowed_roles[role] or type(root) ~= 'table' or type(screen_index) ~= 'number'
            or screen_index < 1 or screen_index % 1 ~= 0 then return 0 end
        local visited, count = setmetatable({}, {__mode='k'}), 0
        local function visit(widget)
            if type(widget) ~= 'table' or visited[widget] then return end
            visited[widget] = true
            if not P.widget_roles[widget] then
                P.widget_roles[widget] = {role=role, screen=screen_index}
                count = count + 1
            end
            if type(widget.get_children) == 'function' then
                for _, child in ipairs(widget:get_children() or {}) do visit(child) end
            end
        end
        visit(root)
        return count
    end
    P.widget_update = function(widget, property, changed)
        if P.phase ~= 'measured' or not allowed_properties[property] then return end
        local target = P.widget_roles[widget]
        if not target then return end
        P.count(string.format('update.screen%d.%s.%s.%s', target.screen, target.role,
            property, changed and 'changed' or 'unchanged'))
    end
    P.wrap_attribution_draw = function(widget, screen_index, role)
        if type(widget.draw) ~= 'function' or type(screen_index) ~= 'number'
            or screen_index < 1 or screen_index % 1 ~= 0 or not allowed_roles[role] then return false end
        P.attribution_wrapped_fields = P.attribution_wrapped_fields
            or setmetatable({}, {__mode='k'})
        if P.attribution_wrapped_fields[widget] ~= nil then return false end
        local field = rawget(widget, 'draw')
        if field == nil then P.attribution_wrapped_fields[widget] = false
        else P.attribution_wrapped_fields[widget] = field end
        local name = string.format('draw.depth16.screen%d.%s', screen_index, role)
        rawset(widget, 'draw', P.wrap(name, widget.draw, false))
        return true
    end
    local function is_textbox(widget)
        if type(widget.draw) ~= 'function' then return false end
        local info = debug.getinfo(widget.draw, 'S')
        return info and info.source and info.source:match('/wibox/widget/textbox%.lua$') ~= nil
    end
    P.bind_attribution = function()
        local targets = 0
        for s in screen do
            for id, section in pairs(s.sidebar_sections or {}) do
                if section.body then P.tag_widget_tree(section.body, id, s.index) end
                if section.header then P.tag_widget_tree(section.header, 'header', s.index) end
            end
            P.tag_widget_tree(s.sidebar_header, 'header', s.index)
            local clock = s.sidebar_components and s.sidebar_components.clock
            if clock and clock.widget then P.tag_widget_tree(clock.widget, 'clock', s.index) end
            if s.sidebar_clock then P.tag_widget_tree(s.sidebar_clock, 'clock', s.index) end
            local drawable = s.sidebar and s.sidebar._drawable
            local root = drawable and drawable._widget_hierarchy
            assert(root, 'Sidebar hierarchy is not ready for attribution')
            local function visit(node, depth)
                local widget = node:get_widget()
                local target = P.widget_roles[widget]
                if target and depth == 16 and is_textbox(widget) then
                    if P.wrap_attribution_draw(widget, target.screen, target.role) then
                        P.count(string.format('attribution.target.screen%d.%s', target.screen, target.role))
                        targets = targets + 1
                    end
                end
                for _, child in ipairs(node:get_children()) do visit(child, depth + 1) end
            end
            visit(root, 0)
        end
        return targets
    end
end
function P.install_rendering_breakdown()
    local hierarchy = require('wibox.hierarchy')
    local original = hierarchy.draw
    local frames, node_info, wrapped_widgets, widget_classes = {}, setmetatable({}, {__mode='k'}),
        setmetatable({}, {__mode='k'}), setmetatable({}, {__mode='k'})
    local level = 0
    local function widget_class(widget)
        local callback = widget.draw
        if type(callback) ~= 'function' then return 'no_draw' end
        local info = debug.getinfo(callback, 'S')
        local source = info and info.source or ''
        local name = source:match('/wibox/[^/]+/([%w_.-]+)%.lua$')
        return name and ('wibox.' .. name) or 'custom'
    end
    local function info_for(node, target)
        local info = node_info[node]
        if info then return info end
        local depth, parent = 0, node._parent
        while parent do depth, parent = depth + 1, parent._parent end
        local widget = node:get_widget()
        local class = widget_classes[widget] or widget_class(widget)
        widget_classes[widget] = class
        local prefix = 'hierarchy.sidebar.screen' .. target.screen
        info = {
            depth=depth, class=class,
            inclusive=string.format('%s.node.%s.depth%d.inclusive', prefix, class, depth),
            exclusive=string.format('%s.node.%s.depth%d.exclusive', prefix, class, depth),
            callback=string.format('draw.callback.sidebar.screen%d.%s.depth%d', target.screen, class, depth),
            total=depth == 0 and (prefix .. '.total') or nil,
        }
        node_info[node] = info
        P.wrap_widget_draw(widget)
        return info
    end
    P.wrap_widget_draw = function(widget)
        if wrapped_widgets[widget] then return end
        local callback = widget.draw
        if type(callback) ~= 'function' then return end
        wrapped_widgets[widget] = true
        widget_classes[widget] = widget_classes[widget] or widget_class(widget)
        P.count('draw_wrapper_installed')
        local original_field = rawget(widget, 'draw')
        P.draw_wrapped_fields = P.draw_wrapped_fields or setmetatable({}, {__mode='k'})
        if original_field == nil then P.draw_wrapped_fields[widget] = false
        else P.draw_wrapped_fields[widget] = original_field end
        rawset(widget, 'draw', function(self, ...)
            local frame = frames[level]
            if not frame then return callback(self, ...) end
            local started = clock()
            local result = table.pack(callback(self, ...))
            P.sample(frame.callback, clock() - started)
            return unpack(result, 1, result.n)
        end)
    end
    hierarchy.draw = function(node, context, cr)
        local target = context and P.drawables[context.drawable]
        if not target or target.name ~= 'sidebar' then return original(node, context, cr) end
        local info = info_for(node, target)
        level = level + 1
        local frame = frames[level]
        if not frame then frame = {}; frames[level] = frame end
        frame.child_time, frame.callback = 0, info.callback
        local started = clock()
        original(node, context, cr)
        local elapsed = clock() - started
        level = level - 1
        if level > 0 then frames[level].child_time = frames[level].child_time + elapsed end
        P.sample(info.inclusive, elapsed)
        P.sample(info.exclusive, math.max(0, elapsed - frame.child_time))
        if info.total then P.sample(info.total, elapsed) end
    end
end
function P.bind_rendering()
    for s in screen do
        for _,name in ipairs({'panel','sidebar','sidebar_scrollbar_panel'}) do
            local box=s[name]
            if box then
                local drawable=assert(box._drawable,'Missing private drawable: '..name)
                P.drawables[drawable] = {name=name, screen=s.index}
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
    for widget, original in pairs(P.draw_wrapped_fields or {}) do
        if original == false then rawset(widget, 'draw', nil)
        else rawset(widget, 'draw', original) end
    end
    for widget, original in pairs(P.attribution_wrapped_fields or {}) do
        if original == false then rawset(widget, 'draw', nil)
        else rawset(widget, 'draw', original) end
    end
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
