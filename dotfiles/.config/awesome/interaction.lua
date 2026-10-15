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
        local tip = awful.tooltip {objects = {widget}, text = text, delay_show = 0.5}
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

-- The geometry supplied by Awesome's button event includes the allocated size.
-- Do not compete with an existing drag/resize grab.
function M.bind_button(widget, options, group)
    local hovering, grabbing, bounds = false, false
    local state = M.press_state {
        valid = function() return not group.disposed and options.valid() end,
        activate = options.activate,
        changed = function(s) options.paint(s.armed and s.inside, hovering) end,
    }
    local watchdog
    local function cancel()
        if grabbing then mousegrabber.stop() end
        grabbing, hovering = false, false
        if watchdog then watchdog:stop() end
        state.cancel()
    end
    group.connect(widget, "mouse::enter", function() hovering = true; state.move(true) end)
    group.connect(widget, "mouse::leave", function() hovering = false; state.move(false) end)
    group.connect(widget, "button::press", function(_, x, y, button, _, geometry)
        if mousegrabber.isrunning() or not state.press(button) then return end
        local origin = mouse.coords()
        bounds = {x = origin.x - x, y = origin.y - y,
            width = geometry and geometry.width or widget.forced_width,
            height = geometry and geometry.height or widget.forced_height}
        grabbing = true
        mousegrabber.run(function(pointer)
            if not grabbing or not options.valid() or group.disposed then
                grabbing = false; state.cancel(); watchdog:stop(); return false
            end
            local inside = pointer.x >= bounds.x and pointer.x < bounds.x + bounds.width
                and pointer.y >= bounds.y and pointer.y < bounds.y + bounds.height
            hovering = inside
            state.move(inside)
            if pointer.buttons[1] then return true end
            grabbing = false
            watchdog:stop()
            state.release(1, inside)
            return false
        end, "left_ptr")
        watchdog:start()
    end)
    watchdog = gears.timer {timeout = 0.05, callback = function()
        if grabbing and (not options.valid() or not mousegrabber.isrunning()) then cancel() end
    end}
    group.add(function() cancel(); state.destroy() end)
    return {state = state, cancel = cancel}
end
return M
