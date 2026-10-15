-- Small, testable release-to-activate state machine and owned UI lifetimes.
local M = {}
function M.press_state(options)
    local state = {armed = false, inside = false, destroyed = false}
    local function update() if options.changed then options.changed(state) end end
    function state.cancel()
        state.armed, state.inside = false, false
        update()
    end
    function state.press(button)
        if button ~= 1 or state.destroyed or not options.valid() then return false end
        state.armed, state.inside = true, true
        update()
        return true
    end
    function state.move(inside)
        state.inside = inside
        if not options.valid() then state.cancel() else update() end
    end
    function state.release(button, inside)
        if button ~= 1 then return end
        local activate = state.armed and inside and not state.destroyed and options.valid()
        state.cancel()
        if activate then options.activate() end
    end
    function state.destroy() state.destroyed = true; state.cancel() end
    return state
end
local function modifiers_match(actual, expected)
    local function normalize(modifiers)
        local result = {}
        for _, modifier in ipairs(modifiers or {}) do
            if modifier ~= "Lock" and modifier ~= "Mod2" then result[#result + 1] = modifier end
        end
        table.sort(result)
        return result
    end
    actual, expected = normalize(actual), normalize(expected)
    if #actual ~= #expected then return false end
    for index, modifier in ipairs(actual) do if modifier ~= expected[index] then return false end end
    return true
end
M.modifiers_match = modifiers_match
function M.transition_value(current, target, start_time, duration, sample_time)
    if duration <= 0 or sample_time >= start_time + duration then return target end
    if sample_time <= start_time then return current end
    local progress = (sample_time - start_time) / duration
    return current + (target - current) * progress
end
function M.monotonic_time()
    return require("lgi").GLib.get_monotonic_time() / 1000000
end
function M.deduplicate_paint(paint)
    local last_pressed, last_hovered
    return function(pressed, hovered)
        if pressed == last_pressed and hovered == last_hovered then return false end
        last_pressed, last_hovered = pressed, hovered
        paint(pressed, hovered)
        return true
    end
end
local grab_owner
function M.start_grab(owner, callback, cursor)
    if grab_owner or mousegrabber.isrunning() then return false end
    grab_owner = owner
    mousegrabber.run(function(pointer, ...)
        if grab_owner ~= owner then return false end
        local keep = callback(pointer, ...)
        if not keep and grab_owner == owner then grab_owner = nil end
        return keep
    end, cursor)
    if not mousegrabber.isrunning() then
        if grab_owner == owner then grab_owner = nil end
        return false
    end
    return true
end
function M.stop_grab(owner)
    if grab_owner ~= owner then return false end
    grab_owner = nil
    if mousegrabber.isrunning() then mousegrabber.stop() end
    return true
end
function M.owns_grab(owner)
    return grab_owner == owner and mousegrabber.isrunning()
end
if not awesome then return M end
local awful = require("awful")
local gears = require("gears")

function M.lifetime()
    local group = {disposed = false, cleanups = {}, tooltips = {}}
    function group.add(cleanup) group.cleanups[#group.cleanups + 1] = cleanup end
    function group.connect(object, signal, callback)
        object:connect_signal(signal, callback)
        group.add(function() object:disconnect_signal(signal, callback) end)
    end
    function group.tip(widget, text)
        local args = {objects = {widget}, delay_show = 0.5}
        if type(text) == "function" then args.timer_function = text else args.text = text end
        local tip = awful.tooltip(args)
        group.tooltips[#group.tooltips + 1] = tip
        group.add(function()
            tip.hide() -- also stops Awesome's private delayed-show timer
            tip:remove_from_object(widget)
        end)
        return tip
    end
    function group.destroy()
        if group.disposed then return end
        group.disposed = true
        for i = #group.cleanups, 1, -1 do group.cleanups[i]() end
        group.cleanups = {}
    end
    return group
end

local function widget_geometry(drawable, widget, preferred_hierarchy)
    if not drawable or not drawable._widget_hierarchy then return nil end
    local ok, result = pcall(function()
        local drawin = drawable.drawable
        if not drawin or drawin.valid == false or drawin.visible == false then return nil end
        local window_geometry = drawin:geometry()
        local function bounds_for(hierarchy)
            local width, height = hierarchy:get_size()
            local x, y, w, h = hierarchy:get_matrix_to_device():transform_rectangle(0, 0, width, height)
            return {drawable = drawable, window = drawin, hierarchy = hierarchy,
                x = (window_geometry.x or 0) + x, y = (window_geometry.y or 0) + y,
                width = w, height = h}
        end
        if preferred_hierarchy and preferred_hierarchy:get_widget() == widget then
            return bounds_for(preferred_hierarchy)
        end
        local function find(hierarchy)
            if hierarchy:get_widget() == widget then return bounds_for(hierarchy) end
            for _, child in ipairs(hierarchy:get_children()) do
                local match = find(child)
                if match then return match end
            end
        end
        return find(drawable._widget_hierarchy)
    end)
    return ok and result or nil
end

local function same_geometry(a, b)
    if not a or not b or a.window ~= b.window then return false end
    local epsilon = 0.75
    return math.abs(a.x-b.x) <= epsilon and math.abs(a.y-b.y) <= epsilon
        and math.abs(a.width-b.width) <= epsilon and math.abs(a.height-b.height) <= epsilon
end

-- Track the exact widget bounds and drawable for the lifetime of each grab.
function M.bind_button(widget, options, group)
    options.modifiers = options.modifiers or {}
    local hovering, grabbing, bounds = false, false, nil
    local grab_token = {}
    local paint = M.deduplicate_paint(options.paint)
    local state = M.press_state {
        valid = function() return not group.disposed and options.valid() end,
        activate = options.activate,
        changed = function(s) paint(s.armed and s.inside, hovering) end,
    }
    local watchdog
    local function cancel()
        if grabbing then M.stop_grab(grab_token) end
        grabbing, hovering, bounds = false, false, nil
        if watchdog and watchdog.started then watchdog:stop() end
        state.cancel()
    end
    local function still_valid()
        if group.disposed or not options.valid() or not bounds then return false end
        local current = widget_geometry(bounds.drawable, widget, bounds.hierarchy)
        return current and same_geometry(bounds, current) or false
    end
    group.connect(widget, "mouse::enter", function() hovering = true; state.move(true) end)
    group.connect(widget, "mouse::leave", function() hovering = false; state.move(false) end)
    group.connect(widget, "button::press", function(_, _, _, button, modifiers, geometry)
        if mousegrabber.isrunning() or not modifiers_match(modifiers, options.modifiers) then return end
        local found = geometry and widget_geometry(geometry.drawable, widget)
        if not found or found.width <= 0 or found.height <= 0 or not options.valid()
            or not state.press(button) then return end
        bounds = found
        grabbing = true
        local started = M.start_grab(grab_token, function(pointer)
            if not grabbing or not still_valid() then
                grabbing = false; state.cancel()
                if watchdog.started then watchdog:stop() end
                return false
            end
            local inside = pointer.x >= bounds.x and pointer.x < bounds.x + bounds.width
                and pointer.y >= bounds.y and pointer.y < bounds.y + bounds.height
            hovering = inside
            state.move(inside)
            if pointer.buttons[1] then return true end
            grabbing = false
            if watchdog.started then watchdog:stop() end
            state.release(1, inside)
            return false
        end, "left_ptr")
        if not started then
            grabbing = false; bounds = nil; state.cancel()
            return
        end
        watchdog:start()
    end)
    watchdog = gears.timer {timeout = 0.05, callback = function()
        if grabbing and (not still_valid() or not M.owns_grab(grab_token)) then cancel() end
    end}
    group.add(function() cancel(); state.destroy() end)
    return {state = state, cancel = cancel}
end
return M
