-- Floating Win98 + Matrix desktop with a native Awesome panel and tray.
local gears = require("gears")
local awful = require("awful")
require("awful.autofocus")
local wibox = require("wibox")
local beautiful = require("beautiful")
local menubar = require("menubar")
menubar.utils.terminal = "kitty"
local config_dir = awesome.conffile:match("^(.*)/") or "."
local appearance = dofile(config_dir .. "/appearance.lua")
local interaction = dofile(config_dir .. "/interaction.lua")
local titlebar_layout = dofile(config_dir .. "/titlebar-layout.lua")
local fullscreen_geometry = dofile(config_dir .. "/fullscreen-geometry.lua").install(client, awful, gears)
dofile(config_dir .. "/menu-release.lua").install(require("awful.menu"), interaction, awful, gears)
local panel = dofile(config_dir .. "/panel.lua")
local sidebar = dofile(config_dir .. "/sidebar.lua")
local home = assert(os.getenv("HOME"))
local mod = "Mod4"
local test_mode = os.getenv("AWESOME_TEST_MODE") == "1"

local titlebar_focus_gradient = appearance.gradient("selected", 26)
local titlebar_normal_gradient = appearance.gradient("inactive", 26)
local titlebar_button_gradient = appearance.gradient("control", 20)
local titlebar_button_hover = appearance.gradient("control_hover", 20)
local titlebar_close_gradient = appearance.gradient("close", 20)
local titlebar_close_hover = appearance.gradient("close_hover", 20)
local menu_glass_gradient = appearance.gradient("menu", 340)
local menu_selection_gradient = appearance.gradient("selected", 28)

-- Do not load naughty: dunst, not Awesome, owns the notification D-Bus name.
awesome.connect_signal("debug::error", function(err)
    io.stderr:write("awesome config: " .. tostring(err) .. "\n")
    if not test_mode then
        awful.spawn({"notify-send", "Awesome configuration error", tostring(err)})
    end
end)

beautiful.init({
    font = appearance.fonts.body,
    bg_normal = "#c0c0c0", fg_normal = "#000000",
    bg_focus = "#001a00", fg_focus = "#00ff41",
    bg_urgent = "#001a00", fg_urgent = "#00ff41",
    border_width = 2, border_normal = "#808080", border_focus = "#538ed4",
    titlebar_bg_normal = titlebar_normal_gradient, titlebar_fg_normal = appearance.palette.inactive,
    titlebar_bg_focus = titlebar_focus_gradient, titlebar_fg_focus = appearance.palette.title,
    menu_font = appearance.fonts.menu, menu_height = 28, menu_width = 270,
    menu_bg_normal = menu_glass_gradient, menu_fg_normal = appearance.palette.text,
    menu_bg_focus = menu_selection_gradient, menu_fg_focus = appearance.palette.title,
    menu_border_width = 1, menu_border_color = appearance.palette.menu_border,
    menubar_bg_normal = menu_glass_gradient, menubar_fg_normal = appearance.palette.text,
    menubar_bg_focus = menu_selection_gradient, menubar_fg_focus = appearance.palette.title,
    menubar_border_width = 1, menubar_border_color = appearance.palette.menu_border,
    prompt_font = appearance.fonts.menu, prompt_fg = appearance.palette.text,
    prompt_bg = appearance.palette.menu_base,
    prompt_fg_cursor = appearance.palette.menu_base, prompt_bg_cursor = appearance.palette.green,
    tooltip_bg = appearance.palette.menu_base, tooltip_fg = appearance.palette.text,
    tooltip_font = appearance.fonts.menu, tooltip_border_width = 1,
    tooltip_border_color = appearance.palette.menu_border,
    tooltip_opacity = 1, tooltip_shape = gears.shape.rectangle,
    useless_gap = 0, bg_systray = "#174a77", systray_icon_spacing = 2,
    maximized_hide_border = true, fullscreen_hide_border = true,
})
menubar.prompt_args = {font = appearance.fonts.menu,
    fg_cursor = appearance.palette.menu_base, bg_cursor = appearance.palette.green}
