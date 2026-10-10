-- Floating Win98 + Matrix desktop with a native Awesome panel and tray.
local gears = require("gears")
local awful = require("awful")
require("awful.autofocus")
local wibox = require("wibox")
local beautiful = require("beautiful")
local menubar = require("menubar")
menubar.utils.terminal = "kitty"
local config_dir = awesome.conffile:match("^(.*)/") or "."
local panel = dofile(config_dir .. "/panel.lua")
local sidebar = dofile(config_dir .. "/sidebar.lua")
local home = assert(os.getenv("HOME"))
local mod = "Mod4"
local test_mode = os.getenv("AWESOME_TEST_MODE") == "1"

local titlebar_focus_gradient = gears.color {
    type = "linear", from = {0, 0}, to = {0, 26},
    stops = {{0, "#79dce8"}, {0.18, "#3a9dab"}, {0.52, "#176c69"}, {1, "#0a342d"}},
}
local titlebar_normal_gradient = gears.color {
    type = "linear", from = {0, 0}, to = {0, 26},
    stops = {{0, "#6c9296"}, {0.2, "#476f70"}, {0.55, "#2b4d49"}, {1, "#192e2b"}},
}
local titlebar_button_gradient = gears.color {
    type = "linear", from = {0, 0}, to = {0, 20},
    stops = {{0, "#d9fff7"}, {0.18, "#8cddd8"}, {0.55, "#398f8c"}, {1, "#1a514b"}},
}
local titlebar_button_hover = gears.color {
    type = "linear", from = {0, 0}, to = {0, 20},
    stops = {{0, "#ffffff"}, {0.2, "#c3fff2"}, {0.6, "#5fc4b3"}, {1, "#28715d"}},
}
local titlebar_close_gradient = gears.color {
    type = "linear", from = {0, 0}, to = {0, 20},
    stops = {{0, "#fff2e9"}, {0.2, "#f5b19a"}, {0.58, "#d65c4a"}, {1, "#7f2928"}},
}
local titlebar_close_hover = gears.color {
    type = "linear", from = {0, 0}, to = {0, 20},
    stops = {{0, "#fffaf1"}, {0.2, "#ffd1ae"}, {0.58, "#f17d63"}, {1, "#a8342e"}},
}

-- Do not load naughty: dunst, not Awesome, owns the notification D-Bus name.
awesome.connect_signal("debug::error", function(err)
    io.stderr:write("awesome config: " .. tostring(err) .. "\n")
    if not test_mode then
        awful.spawn({"notify-send", "Awesome configuration error", tostring(err)})
    end
end)

beautiful.init({
    font = "Microsoft Sans Serif 8",
    bg_normal = "#c0c0c0", fg_normal = "#000000",
    bg_focus = "#001a00", fg_focus = "#00ff41",
    bg_urgent = "#001a00", fg_urgent = "#00ff41",
    border_width = 2, border_normal = "#808080", border_focus = "#70c5bd",
    titlebar_bg_normal = titlebar_normal_gradient, titlebar_fg_normal = "#d6e7e3",
    titlebar_bg_focus = titlebar_focus_gradient, titlebar_fg_focus = "#f2fffb",
    menu_height = 24, menu_width = 230,
    menu_border_width = 2, menu_border_color = "#808080",
    useless_gap = 0, bg_systray = "#c0c0c0", systray_icon_spacing = 2,
    maximized_hide_border = true, fullscreen_hide_border = true,
})
awful.layout.layouts = { awful.layout.suit.floating }

