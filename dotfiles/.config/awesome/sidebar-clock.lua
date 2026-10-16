-- Analog/digital clock component. The parent supplies appearance and containers.
local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local cairo = require("lgi").cairo
local M = {}
local function analog_clock()
    local clock = wibox.widget.base.make_widget()
    clock.forced_width, clock.forced_height = 112, 112
    clock.fit = function() return 112, 112 end
    clock.current_time = os.date("*t")
    clock.draw = function(_, _, cr, width, height)
        local size = math.min(width, height)
        local cx, cy = width / 2, height / 2
        local radius = size / 2 - 3
        local now = clock.current_time or os.date("*t")
        local pi, tau = math.pi, 2 * math.pi
        cr:set_line_cap(cairo.LineCap.ROUND)
        cr:arc(cx + 1, cy + 2, radius, 0, tau)
        cr:set_source_rgba(0, 0, 0, 0.5)
        cr:fill()
        cr:arc(cx, cy, radius, 0, tau)
        cr:set_source_rgba(0.44, 0.77, 0.74, 0.96)
        cr:set_line_width(2.5)
        cr:fill_preserve()
        cr:set_source_rgba(0.78, 1, 0.91, 0.9)
        cr:set_line_width(1)
        cr:stroke()
        local face_radius = radius - 4
        cr:arc(cx, cy, face_radius, 0, tau)
        cr:save()
        cr:clip()
        local face = cairo.RadialPattern.create(cx - face_radius * 0.28, cy - face_radius * 0.34,
            face_radius * 0.04, cx, cy, face_radius * 1.1)
        face:add_color_stop_rgba(0, 0.20, 0.65, 0.36, 1)
        face:add_color_stop_rgba(0.65, 0.06, 0.36, 0.19, 1)
        face:add_color_stop_rgba(1, 0.01, 0.12, 0.07, 1)
        cr:set_source(face)
        cr:paint()
        cr:move_to(cx - face_radius * 0.78, cy - face_radius * 0.19)
        cr:curve_to(cx - face_radius * 0.58, cy - face_radius * 0.88,
            cx + face_radius * 0.48, cy - face_radius * 0.90,
            cx + face_radius * 0.78, cy - face_radius * 0.19)
        cr:curve_to(cx + face_radius * 0.36, cy - face_radius * 0.43,
            cx - face_radius * 0.30, cy - face_radius * 0.43,
            cx - face_radius * 0.78, cy - face_radius * 0.19)
        cr:close_path()
        cr:set_source_rgba(0.83, 1, 0.91, 0.13)
        cr:fill()
        cr:restore()
        cr:arc(cx, cy, face_radius, 0, tau)
        cr:set_source_rgba(0.44, 0.77, 0.74, 0.8)
        cr:set_line_width(1)
        cr:stroke()
        for index = 0, 59 do
            local angle = index * tau / 60 - pi / 2
            local major = index % 5 == 0
            local inner = face_radius * (major and 0.82 or 0.91)
            local outer = face_radius * 0.94
            cr:set_source_rgba(major and 0.74 or 0.58, major and 0.93 or 0.82,
                major and 0.82 or 0.76, major and 0.98 or 0.78)
            cr:set_line_width(major and 1.8 or 0.8)
            cr:move_to(cx + math.cos(angle) * inner, cy + math.sin(angle) * inner)
            cr:line_to(cx + math.cos(angle) * outer, cy + math.sin(angle) * outer)
            cr:stroke()
        end
        cr:select_font_face("Microsoft Sans Serif", cairo.FontSlant.NORMAL, cairo.FontWeight.BOLD)
        cr:set_font_size(face_radius * 0.19)
        cr:set_source_rgba(0.88, 1, 0.93, 0.96)
        for hour = 1, 12 do
            local angle = hour * tau / 12 - pi / 2
            local text = tostring(hour)
            local extents = cr:text_extents(text)
            local text_radius = face_radius * 0.69
            local x = cx + math.cos(angle) * text_radius
            local y = cy + math.sin(angle) * text_radius
            cr:move_to(x - extents.width / 2 - extents.x_bearing,
                y - extents.height / 2 - extents.y_bearing)
            cr:show_text(text)
        end
        local function hand(angle, length, shaft, head, red, green, blue, alpha)
            local ux, uy = math.cos(angle), math.sin(angle)
            local px, py = -uy, ux
            local base = length * 0.70
            cr:move_to(cx + px * shaft, cy + py * shaft)
            cr:line_to(cx + ux * base + px * shaft, cy + uy * base + py * shaft)
            cr:line_to(cx + ux * (length - head * 0.45), cy + uy * (length - head * 0.45))
            cr:line_to(cx + ux * length, cy + uy * length)
            cr:line_to(cx + ux * (length - head * 0.45), cy + uy * (length - head * 0.45))
            cr:line_to(cx + ux * base - px * shaft, cy + uy * base - py * shaft)
            cr:line_to(cx - px * shaft, cy - py * shaft)
            cr:close_path()
            cr:set_source_rgba(red, green, blue, alpha)
            cr:fill()
        end
        local minute = now.min + now.sec / 60
        local hour = (now.hour % 12) + minute / 60
        hand(hour * tau / 12 - pi / 2, face_radius * 0.47, face_radius * 0.045,
            face_radius * 0.14, 0.88, 1, 0.93, 0.98)
        hand(minute * tau / 60 - pi / 2, face_radius * 0.68, face_radius * 0.027,
            face_radius * 0.12, 0.44, 0.77, 0.74, 1)
        local seconds = now.sec * tau / 60 - pi / 2
        cr:set_source_rgba(0, 1, 0.25, 1)
        cr:set_line_width(math.max(1, face_radius * 0.018))
        cr:move_to(cx - math.cos(seconds) * face_radius * 0.16,
            cy - math.sin(seconds) * face_radius * 0.16)
        cr:line_to(cx + math.cos(seconds) * face_radius * 0.76,
            cy + math.sin(seconds) * face_radius * 0.76)
        cr:stroke()
        cr:arc(cx, cy, face_radius * 0.075, 0, tau)
        cr:set_source_rgba(0.87, 1, 0.93, 1)
        cr:fill_preserve()
        cr:set_source_rgba(0.16, 0.45, 0.30, 1)
        cr:set_line_width(1)
        cr:stroke()
    end
    return clock