awful.layout.layouts = { awful.layout.suit.floating, awful.layout.suit.tile }

local function run(command) awful.spawn(command) end
local function helper(name, argument)
    local command = { home .. "/.local/bin/desktop-" .. name }
    if argument then command[#command + 1] = argument end
    run(command)
end
local main_menu
local function dismiss_start_menu()
    if main_menu and main_menu.wibox.visible then main_menu:hide() end
end
local function activate(c)
    dismiss_start_menu()
    c.minimized = false
    c:emit_signal("request::activate", "user", {raise = true})
end
local function maximize(c)
    dismiss_start_menu()
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
local floating_restore = setmetatable({}, {__mode = "k"})
local function belongs_to_tag(c, tag)
    for _, current in ipairs(c:tags()) do
        if current == tag then return true end
    end
    return false
end
local function toggle_layout()
    local s = awful.screen.focused()
    local tag = s and s.selected_tag
    if not tag then return end
    local to_tile = tag.layout == awful.layout.suit.floating
    awful.layout.set(to_tile and awful.layout.suit.tile or awful.layout.suit.floating, tag)
    if to_tile then
        for _, c in ipairs(client.get(s)) do
            if c.valid and not c.minimized and not c.fullscreen and belongs_to_tag(c, tag) then
                local states = floating_restore[c] or {}
                states[tag] = {floating = c.floating, geometry = c:geometry(), maximized = c.maximized}
                floating_restore[c] = states
                c.maximized, c.maximized_horizontal, c.maximized_vertical = false, false, false
                c.floating = false
            end
        end
    else
        for _, c in ipairs(client.get(s)) do
            local states = floating_restore[c]
            local state = states and states[tag]
            if c.valid and (belongs_to_tag(c, tag) or state) then
                if state then
                    c.floating = state.floating
                else
                    c.floating = true
                end
                if state then
                    if state.maximized then
                        c.maximized = true
                    elseif state.geometry then
                        c:geometry(state.geometry)
                    end
                    states[tag] = nil
                    if next(states) == nil then floating_restore[c] = nil end
                end
            end
        end
    end
end
local function lower(c)
    dismiss_start_menu()
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
    dismiss_start_menu()
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
    dismiss_start_menu()
    local confirmation = awful.menu({items = {
        {"Quit Awesome?", function() awesome.quit() end},
        {"Cancel", function() end},
    }})
    _G.__awesome_quit_confirmation = confirmation
    confirmation:show()
end
local function confirm_poweroff()
    dismiss_start_menu()
    local confirmation = awful.menu({items = {
        {"Power off the computer?", function() run({"systemctl", "poweroff"}) end},
        {"Cancel", function() end},
    }})
    _G.__awesome_poweroff_confirmation = confirmation
    confirmation:show()
end
local function menu_separator(_, args)
    local rule = wibox.widget {
        orientation = "horizontal", color = appearance.palette.menu_separator, thickness = 1,
        widget = wibox.widget.separator,
    }
    local theme = {
        fg_normal = args.theme.fg_normal, fg_focus = args.theme.fg_normal,
        bg_normal = args.theme.bg_normal, bg_focus = args.theme.bg_normal,
    }
    return {
        widget = wibox.widget {
            rule, left = 10, right = 10, top = 2, bottom = 2,
            widget = wibox.container.margin,
        },
        width = args.theme.width, height = 5, theme = theme,
        is_separator = true,
    }
end
local function next_selectable_menu_item(menu, step)
    local count = #menu.items
    if count == 0 then return nil end
    local index = menu.sel or (step > 0 and 0 or 1)
    for _ = 1, count do
        index = index + step
        if index < 1 then index = count end
        if index > count then index = 1 end
        local item = menu.items[index]
        if item and not item.is_separator then return index end
    end
    return nil
end
local legacy_menu_icons = "/usr/share/icons/AdwaitaLegacy/32x32/legacy/"
local legacy_menu_fallbacks = {
    ["applications-all"] = "applications-utilities.png",
    ["system-run"] = "system-run.png",
    ["utilities-terminal"] = "utilities-terminal.png",
    ["system-file-manager"] = "system-file-manager.png",
    ["web-browser"] = "web-browser.png",
    ["multimedia-player"] = "multimedia-player.png",
    ["im-message"] = "applications-internet.png",
    ["dialog-password"] = "dialog-password.png",
    ["utilities-system-monitor"] = "utilities-system-monitor.png",
    ["audio-volume-high"] = "audio-volume-high.png",
    ["video-display"] = "video-display.png",
    ["applications-games"] = "applications-games.png",
    ["input-gaming"] = "applications-games.png",
    ["view-refresh"] = "view-refresh.png",
    ["system-log-out"] = "system-log-out.png",
    ["system-suspend"] = "/usr/share/icons/hicolor/48x48/actions/xfsm-suspend.png",
    ["system-shutdown"] = "system-shutdown.png",
}
local function menu_icon(name)
    local ok, path = pcall(function()
        local theme = require("lgi").Gtk.IconTheme.get_default()
        local info = theme and theme:lookup_icon(name, 32, 0)
        return info and info:get_filename()
    end)
    if ok and path and gears.filesystem.file_readable(path) then return path end
    local fallback = legacy_menu_fallbacks[name]
    local fallback_path = fallback and (fallback:sub(1, 1) == "/" and fallback or legacy_menu_icons .. fallback)
    if fallback_path and gears.filesystem.file_readable(fallback_path) then return fallback_path end
    local looked_up = menubar.utils.lookup_icon(name)
    return type(looked_up) == "string" and gears.filesystem.file_readable(looked_up) and looked_up or nil
end
local display_menu = awful.menu({items = {
    {"Internal display only", function() helper("display", "--internal") end},
    {"External HDMI only", function() helper("display", "--hdmi") end},
    {"Extend desktop (laptop + HDMI)", function() helper("display", "--extend") end},
    {"Restore automatic layout", function() helper("display", "--once") end},
}})
_G.__awesome_display_menu = display_menu
_G.__awesome_quit_confirmation = nil
main_menu = awful.menu({items = {
    {"Applications", function() menubar.show() end, menu_icon("applications-all")},
    {"Run…", "xfce4-appfinder", menu_icon("system-run")},
    {new = menu_separator},
    {"Kitty", "kitty", menu_icon("utilities-terminal")},
    {"PCManFM", "pcmanfm", menu_icon("system-file-manager")},
    {"Firefox", "firefox", menu_icon("web-browser")},
    {"Audacious", "audacious", menu_icon("multimedia-player")},
    {"Gajim", "gajim", menu_icon("im-message")},
    {"KeePassXC", "keepassxc", menu_icon("dialog-password")},
    {new = menu_separator},
    {"Monitor", function() dismiss_start_menu(); run({"kitty", "--title", "System Monitor", "btop"}) end,
        menu_icon("utilities-system-monitor")},
    {"Volume Control", "pavucontrol", menu_icon("audio-volume-high")},
    {"Display outputs", function() dismiss_start_menu(); display_menu:show() end,
        menu_icon("video-display")},
    {new = menu_separator},
    {"Quake 1", function() dismiss_start_menu(); run({home .. "/Games/quake-rerelease/vkquake.sh"}) end,
        menu_icon("applications-games")},
    {"Quake 2", function() dismiss_start_menu(); run({home .. "/Games/quake2/q2pro.sh"}) end,
        menu_icon("input-gaming")},
    {new = menu_separator},
    {"Reload Awesome", awesome.restart, menu_icon("view-refresh")},
    {"Log Out…", confirm_quit, menu_icon("system-log-out")},
    {"Sleep", function() dismiss_start_menu(); run({"systemctl", "suspend"}) end,
        menu_icon("system-suspend")},
    {"Poweroff", confirm_poweroff, menu_icon("system-shutdown")},
}})
local main_menu_keygrabber = main_menu._keygrabber
local start_key_pending = false
main_menu._keygrabber = function(modifiers, key_name, event)
    if event == "press" and gears.table.hasitem(awful.menu.menu_keys.up, key_name) then
        local sel_new = next_selectable_menu_item(main_menu, -1)
        if sel_new then main_menu:item_enter(sel_new) end
        return
    elseif event == "press" and gears.table.hasitem(awful.menu.menu_keys.down, key_name) then
        local sel_new = next_selectable_menu_item(main_menu, 1)
        if sel_new then main_menu:item_enter(sel_new) end
        return
    end
    if key_name == "Super_L" or key_name == "Super_R" then
        if event == "press" then
            start_key_pending = true
        elseif event == "release" then
            local tap = start_key_pending
            start_key_pending = false
            if tap then main_menu:hide() end
            return
        end
    end
    main_menu_keygrabber(modifiers, key_name, event)
end
local function toggle_start_menu(s)
    s = s or awful.screen.focused()
    local menu = s.start_menu or main_menu
    menu:toggle({coords = {x = s.geometry.x, y = s.geometry.y + (s.panel and s.panel.height or 30)}})
end

local function wallpaper(s)
    local state_home = os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")
    local state_file = io.open(state_home .. "/awesome/wallpaper", "r")
    local selected = state_file and state_file:read("*l") or nil
    if state_file then state_file:close() end
    local path = selected and gears.filesystem.file_readable(selected) and selected
        or home .. "/.local/share/wallpapers/aurora-cabin.png"
    if not gears.filesystem.file_readable(path) then
        path = home .. "/.local/share/wallpapers/lock-win98-tux.png"
    end
    if gears.filesystem.file_readable(path) then
        gears.wallpaper.maximized(path, s, false)
    else
        gears.wallpaper.set("#008080")
    end
end
local update_sidebar_mode
awful.screen.connect_for_each_screen(function(s)
    awful.tag({"1", "2", "3", "4"}, s, awful.layout.suit.floating)
    wallpaper(s)
    panel.create(s, main_menu, activate, window_menu, interaction)
    sidebar.create(s, dismiss_start_menu)
    s.sidebar_mode = 3
    if update_sidebar_mode then update_sidebar_mode(s) end
end)
screen.connect_signal("property::geometry", wallpaper)

local function screen_has_fullscreen(s)
    for _, c in ipairs(client.get(s)) do
        if c.valid and c.fullscreen and not c.minimized and c:isvisible() then return true end
    end
    return false
end

update_sidebar_mode = function(s)
    if not s or not s.valid or not s.sidebar or (s.sidebar_ui and s.sidebar_ui.disposed) then return end
    local mode = s.sidebar_mode or 0
    local fullscreen = screen_has_fullscreen(s)
    local reserve = mode == 3 and not fullscreen
    s.sidebar.visible = mode > 0 and not (mode == 3 and fullscreen)
    if s.panel_clock_container then s.panel_clock_container.visible = not s.sidebar.visible end
    s.sidebar.ontop = mode == 2 or mode == 3
    if s.sidebar_scrollbar_panel then
        s.sidebar_scrollbar_panel.visible = s.sidebar.visible and s.sidebar_scrollbar.visible
        s.sidebar_scrollbar_panel.ontop = s.sidebar.ontop
    end
    s.sidebar:struts(reserve and {right = s.sidebar.width}
        or {left = 0, right = 0, top = 0, bottom = 0})
end
for s in screen do update_sidebar_mode(s) end

local function cycle_sidebar_mode(s)
    if not s or not s.sidebar then return end
    s.sidebar_mode = ((s.sidebar_mode or 0) + 1) % 4
    update_sidebar_mode(s)
end

local globalkeys = {}
local super_key_down, super_combo_used = false, false
local function mark_super_combo()
    if super_key_down then super_combo_used = true end
end
local function key(modifiers, name, callback)
    for _, modifier in ipairs(modifiers) do
        if modifier == mod then
            local action = callback
            callback = function(...)
                mark_super_combo()
                return action(...)
            end
            break
        end
    end
    globalkeys = gears.table.join(globalkeys, awful.key(modifiers, name, callback))
end
key({mod}, "Return", function() run("kitty") end)
key({mod}, "space", toggle_layout)
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
key({mod}, "Left", function() if client.focus then snap(client.focus, false) end end)
key({mod}, "Right", function() if client.focus then snap(client.focus, true) end end)
local commands = {
    {{}, "XF86AudioRaiseVolume", {home .. "/.local/bin/desktop-volume", "up"}},
    {{}, "XF86AudioLowerVolume", {home .. "/.local/bin/desktop-volume", "down"}},
    {{}, "XF86AudioMute", {home .. "/.local/bin/desktop-volume", "mute"}},
    {{}, "XF86AudioMicMute", {"wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"}},
    {{}, "XF86MonBrightnessUp", {home .. "/.local/bin/desktop-brightness", "up"}},
    {{}, "XF86MonBrightnessDown", {home .. "/.local/bin/desktop-brightness", "down"}},
    {{}, "XF86AudioNext", {"playerctl", "next"}},
    {{}, "XF86AudioPrev", {"playerctl", "previous"}},
    {{}, "XF86AudioPlay", {"playerctl", "play-pause"}},
    {{}, "XF86AudioPause", {"playerctl", "play-pause"}},
    {{mod}, "z", {"playerctl", "previous"}},
    {{mod}, "x", {"playerctl", "play-pause"}},
    {{mod}, "c", {"playerctl", "next"}},  
    {{}, "Print", {home .. "/.local/bin/desktop-screenshot", "full"}},
    {{"Mod1"}, "Print", {home .. "/.local/bin/desktop-screenshot", "window"}},
    {{"Shift"}, "Print", {home .. "/.local/bin/desktop-screenshot", "region"}},
}
for _, entry in ipairs(commands) do
    local command = entry[3]
    key(entry[1], entry[2], function() run(command) end)
end
-- Modifier releases are unreliable as root key callbacks under X11, so poll
-- until Mod4 is physically up; registered Win shortcuts cancel the tap.
local super_tap_timer
local function on_super_press()
    super_key_down, super_combo_used = true, false
    if super_tap_timer then super_tap_timer:stop() end
    super_tap_timer = gears.timer.start_new(0.05, function()
        if super_combo_used then
            super_key_down, super_tap_timer = false, nil
            return false
        end
        for _, modifier in ipairs(awesome._active_modifiers or {}) do
            if modifier == mod then return true end
        end
        local tap = super_key_down and not super_combo_used
        super_key_down, super_tap_timer = false, nil
        if tap then toggle_start_menu() end
        return false
    end)
end
globalkeys = gears.table.join(globalkeys,
    awful.key({}, "Super_L", on_super_press),
    awful.key({}, "Super_R", on_super_press))
root.keys(globalkeys)
root.buttons(gears.table.join(
    awful.button({}, 1, dismiss_start_menu),
    awful.button({}, 3, function() main_menu:toggle() end),
    awful.button({}, 2, function() awful.menu.client_list({theme = {width = 250}}) end),
    awful.button({}, 4, function() adjacent_tag(-1, false, false, true) end),
    awful.button({}, 5, function() adjacent_tag(1, false, false, true) end)
))
local clientkeys = gears.table.join(
    awful.key({"Mod1"}, "F4", function(c) c:kill() end),
    awful.key({"Mod1"}, "F11", function(c) c.fullscreen = not c.fullscreen; c:raise() end),
    awful.key({"Mod1"}, "Escape", lower),
    awful.key({"Mod1"}, "space", window_menu)
)
local clientbuttons = gears.table.join(
    awful.button({}, 1, activate),
    awful.button({mod}, 1, function(c)
        mark_super_combo()
        activate(c)
        awful.mouse.client.move(c)
    end),
    awful.button({mod}, 3, function(c)
        mark_super_combo()
        activate(c)
        awful.mouse.client.resize(c)
    end),
    awful.button({mod}, 2, function(c) mark_super_combo(); lower(c) end),
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
    local titlebars = c._private and c._private.titlebars
    if not titlebars then return end
    local changed = false
    local geometry = c:geometry()
    if titlebars.top then
        local _, height = c:titlebar_top()
        -- Fullscreen must advertise zero frame extents to the application, not
        -- just cover the titlebar with a screen-sized outer window.
        if c.fullscreen and height > 0 then
            awful.titlebar.hide(c, "top")
            changed = true
        elseif not c.fullscreen and height == 0 then
            awful.titlebar.show(c, "top")
            changed = true
        end
    end
    if titlebars.bottom then
        local _, height = c:titlebar_bottom()
        if c.maximized or c.fullscreen then
            if height > 0 then
                awful.titlebar.hide(c, "bottom")
                changed = true
            end
        elseif height == 0 then
            awful.titlebar.show(c, "bottom")
            changed = true
        end
    end
    if changed and not c.maximized and not c.fullscreen then
        -- Showing decorations expands the outer frame; keep the geometry that
        -- Awesome just restored rather than growing the window on every exit.
        c:geometry(geometry)
        if c.maximized_horizontal or c.maximized_vertical then fullscreen_geometry.queue_refit(c) end
    elseif changed then
        -- Coalesce decoration repairs; inspect current state when the call runs.
        -- The fullscreen dispatcher keeps native maximize history untouched.
        fullscreen_geometry.queue_refit(c)
    end
end
client.connect_signal("property::maximized", update_decorations)
client.connect_signal("property::fullscreen", update_decorations)
local function update_panel_for_fullscreen(s)
    if not s or not s.valid or not s.panel or (s.sidebar_ui and s.sidebar_ui.disposed) then return end
    s.panel.visible = not screen_has_fullscreen(s)
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
tag.connect_signal("property::selected", function(t)
    update_panel_for_fullscreen(t.screen)
end)
for _, signal in ipairs({"tagged", "untagged", "property::sticky", "property::hidden"}) do
    client.connect_signal(signal, function(c)
        update_panel_for_fullscreen(c.screen)
    end)
end
client.connect_signal("unmanage", function(c)
    local s = c.screen
    if s then
        -- A fullscreen client may disappear without a final fullscreen=false
        -- event (for example, closing mpv), so recompute after removal.
        gears.timer.delayed_call(function() update_panel_for_fullscreen(s) end)
    end
end)

-- Square glass controls keep Win98 geometry with a restrained Aero sheen.
local function control(c, ui, label, callback, is_close, widget_id, options)
    options = options or {}
    local text = wibox.widget.textbox(label)
    text.align = "center"
    text.valign = "center"
    text.font = "Segoe UI bold 10"
    local button = wibox.widget {
        {text, left = 2, right = 2, top = 1, bottom = 1, widget = wibox.container.margin},
        bg = is_close and titlebar_close_gradient or titlebar_button_gradient,
        fg = appearance.palette.title, border_width = 1,
        border_color = is_close and appearance.palette.close_border or appearance.palette.control_border,
        forced_width = 21, forced_height = 19, id = widget_id,
        widget = wibox.container.background,
    }
    local pressed_bg = appearance.gradient(is_close and "close_pressed" or "control_pressed", 20)
    local held, hovered = false, false
    local function repaint()
        local active = c.valid and options.active and options.active() or false
        button.bg = (held or active) and pressed_bg or (is_close
            and (hovered and titlebar_close_hover or titlebar_close_gradient)
            or (hovered and titlebar_button_hover or titlebar_button_gradient))
        button.border_color = (held or hovered or active) and appearance.palette.title
            or (is_close and appearance.palette.close_border or appearance.palette.control_border)
    end
    local binding = interaction.bind_button(button, {
        activate = callback,
        valid = function()
            if not c.valid or c.fullscreen or c.minimized or not c:isvisible()
                or button._titlebar_present == false then return false end
            local _, height = c:titlebar_top()
            return height > 0
        end,
        paint = function(pressed, inside)
            held, hovered = pressed, inside
            repaint()
        end,
    }, ui)
    if options.signal then ui.connect(c, options.signal, repaint) end
    repaint()
    button._titlebar_tooltip = ui.tip(button, options.tooltip or (is_close and "Close" or (label == "−" and "Minimize" or "Maximize / restore")))
    c._private.release_controls = c._private.release_controls or {}
    c._private.release_controls[widget_id] = binding
    return button
end
client.connect_signal("request::titlebars", function(c)
    if c._private and c._private.titlebar_ui then c._private.titlebar_ui.destroy() end
    local ui = interaction.lifetime()
    c._private = c._private or {}
    c._private.titlebar_ui = ui
    ui.connect(c, "unmanage", function() ui.destroy() end)
    local click_timer = gears.timer({timeout = 0.5, single_shot = true, callback = function() end})
    ui.add(function() click_timer:stop() end)
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
    title:set_font(appearance.fonts.title)
    title:set_align("left")
    title:set_ellipsize("end")
    local icon = awful.titlebar.widget.iconwidget(c)
    icon:buttons(gears.table.join(awful.button({}, 1, function() window_menu(c) end)))
    local ontop_button = control(c, ui, "↑", function()
        dismiss_start_menu()
        c.ontop = not c.ontop
        if c.ontop then c:raise() end
    end, false, "titlebar_ontop", {
        active = function() return c.ontop end,
        signal = "property::ontop",
        tooltip = function() return "Always on top: " .. (c.ontop and "on (click to disable)" or "off (click to enable)") end,
    })
    local minimize_button = control(c, ui, "−", function()
        dismiss_start_menu()
        gears.timer.delayed_call(function()
            if c.valid then c.minimized = true end
        end)
    end, false, "titlebar_minimize")
    local maximize_button = control(c, ui, "□", function() maximize(c) end, false, "titlebar_maximize")
    local close_button = control(c, ui, "×", function() dismiss_start_menu(); c:kill() end, true, "titlebar_close")
    local titlebar_widgets = {
        icon = wibox.widget {
            {icon, forced_width = 18, widget = wibox.container.constraint},
            margins = 2, widget = wibox.container.margin,
        },
        title = wibox.widget {title, buttons = drag, left = 3, widget = wibox.container.margin},
        ontop = ontop_button, minimize = minimize_button, maximize = maximize_button, close = close_button,
    }
    local function update_controls(cancel_press)
        if ui.disposed or not c.valid then return end
        local plan = titlebar_layout.plan(c.width)
        for _, name in ipairs({"ontop", "minimize", "maximize", "close"}) do
            local button = titlebar_widgets[name]
            local present = plan.controls[name] == true and not c.fullscreen and not c.minimized and not c.hidden
            local binding = c._private.release_controls["titlebar_" .. name]
            button._titlebar_present = present
            if not present or (cancel_press and binding.state.armed) then
                binding.cancel()
                button._titlebar_tooltip.hide()
            end
        end
    end
    ui.connect(c, "property::geometry", function() update_controls(true) end)
    for _, signal in ipairs({"property::fullscreen", "property::minimized", "property::hidden"}) do
        ui.connect(c, signal, function() update_controls(false) end)
    end
    update_controls(false)
    awful.titlebar(c, {size = 26,
        bg_normal = titlebar_normal_gradient, bg_focus = titlebar_focus_gradient}):set_widget(titlebar_layout.create(titlebar_widgets))
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
        bg_normal = "#d7eef5aa", bg_focus = "#d7eef5bb"}):setup {
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
    local tag = c.first_tag
    if tag and tag.layout == awful.layout.suit.tile and c.type ~= "dock" and c.type ~= "desktop" then
        local states = floating_restore[c] or {}
        states[tag] = {floating = true, geometry = c:geometry(), maximized = c.maximized}
        floating_restore[c] = states
        c.maximized, c.maximized_horizontal, c.maximized_vertical = false, false, false
        c.floating = false
    end
end)
client.connect_signal("focus", function(c) c.border_color = beautiful.border_focus end)
client.connect_signal("unfocus", function(c) c.border_color = beautiful.border_normal end)
-- Intentionally no mouse::enter focus handler: click-to-focus like Openbox.
if not test_mode then
    awful.spawn({"sh", home .. "/.config/awesome/autostart"})
end
