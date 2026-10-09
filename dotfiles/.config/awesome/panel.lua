-- Native Awesome widgets, styled like the previous 30px VAX/Win98 panel.
local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local Gio = require("lgi").Gio
local panel = {}

local function read(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local value = file:read("*l")
    file:close()
    return value
end
local function bevel(widget, inset)
    return wibox.widget {
        {
            {widget, margins = 2, widget = wibox.container.margin},
            bg = "#c0c0c0", fg = "#000000",
            border_width = 1, border_color = inset and "#808080" or "#ffffff",
            widget = wibox.container.background,
        },
        bg = "#c0c0c0", border_width = 1,
        border_color = inset and "#ffffff" or "#404040",
        widget = wibox.container.background,
    }
end
local function separator()
    return wibox.widget {
        forced_width = 3, color = "#808080",
        orientation = "vertical", widget = wibox.widget.separator,
    }
end

function panel.create(s, menu, activate, window_menu)
    local icon = wibox.widget.imagebox()
    local icon_path = (os.getenv("XDG_DATA_HOME") or os.getenv("HOME") .. "/.local/share")
        .. "/icons/hicolor/32x32/apps/vax-tux-start.png"
    if gears.filesystem.file_readable(icon_path) then icon.image = icon_path end
    -- The generated image is the complete 65x25 Start button, text included.
    -- Render at native size, without a second label or shrinking it to 22px.
    icon.forced_width, icon.forced_height, icon.resize = 65, 25, false
    local start = icon
    awful.tooltip {objects = {start}, text = "Start"}
    start:buttons(gears.table.join(awful.button({}, 1, function() menu:toggle() end)))
    s.start_button, s.start_menu = start, menu

    s.taglist = awful.widget.taglist {
        screen = s, filter = awful.widget.taglist.filter.all,
        style = {bg_focus = "#001a00", fg_focus = "#00ff41",
            bg_empty = "#c0c0c0", fg_empty = "#000000",
            bg_occupied = "#c0c0c0", fg_occupied = "#000000"},
        buttons = gears.table.join(
            awful.button({}, 1, function(t) t:view_only() end),
            awful.button({"Mod4"}, 1, function(t)
                if client.focus then client.focus:move_to_tag(t) end
            end),
            -- Up returns to the previous desktop; down advances to the next.
            awful.button({}, 4, function(t) awful.tag.viewprev(t.screen) end),
            awful.button({}, 5, function(t) awful.tag.viewnext(t.screen) end)
        ),
        layout = {spacing = 2, layout = wibox.layout.fixed.horizontal},
        widget_template = {
            {
                {id = "text_role", align = "center", widget = wibox.widget.textbox},
                left = 6, right = 6, widget = wibox.container.margin,
            },
            id = "background_role", border_width = 1, border_color = "#808080",
            widget = wibox.container.background,
        },
    }
    s.tasklist = awful.widget.tasklist {
        screen = s, filter = awful.widget.tasklist.filter.currenttags,
        style = {bg_normal = "#c0c0c0", fg_normal = "#000000",
            bg_focus = "#001a00", fg_focus = "#00ff41",
            bg_minimize = "#c0c0c0", fg_minimize = "#404040"},
        buttons = gears.table.join(
            awful.button({}, 1, function(c)
                if c == client.focus then c.minimized = true else activate(c) end
            end),
            awful.button({}, 3, window_menu),
            awful.button({}, 4, function() awful.client.focus.byidx(1) end),
            awful.button({}, 5, function() awful.client.focus.byidx(-1) end)
        ),
        layout = {spacing = 2, layout = wibox.layout.fixed.horizontal},
        widget_template = {
            {
                {
                    {
                        {id = "icon_role", forced_width = 18, widget = wibox.widget.imagebox},
                        {id = "text_role", widget = wibox.widget.textbox},
                        spacing = 4, layout = wibox.layout.fixed.horizontal,
                    },
                    margins = 3, widget = wibox.container.margin,
                },
                id = "background_role", border_width = 1, border_color = "#808080",
                widget = wibox.container.background,
            },
            width = 180, strategy = "max", widget = wibox.container.constraint,
        },
    }

    local cpu = wibox.widget {
        forced_width = 46, max_value = 1, step_width = 2, step_spacing = 0,
        background_color = "#001a00", color = "#00ff41",
        widget = wibox.widget.graph,
    }
    local cpu_tip = awful.tooltip {objects = {cpu}, text = "CPU"}
    local previous_total, previous_idle
    local battery = wibox.widget.textbox()
    local battery_box = bevel(battery, true)
    local battery_tip = awful.tooltip {objects = {battery}, text = "Battery"}
    local function update_stats()
        local stat = read("/proc/stat")
        if stat then
            local values = {}
            for value in stat:gmatch("%d+") do values[#values + 1] = tonumber(value) end
            -- Guest counters are already included in user/nice; do not double count.
            local total = 0
            for i = 1, math.min(8, #values) do total = total + values[i] end
            local idle = (values[4] or 0) + (values[5] or 0)
            if previous_total and total > previous_total then
                local usage = math.max(0, math.min(1, 1 - (idle - previous_idle) / (total - previous_total)))
                cpu:add_value(usage)
                cpu_tip.text = string.format("CPU: %.0f%%", usage * 100)
            end
            previous_total, previous_idle = total, idle
        end
        local root = "/sys/class/power_supply/"
        local enumerator = Gio.File.new_for_path(root):enumerate_children("standard::name", 0)
        local entries, percentages = {}, {}
        if enumerator then
            while true do
                local entry = enumerator:next_file()
                if not entry then break end
                local name = entry:get_name()
                -- Laptop batteries only: exclude wireless mouse/headset batteries.
                if name:match("^BAT") and read(root .. name .. "/type") == "Battery" then
                    local capacity = tonumber(read(root .. name .. "/capacity"))
                    if capacity then
                        percentages[#percentages + 1] = capacity
                        entries[#entries + 1] = name .. ": " .. capacity .. "% "
                            .. (read(root .. name .. "/status") or "Unknown")
                    end
                end
            end
            enumerator:close()
        end
        battery_box.visible = #percentages > 0
        if #percentages > 0 then
            local sum = 0
            for _, value in ipairs(percentages) do sum = sum + value end
            local capacity = math.floor(sum / #percentages + 0.5)
            battery.text = "BAT " .. capacity .. "%"
            battery_tip.text = table.concat(entries, "\n")
        end
    end
    s.stats_timer = gears.timer {timeout = 5, autostart = true, call_now = true, callback = update_stats}
    s:connect_signal("removed", function() s.stats_timer:stop() end)

    local tray = wibox.widget.systray()
    tray:set_base_size(20)
    tray:set_screen("primary")
    local volume_text = wibox.widget.textbox("--")
    local muted = false
    local speaker = wibox.widget.base.make_widget()
    speaker.fit = function() return 18, 20 end
    speaker.draw = function(_, _, cr, _, height)
        cr:save()
        cr:translate(0, math.floor((height - 16) / 2))
        cr:set_source_rgb(0, 0, 0)
        cr:rectangle(2, 6, 4, 5)
        cr:move_to(6, 6); cr:line_to(10, 2); cr:line_to(10, 15); cr:line_to(6, 11)
        cr:close_path(); cr:fill()
        cr:set_line_width(1.5)
        if muted then
            cr:move_to(12, 5); cr:line_to(17, 12)
            cr:move_to(17, 5); cr:line_to(12, 12); cr:stroke()
        else
            cr:arc(9, 8.5, 5, -0.9, 0.9)
            cr:stroke()
            cr:arc(9, 8.5, 8, -0.9, 0.9); cr:stroke()
        end
        cr:restore()
    end
    local volume = wibox.widget {speaker, volume_text, spacing = 2, layout = wibox.layout.fixed.horizontal}
    local volume_tip = awful.tooltip {objects = {volume}, text = "Volume"}
    local volume_pending = false
    local function update_volume()
        if volume_pending then return end
        volume_pending = true
        awful.spawn.easy_async({"wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"}, function(stdout, _, _, code)
            volume_pending = false
            local value = code == 0 and tonumber(stdout:match("Volume:%s*([%d.]+)")) or nil
            muted = stdout:find("MUTED", 1, true) ~= nil
            volume_text.text = value and (muted and "Mute" or string.format("%.0f%%", value * 100)) or "--"
            volume_tip.text = value and ("Volume: " .. volume_text.text .. "\nClick: mixer; right-click: mute; wheel: volume")
                or "No default audio output\nClick to open Volume Control"
            speaker:emit_signal("widget::redraw_needed")
        end)
    end
    local function change_volume(action)
        awful.spawn.easy_async({os.getenv("HOME") .. "/.local/bin/openbox-volume", action}, update_volume)
    end
    volume:buttons(gears.table.join(
        awful.button({}, 1, function() awful.spawn("pavucontrol") end),
        awful.button({}, 2, function() change_volume("mute") end),
        awful.button({}, 3, function() change_volume("mute") end),
        awful.button({}, 4, function() change_volume("up") end),
        awful.button({}, 5, function() change_volume("down") end)
    ))
    s.volume_timer = gears.timer {timeout = 3, autostart = true, call_now = true, callback = update_volume}
    s:connect_signal("removed", function() s.volume_timer:stop() end)
    local clock = wibox.widget.textclock("%a  %d.%m.%y  %H:%M:%S", 1)
    clock.font = "Microsoft Sans Serif bold 9"
    clock.forced_width = 170
    clock.align = "center"
    awful.tooltip {objects = {clock}, timer_function = function() return os.date("%A, %d %B %Y") end}
    local calendar = awful.widget.calendar_popup.month {
        font = beautiful.font, start_sunday = false, week_numbers = false,
        bg = "#c0c0c0", fg = "#000000", border_width = 2, border_color = "#000000",
        style_month = {bg_color = "#c0c0c0", fg_color = "#000000", padding = 5},
        style_focus = {bg_color = "#001a00", fg_color = "#00ff41"},
    }
    calendar:attach(clock, "tr", {on_hover = false})
    s.panel = awful.wibar {
        position = "top", screen = s, height = 30, bg = "#c0c0c0", fg = "#000000",
        border_width = 0, ontop = true, restrict_workarea = true,
    }
    s.panel:setup {
        {
            {start, separator(), s.taglist, separator(), spacing = 4,
                layout = wibox.layout.fixed.horizontal},
            s.tasklist,
            {bevel(cpu, true), battery_box, volume, tray, bevel(clock, true),
                spacing = 4, layout = wibox.layout.fixed.horizontal},
            layout = wibox.layout.align.horizontal,
        },
        margins = 2, widget = wibox.container.margin,
    }
    -- Useful handles for runtime checks; there is no external panel process.
    s.panel_clock, s.panel_battery, s.panel_cpu = clock, battery, cpu
    s.panel_calendar = calendar
    s.panel_volume, s.panel_volume_text = volume, volume_text
end
return panel