end
function M.create(options)
    local ui = options.interaction.lifetime()
    local palette, label = options.appearance.palette, options.label
    local clock = analog_clock()
    local digital = label("00:00:00", palette.neon, 24, true, "center")
    local date = label("", palette.teal, 13, true, "center")
    local centered = wibox.widget {clock, halign = "center", valign = "center", widget = wibox.container.place}
    local content = wibox.layout.fixed.vertical()
    content.spacing = 3
    content:add(date); content:add(centered); content:add(digital)
    local widget = options.card(content, 142)
    local component = {widget = widget, clock = clock, digital = digital, date = date, ui = ui}
    function component.set_mode(mode)
        if ui.disposed then return end
        component.mode = mode
        clock.visible, centered.visible, digital.visible = mode == "analog", mode == "analog", mode == "text"
        widget.forced_height = mode == "analog" and 142 or 66
        options.on_mode(mode)
    end
    function component.toggle() component.set_mode(component.mode == "analog" and "text" or "analog") end
    for _, control in ipairs({clock, digital}) do
        control:buttons(gears.table.join(awful.button({}, 1, component.toggle)))
        if options.dismiss then ui.connect(control, "button::press", options.dismiss) end
        ui.tip(control, "Click to switch analog / digital clock")
    end
    function component.tick(timestamp)
        if ui.disposed then return end
        timestamp = timestamp or os.time()
        local now = os.date("*t", timestamp)
        local second = os.date("%H:%M:%S", timestamp)
        local day = os.date("%Y-%m-%d", timestamp)
        if component.last_second ~= second then
            component.last_second = second
            clock.current_time = now
            clock:emit_signal("widget::redraw_needed")
            digital.markup = string.format("<span foreground='%s' size='24pt' weight='bold'>%s</span>", palette.neon, second)
        end
        if component.last_day ~= day then
            component.last_day = day
            date.markup = string.format("<span foreground='%s' size='12pt' weight='bold'>%s</span>",
                palette.teal, os.date("%A  •  %d %B %Y", timestamp))
        end
    end
    function component.destroy()
        if ui.disposed then return end
        ui.destroy()
        clock:buttons({}); digital:buttons({})
    end
    component.set_mode("text")
    return component
end
return M
