-- Native Awesome panel: Win98 geometry with Frutiger Aero glass styling.
local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local appearance = dofile((awesome.conffile:match("^(.*)/") or ".") .. "/appearance.lua")
local palette = appearance.palette
local panel = {}

local task_order = setmetatable({}, {__mode = "k"})
local next_task_order = 0

local function ordered_task_source()
    local clients = client.get()
    for _, c in ipairs(clients) do
        if not task_order[c] then
            next_task_order = next_task_order + 1
            task_order[c] = next_task_order
        end
    end
    table.sort(clients, function(a, b)
        return (task_order[a] or 0) < (task_order[b] or 0)
    end)
    return clients
end

local function reorder_task_clients(s, dragged, drop_index, visible_clients)
    if not dragged or not drop_index or not visible_clients then return false end
    local reordered, from_index = {}, nil
    for index, c in ipairs(visible_clients) do
        if c == dragged then from_index = index else reordered[#reordered + 1] = c end
    end
    if not from_index then return false end
    drop_index = math.max(1, math.min(#reordered + 1, drop_index))
    table.insert(reordered, drop_index, dragged)
    if reordered[from_index] == visible_clients[from_index] then return false end

    local rank, seen = 0, {}
    for _, c in ipairs(reordered) do
        rank = rank + 1
        task_order[c], seen[c] = rank, true
    end
    local remainder = {}
    for _, c in ipairs(client.get()) do
        if c.screen == s and not seen[c] then remainder[#remainder + 1] = c end
    end
    table.sort(remainder, function(a, b)
        return (task_order[a] or 0) < (task_order[b] or 0)
    end)
    for _, c in ipairs(remainder) do
        rank = rank + 1
        task_order[c] = rank
    end
    next_task_order = math.max(next_task_order, rank)
    if s.tasklist and s.tasklist._do_tasklist_update then s.tasklist._do_tasklist_update() end
    return true
end
local panel_gradient = appearance.gradient("blue", 30)
local panel_item_gradient = appearance.gradient("inactive", 24)
local panel_focus_gradient = appearance.gradient("selected", 24)
local function selection_border(self, selected)
    local bg = self:get_children_by_id("background_role")[1]
    if bg then bg.border_color = selected and palette.active_border or palette.inactive_border end
end
local function glass_clock(widget)
    return wibox.widget {
        {widget, left = 5, right = 5, top = 1, bottom = 1, widget = wibox.container.margin},
        bg = panel_item_gradient, fg = palette.title,
        border_width = 1, border_color = "#6aabea",
        widget = wibox.container.background,
    }
end
local function separator()
    return wibox.widget {
        forced_width = 3, color = "#4c83bf",
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
        menu:toggle({coords = {x = s.geometry.x, y = s.geometry.y + 30}})
    end
    start:buttons(gears.table.join(awful.button({}, 1, toggle_start_menu)))
    s.start_button, s.start_menu = start, menu

    s.taglist = awful.widget.taglist {
        screen = s, filter = awful.widget.taglist.filter.all,
        style = {bg_focus = panel_focus_gradient, fg_focus = palette.title,
            bg_empty = panel_item_gradient, fg_empty = palette.inactive,
            bg_occupied = panel_item_gradient, fg_occupied = palette.inactive},
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
            create_callback = function(self, t) selection_border(self, t.selected) end,
            update_callback = function(self, t) selection_border(self, t.selected) end,
            {
                {
                    {id = "text_role", align = "center", widget = wibox.widget.textbox},
                    left = 6, right = 6, top = 1, bottom = 1,
                    widget = wibox.container.margin,
                },
                id = "background_role", border_width = 1, border_color = "#8ecbff",
                widget = wibox.container.background,
            },
            bg = panel_gradient, border_width = 1, border_color = "#173a6c",
            widget = wibox.container.background,
        },
    }
    s.tasklist = awful.widget.tasklist {
        screen = s, filter = awful.widget.tasklist.filter.currenttags,
        source = ordered_task_source,
        style = {bg_normal = panel_item_gradient, fg_normal = palette.inactive,
            bg_focus = panel_focus_gradient, fg_focus = palette.title,
            bg_minimize = panel_item_gradient, fg_minimize = palette.minimized},
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
                    id = "background_role", border_width = 1, border_color = "#8ecbff",
                    widget = wibox.container.background,
                },
                bg = panel_gradient, border_width = 1, border_color = "#173a6c",
                widget = wibox.container.background,
            },
            width = 160, strategy = "exact", widget = wibox.container.constraint,
            create_callback = function(self, c, index, clients)
                selection_border(self, c == client.focus)
                self._tasklist_index, self._tasklist_clients = index, clients
                self:connect_signal("button::press", function(_, lx, _, button)
                    if button ~= 1 then return end
                    local origin = mouse.coords()
                    local left = origin.x - (lx or 0)
                    local item_width = self.width or self.forced_width or 160
                    local spacing = 2
                    mousegrabber.run(function(pointer)
                        if pointer.buttons[1] then return true end
                        local dx, dy = pointer.x - origin.x, pointer.y - origin.y
                        if dx * dx + dy * dy >= 49 then
                            local drop_index = math.floor((pointer.x - left) / (item_width + spacing)) + 1
                            reorder_task_clients(s, c, drop_index, self._tasklist_clients)
                        end
                        return false
                    end, "fleur")
                end)
            end,
            update_callback = function(self, c, index, clients)
                selection_border(self, c == client.focus)
                self._tasklist_index, self._tasklist_clients = index, clients
            end,
        },
    }


    local tray = wibox.widget.systray()
    tray:set_base_size(20)
    tray:set_screen("primary")
    local clock = wibox.widget.textclock("%H:%M", 1)
    local clock_container = glass_clock(clock)
    clock.font = appearance.fonts.title
    clock.fg = palette.title
    clock.forced_width = 58
    clock.align = "center"
    local calendar = awful.widget.calendar_popup.month {
        font = appearance.fonts.menu, start_sunday = false, week_numbers = false,
        bg = appearance.gradient("menu", 340), fg = palette.text,
        border_width = 1, border_color = palette.menu_border,
        style_month = {bg_color = appearance.gradient("menu", 340), fg_color = palette.text, padding = 5,
            border_width = 1, border_color = palette.menu_border},
        style_header = {bg_color = palette.menu_base, fg_color = palette.title, border_width = 0},
        style_weekday = {bg_color = palette.menu_base, fg_color = palette.muted, border_width = 0},
        style_normal = {bg_color = palette.menu_base, fg_color = palette.text, border_width = 0},
        style_weeknumber = {bg_color = palette.menu_base, fg_color = palette.muted, border_width = 0},
        -- Keep the gradient on the container, not in a Pango background attribute.
        style_focus = {bg_color = appearance.gradient("selected", 24), fg_color = palette.title,
            markup = "<b>%s</b>", border_width = 1, border_color = palette.active_border},
    }
    calendar:attach(clock, "tr", {on_hover = false})
    clock:connect_signal("button::press", dismiss_menu)
    tray:connect_signal("button::press", dismiss_menu)
    s.panel = awful.wibar {
        position = "top", screen = s, height = 30, bg = panel_gradient, fg = palette.title,
        border_width = 0, ontop = true, restrict_workarea = true,
        type = "dock",
    }
    s.panel:setup {
        {
            {forced_height = 1, bg = "#eaffffff", widget = wibox.container.background},
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
                {forced_height = 1, bg = "#73c6e199", widget = wibox.container.background},
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
