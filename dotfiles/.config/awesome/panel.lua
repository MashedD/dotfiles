-- Native Awesome panel: Win98 geometry with Frutiger Aero glass styling.
local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local panel = {}
local panel_gradient = gears.color {
    type = "linear", from = {0, 0}, to = {0, 30},
    stops = {{0, "#a5ecf4"}, {0.16, "#55b1d6"}, {0.48, "#2b88b8"}, {0.76, "#1d638f"}, {1, "#123f5e"}},
}
local panel_item_gradient = gears.color {
    type = "linear", from = {0, 0}, to = {0, 24},
    stops = {{0, "#6799bf"}, {0.2, "#477ea6"}, {0.6, "#2e608b"}, {1, "#1c4268"}},
}
local panel_focus_gradient = gears.color {
    type = "linear", from = {0, 0}, to = {0, 24},
    stops = {{0, "#b4f1f7"}, {0.16, "#55b1d6"}, {0.48, "#2b88b8"}, {0.76, "#1d638f"}, {1, "#123f5e"}},
}
local function glass_clock(widget)
    return wibox.widget {
        {widget, left = 5, right = 5, top = 1, bottom = 1, widget = wibox.container.margin},
        bg = panel_item_gradient, fg = "#f2fffb",
        border_width = 1, border_color = "#9dece3",
        widget = wibox.container.background,
    }
end
local function separator()
    return wibox.widget {
        forced_width = 3, color = "#5299b4",
        orientation = "vertical", widget = wibox.widget.separator,
    }
end

function panel.create(s, menu, activate, window_menu)
    local function dismiss_menu()
        if menu and menu.wibox and menu.wibox.visible then menu:hide() end
    end
    local icon = wibox.widget.imagebox()
    local icon_path = (os.getenv("XDG_DATA_HOME") or os.getenv("HOME") .. "/.local/share")
        .. "/icons/hicolor/32x32/apps/vax-tux-start.png"
    if gears.filesystem.file_readable(icon_path) then icon.image = icon_path end
    -- The generated image is the complete 65x25 Start button, text included.
    -- Render at native size, without a second label or shrinking it to 22px.
    icon.forced_width, icon.forced_height, icon.resize = 65, 25, false
    local start = icon
    local function toggle_start_menu()
        menu:toggle({coords = {x = s.geometry.x + 2, y = s.geometry.y + 30}})
    end
    start:buttons(gears.table.join(awful.button({}, 1, toggle_start_menu)))
    s.start_button, s.start_menu = start, menu

    s.taglist = awful.widget.taglist {
        screen = s, filter = awful.widget.taglist.filter.all,
        style = {bg_focus = panel_focus_gradient, fg_focus = "#f2fffb",
            bg_empty = panel_item_gradient, fg_empty = "#d6e7e3",
            bg_occupied = panel_item_gradient, fg_occupied = "#d6e7e3"},
        buttons = gears.table.join(
            awful.button({}, 1, function(t) dismiss_menu(); t:view_only() end),
            awful.button({"Mod4"}, 1, function(t)
                dismiss_menu()
                if client.focus then client.focus:move_to_tag(t) end
            end),
            -- Up returns to the previous desktop; down advances to the next.
            awful.button({}, 4, function(t) awful.tag.viewprev(t.screen) end),
            awful.button({}, 5, function(t) awful.tag.viewnext(t.screen) end)
        ),
        layout = {spacing = 2, layout = wibox.layout.fixed.horizontal},
        widget_template = {
            {
                {
                    {id = "text_role", align = "center", widget = wibox.widget.textbox},
                    left = 6, right = 6, top = 1, bottom = 1,
                    widget = wibox.container.margin,
                },
                id = "background_role", border_width = 1, border_color = "#a7f3eb",
                widget = wibox.container.background,
            },
            bg = panel_gradient, border_width = 1, border_color = "#174441",
            widget = wibox.container.background,
        },
    }
    s.tasklist = awful.widget.tasklist {
        screen = s, filter = awful.widget.tasklist.filter.currenttags,
        style = {bg_normal = panel_item_gradient, fg_normal = "#d6e7e3",
            bg_focus = panel_focus_gradient, fg_focus = "#f2fffb",
            bg_minimize = panel_item_gradient, fg_minimize = "#9ab6b0"},
        buttons = gears.table.join(
            awful.button({}, 1, function(c)
                dismiss_menu()
                if c == client.focus then c.minimized = true else activate(c) end
            end),
            awful.button({}, 3, function(c) dismiss_menu(); window_menu(c) end),
            awful.button({}, 4, function() awful.client.focus.byidx(1) end),
            awful.button({}, 5, function() awful.client.focus.byidx(-1) end)
        ),
        layout = {spacing = 2, layout = wibox.layout.fixed.horizontal},
        widget_template = {
            {
                {
                    {
                        {
                            {id = "icon_role", forced_width = 16, forced_height = 16, widget = wibox.widget.imagebox},
                            {id = "text_role", ellipsize = "end", widget = wibox.widget.textbox},
                            spacing = 4, layout = wibox.layout.fixed.horizontal,
                        },
                        left = 3, right = 4, top = 1, bottom = 1,
                        widget = wibox.container.margin,
                    },
                    id = "background_role", border_width = 1, border_color = "#a7f3eb",
                    widget = wibox.container.background,
                },
                bg = panel_gradient, border_width = 1, border_color = "#174441",
                widget = wibox.container.background,
            },
            width = 160, strategy = "exact", widget = wibox.container.constraint,
        },
    }


    local tray = wibox.widget.systray()
    tray:set_base_size(20)
    tray:set_screen("primary")
    local clock = wibox.widget.textclock("%H:%M", 1)
    local clock_container = glass_clock(clock)
    clock.font = "Segoe UI bold 9"
    clock.fg = "#f2fffb"
    clock.forced_width = 58
    clock.align = "center"
    local calendar = awful.widget.calendar_popup.month {
        font = beautiful.font, start_sunday = false, week_numbers = false,
        bg = "#173b50", fg = "#e4f3ed", border_width = 1, border_color = "#70c5bd",
        style_month = {bg_color = "#204e68", fg_color = "#f2fffb", padding = 5},
        style_focus = {bg_color = "#287ca5", fg_color = "#ffffff"},
    }
    calendar:attach(clock, "tr", {on_hover = false})
    clock:connect_signal("button::press", dismiss_menu)
    tray:connect_signal("button::press", dismiss_menu)
    s.panel = awful.wibar {
        position = "top", screen = s, height = 30, bg = panel_gradient, fg = "#f2fffb",
        border_width = 0, ontop = true, restrict_workarea = true,
    }
    s.panel:setup {
        {
            {forced_height = 1, bg = "#c2fff5", widget = wibox.container.background},
            {
                {
                    {
                        {start, separator(), s.taglist, separator(), spacing = 4,
                            layout = wibox.layout.fixed.horizontal},
                        s.tasklist,
                        {tray, clock_container, spacing = 4, layout = wibox.layout.fixed.horizontal},
                        layout = wibox.layout.align.horizontal,
                    },
                    left = 2, right = 2, top = 1, bottom = 1,
                    widget = wibox.container.margin,
                },
                {forced_height = 1, bg = "#73c6e1", widget = wibox.container.background},
                layout = wibox.layout.fixed.vertical,
            },
            layout = wibox.layout.fixed.vertical,
        },
        widget = wibox.container.margin,
    }
    -- Useful handles for runtime checks; there is no external panel process.
    s.panel_clock, s.panel_clock_container, s.panel_calendar = clock, clock_container, calendar
end
return panel