local function run(command) awful.spawn(command) end
local function helper(name, argument)
    local command = { home .. "/.local/bin/openbox-" .. name }
    if argument then command[#command + 1] = argument end
    run(command)
end
local function activate(c)
    c.minimized = false
    c:emit_signal("request::activate", "user", {raise = true})
end
local function maximize(c)
    c.maximized = not c.maximized
    c:raise()
end
local function adjacent_tag(delta, move, follow, wrap)
    local s = client.focus and client.focus.screen or awful.screen.focused()
    local current = s.selected_tag
    if not current then return end
    local index = current.index + delta
    if wrap then index = ((index - 1) % #s.tags) + 1 end
    local t = s.tags[index]
    if not t then return end
    if move and client.focus then client.focus:move_to_tag(t) end
    if not move or follow then t:view_only() end
end
local shown_desktop = false
local desktop_clients = {}
local function toggle_desktop()
    shown_desktop = not shown_desktop
    if shown_desktop then
        desktop_clients = {}
        for _, c in ipairs(client.get()) do
            if c:isvisible() and not c.minimized and c.type ~= "dock" and c.type ~= "desktop" then
                desktop_clients[#desktop_clients + 1] = c
                c.minimized = true
            end
        end
    else
        for _, c in ipairs(desktop_clients) do
            if c.valid then c.minimized = false end
        end
        desktop_clients = {}
    end
end
local function cycle(delta)
    awful.client.focus.byidx(delta)
    if client.focus then client.focus:raise() end
end
local function lower(c)
    c:lower()
    awful.client.focus.byidx(1)
    if client.focus == c then client.focus = nil end
end
local function snap(c, right)
    c.fullscreen = false
    c.maximized = false
    c.maximized_horizontal = false
    c.maximized_vertical = false
    local area = c.screen.workarea
    local width = math.floor(area.width / 2)
    c:geometry({x = area.x + (right and width or 0), y = area.y,
        width = (right and area.width - width or width) - 2 * c.border_width,
        height = area.height - 2 * c.border_width})
    -- Include titlebars and size hints when fitting the window to the workarea.
    awful.placement.no_offscreen(c, {honor_workarea = true})
end
local function window_menu(c)
    awful.menu({items = {
        {"Minimize", function() c.minimized = true end},
        {"Maximize / Restore", function() maximize(c) end},
        {"Fullscreen", function() c.fullscreen = not c.fullscreen; c:raise() end},
        {"Always on top", function() c.ontop = not c.ontop end},
        {"All desktops", function() c.sticky = not c.sticky end},
        {"Close", function() c:kill() end},
    }}):show()
end
local function confirm_quit()
    local confirmation = awful.menu({items = {
        {"Quit Awesome?", function() awesome.quit() end},
        {"Cancel", function() end},
    }})
    _G.__awesome_quit_confirmation = confirmation
    confirmation:show()
end
local display_menu = awful.menu({items = {
    {"Internal display only", function() helper("display", "--internal") end},
    {"External HDMI only", function() helper("display", "--hdmi") end},
    {"Extend desktop (laptop + HDMI)", function() helper("display", "--extend") end},
    {"Restore automatic layout", function() helper("display", "--once") end},
}})
_G.__awesome_display_menu = display_menu
_G.__awesome_quit_confirmation = nil
local main_menu = awful.menu({items = {
    {"Applications", function() menubar.show() end},
    {"Run…", "xfce4-appfinder"},
    {"Kitty", "kitty"}, {"PCManFM", "pcmanfm"}, {"Firefox", "firefox"},
    {"Audacious", "audacious"}, {"Gajim", "gajim"}, {"KeePassXC", "keepassxc"},
    {"Volume Control", "pavucontrol"},
    {"Reload Awesome", awesome.restart},
    {"Display outputs", function() display_menu:show() end},
    {"Log Out…", confirm_quit},
}})

local function wallpaper(s)
    local state_home = os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")
    local state_file = io.open(state_home .. "/awesome/wallpaper", "r")
    local selected = state_file and state_file:read("*l") or nil
    if state_file then state_file:close() end
    local path = selected and gears.filesystem.file_readable(selected) and selected
        or home .. "/.local/share/wallpapers/aurora-longhorn.png"
    if not gears.filesystem.file_readable(path) then
        path = home .. "/.local/share/wallpapers/lock-win98-tux.png"
    end
    if gears.filesystem.file_readable(path) then
        gears.wallpaper.maximized(path, s, false)
    else
        gears.wallpaper.set("#008080")
    end
end
awful.screen.connect_for_each_screen(function(s)
    awful.tag({"1", "2", "3", "4"}, s, awful.layout.suit.floating)
    wallpaper(s)
    panel.create(s, main_menu, activate, window_menu)
    sidebar.create(s)
end)
screen.connect_signal("property::geometry", wallpaper)

local function screen_has_fullscreen(s)
    for _, c in ipairs(client.get(s)) do
        if c.valid and c.fullscreen and not c.minimized then return true end
    end
    return false
end

local function update_sidebar_mode(s)
    if not s or not s.valid or not s.sidebar then return end
    local mode = s.sidebar_mode or 0
    local fullscreen = screen_has_fullscreen(s)
    local reserve = mode == 3 and not fullscreen
    s.sidebar.visible = mode > 0 and not (mode == 3 and fullscreen)
    s.sidebar.ontop = mode == 2 or mode == 3
    s.sidebar:struts(reserve and {right = s.sidebar.width}
        or {left = 0, right = 0, top = 0, bottom = 0})
end

local function cycle_sidebar_mode(s)
    if not s or not s.sidebar then return end
    s.sidebar_mode = ((s.sidebar_mode or 0) + 1) % 4
    update_sidebar_mode(s)
end

local globalkeys = {}
local function key(modifiers, name, callback)
    globalkeys = gears.table.join(globalkeys, awful.key(modifiers, name, callback))
end
key({mod}, "Return", function() run("kitty") end)
key({mod, "Shift"}, "Return", function()
    run({"kitty", "--title", "System Monitor", "btop"})
end)
key({mod}, "r", function() run("xfce4-appfinder") end)
key({mod}, "e", function() run("pcmanfm") end)
key({mod}, "l", function() helper("lock") end)
key({mod}, "d", toggle_desktop)
key({mod, "Shift"}, "s", function()
    cycle_sidebar_mode(awful.screen.focused())
end)
key({"Mod1"}, "Tab", function() cycle(1) end)
key({"Mod1", "Shift"}, "Tab", function() cycle(-1) end)
key({"Control", "Mod1"}, "Tab", function() cycle(1) end)
key({mod, "Control"}, "r", awesome.restart)
key({mod, "Shift"}, "q", confirm_quit)
key({mod}, "p", function() display_menu:show() end)
for i = 1, 4 do
    key({mod}, "#" .. (i + 9), function()
        local t = awful.screen.focused().tags[i]
        if t then t:view_only() end
    end)
    key({mod, "Shift"}, "#" .. (i + 9), function()
        local c = client.focus
        if c and c.screen.tags[i] then
            local t = c.screen.tags[i]
            c:move_to_tag(t); t:view_only(); activate(c)
        end
    end)
end
for _, entry in ipairs({{"Left", -1}, {"Up", -1}, {"Right", 1}, {"Down", 1}}) do
    local direction, delta = entry[1], entry[2]
    key({"Control", "Mod1"}, direction, function() adjacent_tag(delta, false, false, false) end)
    key({mod, "Shift"}, direction, function()
        awful.client.focus.bydirection(direction:lower())
        if client.focus then client.focus:raise() end
    end)
end
local commands = {
    {{}, "XF86AudioRaiseVolume", {home .. "/.local/bin/openbox-volume", "up"}},
    {{}, "XF86AudioLowerVolume", {home .. "/.local/bin/openbox-volume", "down"}},
    {{}, "XF86AudioMute", {home .. "/.local/bin/openbox-volume", "mute"}},
    {{}, "XF86AudioMicMute", {"wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"}},
    {{}, "XF86MonBrightnessUp", {home .. "/.local/bin/openbox-brightness", "up"}},
    {{}, "XF86MonBrightnessDown", {home .. "/.local/bin/openbox-brightness", "down"}},
    {{}, "XF86AudioNext", {"playerctl", "next"}},
    {{}, "XF86AudioPrev", {"playerctl", "previous"}},
    {{}, "XF86AudioPlay", {"playerctl", "play-pause"}},
    {{}, "XF86AudioPause", {"playerctl", "play-pause"}},
    {{}, "Print", {home .. "/.local/bin/openbox-screenshot", "full"}},
    {{"Mod1"}, "Print", {home .. "/.local/bin/openbox-screenshot", "window"}},
    {{"Shift"}, "Print", {home .. "/.local/bin/openbox-screenshot", "region"}},
}
for _, entry in ipairs(commands) do
    local command = entry[3]
    key(entry[1], entry[2], function() run(command) end)
end
root.keys(globalkeys)
root.buttons(gears.table.join(
    awful.button({}, 3, function() main_menu:toggle() end),
    awful.button({}, 2, function() awful.menu.client_list({theme = {width = 250}}) end),
    awful.button({}, 4, function() adjacent_tag(-1, false, false, true) end),
    awful.button({}, 5, function() adjacent_tag(1, false, false, true) end)
))
local clientkeys = gears.table.join(
    awful.key({"Mod1"}, "F4", function(c) c:kill() end),
    awful.key({"Mod1"}, "F11", function(c) c.fullscreen = not c.fullscreen; c:raise() end),
    awful.key({"Mod1"}, "Escape", lower),
    awful.key({"Mod1"}, "space", window_menu),
    awful.key({mod}, "Left", function(c) snap(c, false) end),
    awful.key({mod}, "Right", function(c) snap(c, true) end)
)
local clientbuttons = gears.table.join(
    awful.button({}, 1, activate),
    awful.button({mod}, 1, function(c) activate(c); awful.mouse.client.move(c) end),
    awful.button({mod}, 3, function(c) activate(c); awful.mouse.client.resize(c) end),
    awful.button({mod}, 2, lower),
    awful.button({mod}, 4, function() adjacent_tag(-1, false, false, true) end),
    awful.button({mod}, 5, function() adjacent_tag(1, false, false, true) end),
    awful.button({"Control", "Mod1"}, 4, function() adjacent_tag(-1, false, false, true) end),
    awful.button({"Control", "Mod1"}, 5, function() adjacent_tag(1, false, false, true) end),
    awful.button({mod, "Shift"}, 4, function() adjacent_tag(-1, true, false, true) end),
    awful.button({mod, "Shift"}, 5, function() adjacent_tag(1, true, false, true) end)
)
awful.rules.rules = {
    {rule = {}, properties = {
        floating = true, border_width = beautiful.border_width,
        border_color = beautiful.border_normal, focus = awful.client.focus.filter,
        raise = true, keys = clientkeys, buttons = clientbuttons,
        screen = function() return screen.primary end,
        placement = awful.placement.no_overlap + awful.placement.no_offscreen,
    }},
    {rule_any = {type = {"normal", "dialog"}}, properties = {titlebars_enabled = true}},
    {rule_any = {type = {"dock", "desktop"}}, properties = {
        titlebars_enabled = false, border_width = 0, focusable = false,
        skip_taskbar = true, sticky = true, placement = function() end,
    }},
    {rule = {type = "dock"}, properties = {ontop = true, dockable = true, floating = false}},
}

local function update_decorations(c)
    if c.type ~= "normal" and c.type ~= "dialog" then return end
    if c._private and c._private.titlebars and c._private.titlebars.bottom then
        local _, height = c:titlebar_bottom()
        if c.maximized or c.fullscreen then
            if height > 0 then
                awful.titlebar.hide(c, "bottom")
                -- Hiding a titlebar shrinks the outer geometry. Refit after
                -- Awesome's maximize request, without replacing restore geometry.
                gears.timer.delayed_call(function()
                    if c.valid and (c.maximized or c.fullscreen) then
                        awful.placement.maximize(c, {honor_workarea = not c.fullscreen,
                            honor_padding = not c.fullscreen, store_geometry = false,
                            ignore_border_width = true})
                    end
                end)
            end
        elseif height == 0 then
            awful.titlebar.show(c, "bottom")
        end
    end
end
client.connect_signal("property::maximized", update_decorations)
client.connect_signal("property::fullscreen", update_decorations)
local function update_panel_for_fullscreen(s)
    if not s or not s.valid or not s.panel then return end
    local fullscreen = false
    for _, c in ipairs(client.get(s)) do
        if c.valid and c.fullscreen and not c.minimized then
            fullscreen = true
            break
        end
    end
    s.panel.visible = not fullscreen
    if s.sidebar_mode == 3 then update_sidebar_mode(s) end
end
client.connect_signal("property::fullscreen", function(c)
    update_panel_for_fullscreen(c.screen)
end)
client.connect_signal("property::minimized", function(c)
    if c.fullscreen then update_panel_for_fullscreen(c.screen) end
end)
client.connect_signal("property::screen", function(c, old_screen)
    update_panel_for_fullscreen(old_screen)
    update_panel_for_fullscreen(c.screen)
end)
client.connect_signal("unmanage", function(c)
    local s = c.screen
    if s then
        -- A fullscreen client may disappear without a final fullscreen=false
        -- event (for example, closing mpv), so recompute after removal.
        gears.timer.delayed_call(function() update_panel_for_fullscreen(s) end)
    end
end)

-- Square glass controls keep Win98 geometry with a restrained Aero sheen.
local function control(label, callback, is_close, widget_id)
    local text = wibox.widget.textbox(label)
    text.align = "center"
    text.valign = "center"
    text.font = "Segoe UI bold 10"
    local button = wibox.widget {
        {text, left = 2, right = 2, top = 1, bottom = 1, widget = wibox.container.margin},
        bg = is_close and titlebar_close_gradient or titlebar_button_gradient,
        fg = "#f4fffb", border_width = 1,
        border_color = is_close and "#ffd0bd" or "#b9f5e9",
        forced_width = 21, forced_height = 19, id = widget_id,
        widget = wibox.container.background,
    }
    local function set_hover(hovered)
        button.bg = is_close
            and (hovered and titlebar_close_hover or titlebar_close_gradient)
            or (hovered and titlebar_button_hover or titlebar_button_gradient)
        button.border_color = hovered and "#ffffff" or (is_close and "#ffd0bd" or "#b9f5e9")
    end
    button:connect_signal("mouse::enter", function() set_hover(true) end)
    button:connect_signal("mouse::leave", function() set_hover(false) end)
    button:connect_signal("button::press", function(_, _, _, pressed_button)
        if pressed_button == 1 then callback() end
    end)
    return button
end
client.connect_signal("request::titlebars", function(c)
    local click_timer = gears.timer({timeout = 0.5, single_shot = true, callback = function() end})
    local drag = gears.table.join(
        awful.button({}, 1, function()
            activate(c)
            if click_timer.started then click_timer:stop(); maximize(c)
            else click_timer:start(); awful.mouse.client.move(c) end
        end),
        awful.button({}, 2, function() lower(c) end),
        awful.button({}, 3, function() window_menu(c) end)
    )
    local title = awful.titlebar.widget.titlewidget(c)
    title:set_font("Segoe UI bold 9")
    title:set_align("left")
    local icon = awful.titlebar.widget.iconwidget(c)
    icon:buttons(gears.table.join(awful.button({}, 1, function() window_menu(c) end)))
    local minimize_button = control("−", function()
        gears.timer.delayed_call(function()
            if c.valid then c.minimized = true end
        end)
    end, false, "titlebar_minimize")
    local maximize_button = control("□", function() maximize(c) end, false, "titlebar_maximize")
    local close_button = control("×", function() c:kill() end, true, "titlebar_close")
    awful.titlebar(c, {size = 26}):setup {
        {
            {icon, forced_width = 18, widget = wibox.container.constraint},
            margins = 2, widget = wibox.container.margin,
        },
        {title, buttons = drag, left = 3, widget = wibox.container.margin},
        {
            {
                minimize_button, maximize_button, close_button,
                spacing = 2, layout = wibox.layout.fixed.horizontal,
            },
            margins = 2, widget = wibox.container.margin,
        },
        layout = wibox.layout.align.horizontal,
    }
    -- A conventional bottom-right grip: plain left-drag, no modifier required.
    local grip = wibox.widget.base.make_widget()
    grip.fit = function() return 16, 10 end
    grip.draw = function(_, _, cr, width, height)
        for offset = 2, 10, 4 do
            cr:set_source_rgb(0.5, 0.5, 0.5)
            cr:move_to(width - offset, height - 1)
            cr:line_to(width - 1, height - offset); cr:stroke()
            cr:set_source_rgb(1, 1, 1)
            cr:move_to(width - offset + 1, height - 1)
            cr:line_to(width - 1, height - offset + 1); cr:stroke()
        end
    end
    grip:buttons(gears.table.join(awful.button({}, 1, function()
        if not c.maximized and not c.fullscreen then
            activate(c)
            awful.mouse.client.resize(c, "bottom_right")
        end
    end)))
    awful.titlebar(c, {position = "bottom", size = 10,
        bg_normal = "#c0c0c0", bg_focus = "#c0c0c0"}):setup {
        nil, nil,
        {grip, width = 16, strategy = "exact", widget = wibox.container.constraint},
        layout = wibox.layout.align.horizontal,
    }
    update_decorations(c)
end)
client.connect_signal("manage", function(c)
    if c.type == "dock" then
        return
    end
    if c.type == "desktop" then return end
    if not c.size_hints.user_position and not c.size_hints.program_position then
        if c.type == "normal" or c.type == "dialog" then
            awful.placement.centered(c, {honor_workarea = true})
        end
    end
    awful.placement.no_offscreen(c, {honor_workarea = true})
end)
client.connect_signal("focus", function(c) c.border_color = beautiful.border_focus end)
client.connect_signal("unfocus", function(c) c.border_color = beautiful.border_normal end)
-- Intentionally no mouse::enter focus handler: click-to-focus like Openbox.
if not test_mode then
    awful.spawn({"sh", home .. "/.config/awesome/autostart"})
end
