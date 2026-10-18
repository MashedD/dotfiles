-- Fixed header/clock, clipped content, and bottom scrollbar with owned teardown.
local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local cairo = require("lgi").cairo
local M = {}
function M.create(options)
    local s, content = options.screen, options.content
    local appearance, interaction = options.appearance, options.interaction
    local ui = interaction.lifetime()
    local palette, bar_height = appearance.palette, 12
    local offset, maximum, content_height, viewport_height = 0, 0, 1, 1
    local hovered, dragging, release_timer = false, false, nil
    local view, bar, column = wibox.widget.base.make_widget(), wibox.widget.base.make_widget(), wibox.widget.base.make_widget()
    local component = {view = view, bar = bar, widget = column, ui = ui}
    local patterns = {}
    for state, name in pairs({normal = "scrollbar", hover = "scrollbar_hover", dragging = "scrollbar_drag"}) do
        patterns[state] = appearance.gradient(name, bar_height)
    end
    local function update_state()
        bar._interaction_state = dragging and "dragging" or (hovered and "hover" or "normal")
        bar:emit_signal("widget::redraw_needed")
    end
    local module_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
    local spring = dofile(module_dir .. "scroll-spring.lua").new(function()
        view:emit_signal("widget::layout_changed")
        view:emit_signal("widget::redraw_needed")
    end, interaction.monotonic_time)
    ui.add(spring.reset)
    function component.set_offset(value)
        if ui.disposed then return end
        offset = math.max(0, math.min(maximum, value))
        options.on_scroll(offset)
        view:emit_signal("widget::layout_changed"); view:emit_signal("widget::redraw_needed")
        bar:emit_signal("widget::redraw_needed")
    end
    function component.scroll_by(delta)
        local requested = offset + delta
        local bounded = math.max(0, math.min(maximum, requested))
        if maximum > 0 and math.abs(delta) <= 160 and requested ~= bounded then
            spring.kick(requested - bounded)
        else spring.reset() end
        component.set_offset(bounded)
    end
    function component.offset() return offset end
    function component.max() return maximum end
    function component.thumb_geometry(width)
        if maximum <= 0 then return 0, width end
        local size = math.min(width, math.max(24, math.floor(width * viewport_height / content_height)))
        return (width - size) * offset / maximum, size
    end
    view.fit = function(_, _, width, height) return width, math.min(height, view.forced_height or height) end
    view.draw = function() end
    view.before_draw_children = function(_, _, cr, width, height)
        cr:save(); cr:rectangle(0, 0, width, height); cr:clip()
    end
    view.after_draw_children = function(_, _, cr, width, height)
        local fade_height = math.min(38, height)
        if maximum > offset + 1 then
            local gradient = cairo.LinearPattern.create(0, height - fade_height, 0, height)
            gradient:add_color_stop_rgba(0, 0, 0, 0, 0); gradient:add_color_stop_rgba(1, 0, 0, 0, 0.72)
            cr:set_source(gradient); cr:rectangle(0, height - fade_height, width, fade_height); cr:fill()
        end
        if offset > 1 then
            local gradient = cairo.LinearPattern.create(0, 0, 0, fade_height)
            gradient:add_color_stop_rgba(0, 0, 0, 0, 0.72); gradient:add_color_stop_rgba(1, 0, 0, 0, 0)
            cr:set_source(gradient); cr:rectangle(0, 0, width, fade_height); cr:fill()
        end
        cr:restore()
    end
    view.layout = function(_, _, width)
        return {wibox.widget.base.place_widget_at(content, 0, -offset - spring.value(), width, content_height)}
    end
    bar.visible, bar.forced_height = false, 0
    bar.fit = function(_, _, width) return width, bar_height end
    bar.draw = function(_, _, cr, width, height)
        cr:set_source(gears.color(palette.scrollbar_track)); cr:rectangle(0, 0, width, height); cr:fill()
        cr:set_source(gears.color(palette.scrollbar_rail)); cr:rectangle(0, math.floor(height / 2) - 2, width, 4); cr:fill()
        local x, size = component.thumb_geometry(width)
        cr:set_source(patterns[bar._interaction_state or "normal"]); cr:rectangle(x, 1, size, height - 2); cr:fill()
        cr:set_source(gears.color(palette.scrollbar_highlight)); cr:rectangle(x + 1, 1, math.max(0, size - 2), 1); cr:fill()
    end
    local bar_panel = wibox {
        screen = s, type = "utility", visible = false, ontop = true,
        width = options.width - 2, height = bar_height,
        x = s.geometry.x + s.geometry.width - options.width + 2, y = s.geometry.y + s.geometry.height - bar_height,
        bg = palette.scrollbar_track, border_width = 0, restrict_workarea = false,
    }
    bar_panel:setup {bar, bg = palette.scrollbar_track, widget = wibox.container.background}
    component.bar_panel = bar_panel
    local watch
    function component.cancel_drag()
        if dragging then interaction.stop_grab(component) end
        dragging, hovered = false, false
        if watch.started then watch:stop() end
        if release_timer and release_timer.started then release_timer:stop() end
        options.on_suppress(false)
        update_state()
    end
    column.fit = function(_, _, width, height) return width, height end
    column.layout = function(_, context, width, height)
        if ui.disposed then return {} end
        component.context, component.content_width = context, width
        local panel = options.panel()
        local hh, ch = options.header.forced_height, options.clock.forced_height
        local fixed = hh + ch
        local full_height = math.max(1, height - fixed)
        local _, measured = wibox.widget.base.fit_widget(column, context, content, width, 2^20)
        local needs_bar = measured > full_height
        local previous_max = maximum
        content_height, viewport_height = measured, math.max(1, full_height - (needs_bar and bar_height or 0))
        maximum = math.max(0, content_height - viewport_height)
        offset = math.max(0, math.min(maximum, offset))
        options.on_scroll(offset)
        bar.visible, bar.forced_height = needs_bar, needs_bar and bar_height or 0
        view.forced_height = viewport_height
        bar_panel.visible = needs_bar and panel ~= nil and panel.visible or false
        bar_panel.x = (panel and panel.x or (s.geometry.x + s.geometry.width - options.width)) + 2
        bar_panel.y = (panel and panel.y or (s.geometry.y + 30)) + fixed + viewport_height
        bar_panel.width, bar_panel.height = width, bar_height
        if dragging and not bar_panel.visible then component.cancel_drag() end
        if previous_max ~= maximum then bar:emit_signal("widget::redraw_needed") end
        return {
            wibox.widget.base.place_widget_at(options.header, 0, 0, width, hh),
            wibox.widget.base.place_widget_at(options.clock, 0, hh, width, ch),
            wibox.widget.base.place_widget_at(view, 0, fixed, width, viewport_height),
        }
    end
    local grab_offset
    local function from_pointer(x)
        local panel = options.panel()
        local track_x = (panel and panel.x or (s.geometry.x + s.geometry.width - options.width)) + 2
        local width = options.width - 2
        local size = select(2, component.thumb_geometry(width))
        local fraction = math.max(0, math.min(1, (x - track_x - (grab_offset or size / 2)) / math.max(1, width - size)))
        component.set_offset(fraction * maximum)
    end
    ui.connect(bar, "mouse::enter", function() hovered = true; update_state() end)
    ui.connect(bar, "mouse::leave", function() hovered = false; update_state() end)
    watch = gears.timer {timeout = 0.05, callback = function()
        local panel = options.panel()
        if dragging and (not s.valid or not panel.visible or not bar.visible or not interaction.owns_grab(component)) then
            component.cancel_drag()
        end
    end}
    ui.add(component.cancel_drag)
    bar:buttons(gears.table.join(awful.button({}, 1, function()
        if mousegrabber.isrunning() or ui.disposed then return end
        if release_timer then release_timer:stop() end
        spring.reset()
        local thumb_x, thumb_size = component.thumb_geometry(options.width - 2)
        local local_x = mouse.coords().x - bar_panel.x
        grab_offset = local_x >= thumb_x and local_x <= thumb_x + thumb_size
            and (local_x - thumb_x) or thumb_size / 2
        options.on_suppress(true); dragging = true; update_state(); watch:start()
        from_pointer(mouse.coords().x)
        local started = interaction.start_grab(component, function(pointer)
            local panel = options.panel()
            if not dragging or not s.valid or not panel.visible or ui.disposed then
                dragging = false; if watch.started then watch:stop() end; options.on_suppress(false); update_state(); return false
            end
            from_pointer(pointer.x)
            if pointer.buttons[1] then return true end
            dragging = false
            hovered = pointer.x >= bar_panel.x and pointer.x < bar_panel.x + bar_panel.width
                and pointer.y >= bar_panel.y and pointer.y < bar_panel.y + bar_panel.height
            if watch.started then watch:stop() end
            update_state()
            release_timer = gears.timer.start_new(0.18, function() options.on_suppress(false); return false end)
            return false
        end, "sb_h_double_arrow")
        if not started then component.cancel_drag() end
    end)))
    function component.attach(panel)
        ui.connect(panel, "property::visible", function()
            bar_panel.visible = panel.visible and bar.visible
            if not panel.visible then spring.reset(); component.cancel_drag() end
        end)
    end
    function component.destroy()
        if ui.disposed then return end
        ui.destroy()
        bar:buttons({}); bar_panel.visible = false; bar_panel.widget = nil
    end
    return component
end
return M
