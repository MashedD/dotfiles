-- Native Awesome widgets, styled like the previous 30px VAX/Win98 panel.
local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local panel = {}
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


    local tray = wibox.widget.systray()
    tray:set_base_size(20)
    tray:set_screen("primary")
    local clock = wibox.widget.textclock("%H:%M", 1)
    clock.font = "Microsoft Sans Serif bold 9"
    clock.forced_width = 58
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
            {
                {
                    {start, separator(), s.taglist, separator(), spacing = 4,
                        layout = wibox.layout.fixed.horizontal},
                    s.tasklist,
                    {tray, bevel(clock, true), spacing = 4, layout = wibox.layout.fixed.horizontal},
                    layout = wibox.layout.align.horizontal,
                },
                left = 2, right = 2, top = 2, bottom = 2,
                widget = wibox.container.margin,
            },
            {forced_height = 1, bg = "#70c5bd", widget = wibox.container.background},
            layout = wibox.layout.fixed.vertical,
        },
        widget = wibox.container.margin,
    }
    -- Useful handles for runtime checks; there is no external panel process.
    s.panel_clock, s.panel_calendar = clock, calendar
end
return panel
