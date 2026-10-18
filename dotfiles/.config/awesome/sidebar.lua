-- Longhorn-inspired gadget rail; resource, media, and volume tools live here.
local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local Gio = require("lgi").Gio
local cairo = require("lgi").cairo
local gstring = require("gears.string")
local menubar = require("menubar")
local sidebar = {}
local config_dir = awesome.conffile:match("^(.*)/") or "."
local appearance = dofile(config_dir .. "/appearance.lua")
local preferences = dofile(config_dir .. "/sidebar-preferences.lua").load()
local data = dofile(config_dir .. "/sidebar-data.lua")
data.configure(preferences)
local interaction = dofile(config_dir .. "/interaction.lua")
local clock_component = dofile(config_dir .. "/sidebar-clock.lua")
local refresh_component = dofile(config_dir .. "/sidebar-refresh.lua")
local calendar_component = dofile(config_dir .. "/sidebar-calendar.lua")
local scroll_component = dofile(config_dir .. "/sidebar-scroll.lua")
local launcher = dofile(config_dir .. "/sidebar-launch.lua")
local keyboard_view = dofile(config_dir .. "/sidebar-keyboard-view.lua")
local news_component = dofile(config_dir .. "/sidebar-news.lua")
local quick_launch_entries = dofile(config_dir .. "/sidebar-quick-launch.lua").load()
local weather_enabled = os.getenv("AWESOME_TEST_MODE") ~= "1" or os.getenv("AWESOME_TEST_WEATHER") == "1"
local palette = appearance.palette
local sidebar_gradient = appearance.forest(300)
local card_gradient = appearance.gradient("card", 180)
local sidebar_title_gradient = appearance.gradient("selected", 26)
local section_header_gradient = appearance.gradient("blue", 24)
local button_gradient = gears.color {
    type = "linear", from = {0, 0}, to = {0, 30},
    stops = {{0, "#354b64"}, {0.5, "#293c53"}, {1, "#1b2a3c"}},
}
local button_hover_gradient = gears.color {
    type = "linear", from = {0, 0}, to = {0, 30},
    stops = {{0, "#52789e"}, {0.5, "#3d5d7d"}, {1, "#2a4059"}},
}
local button_pressed_gradient = gears.color {
    type = "linear", from = {0, 0}, to = {0, 30},
    stops = {{0, "#17263a"}, {0.5, "#223650"}, {1, "#304967"}},
}

local function read(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local value = file:read("*a")
    file:close()
    return value
end

local function open_document(path)
    return io.open(path, "r")
end

local function launch_document(path)
    -- xdg-open runs Terminal=true apps in its caller's terminal; Awesome has no
    -- TTY, so launch the registered GIO app and let its desktop entry open Kitty.
    local uri = Gio.File.new_for_path(path):get_uri()
    local ok, result = pcall(Gio.AppInfo.launch_default_for_uri, uri, nil)
    if not ok or result ~= true then
        gears.debug.print_error("Could not open sidebar document " .. path .. ": " .. tostring(result))
    end
end

local function read_sidebar_todo()
    local file = open_document(preferences.todo_path)
    if not file then return {} end
    local in_section, items = false, {}
    for line in file:lines() do
        local hashes = line:match("^(#+)%s+")
        if hashes then
            if in_section and #hashes <= 2 then break end
            if #hashes == 2 and line:match("^##%s+Sidebar%s*$") then in_section = true end
        elseif in_section and not line:match("^%s+") then
            local item = line:match("^[-*+]%s+(.+)$") or line:match("^%d+[.)]%s+(.+)$")
            if item then
                items[#items + 1] = item:gsub("%s+$", "")
                if #items == 5 then break end
            end
        end
    end
    file:close()
    return items
end

local function label(text, color, size, bold, align)
    return wibox.widget {
        markup = string.format("<span foreground='%s' size='%dpt'%s>%s</span>",
            color, size, bold and " weight='bold'" or "", text),
        align = align or "left", valign = "center", widget = wibox.widget.textbox,
    }
end

local function set_cached(widget, property, value)
    if widget._sidebar_cache == nil then widget._sidebar_cache = {} end
    if widget._sidebar_cache[property] == value then return false end
    widget._sidebar_cache[property] = value
    -- Text and markup are aliases of the same textbox content, not independent
    -- properties. Otherwise an old cached "unavailable" string can be skipped
    -- after fresh markup has replaced it (and vice versa).
    if property == 'text' then widget._sidebar_cache.markup = nil
    elseif property == 'markup' then widget._sidebar_cache.text = nil end
    widget[property] = value
    return true
end
local function set_text(widget, value) return set_cached(widget, "text", value) end
local function set_markup(widget, value) return set_cached(widget, "markup", value) end
local function set_visible(widget, value) return set_cached(widget, "visible", value) end
local function set_value(widget, value) return set_cached(widget, "value", value) end

local function section_header(text, trailing_widget)
    local title = label(text, palette.title, 10, true, "center")
    local marker = label("−", "#d9f7f4", 10, true, "center")
    marker.forced_width = 18
    local centered_title = wibox.widget {
        title, halign = "center", valign = "center", widget = wibox.container.place,
    }
    local contents
    if trailing_widget then
        -- Reserve real space for status text, including the longer UNKNOWN state.
        contents = wibox.layout.align.horizontal()
        contents:set_left(marker)
        contents:set_middle(centered_title)
        contents:set_right(wibox.widget {
            trailing_widget, left = 6, right = 2, widget = wibox.container.margin,
        })
    else
        contents = wibox.layout.stack()
        local adornments = wibox.layout.align.horizontal()
        adornments:set_left(marker)
        contents:add(adornments)
        contents:add(centered_title)
    end
    local header = wibox.widget {
        {
            {forced_height = 1, bg = "#efffffff", widget = wibox.container.background},
            {
                {contents, left = 2, right = 2, top = 1, bottom = 1,
                    widget = wibox.container.margin},
                forced_height = 20, bg = section_header_gradient,
                widget = wibox.container.background,
            },
            {forced_height = 1, bg = "#123979aa", widget = wibox.container.background},
            layout = wibox.layout.fixed.vertical,
        },
        forced_height = 24, bg = section_header_gradient,
        border_width = 1, border_color = "#588cd4",
        widget = wibox.container.background,
    }
    return header, title, marker
end

local function make_trash_icon()
    local icon = wibox.widget.base.make_widget()
    icon.forced_width, icon.forced_height = 16, 18
    icon.fit = function() return 16, 18 end
    icon.full = nil
    icon.draw = function(_, _, cr)
        cr:set_source(gears.color(appearance.trash_color(icon.full)))
        cr:set_line_width(1.4)
        cr:set_line_cap(cairo.LineCap.ROUND)
        cr:move_to(2, 4); cr:line_to(14, 4)
        cr:move_to(6, 2); cr:line_to(10, 2); cr:line_to(10, 4)
        cr:move_to(4, 5); cr:line_to(5, 16); cr:line_to(11, 16); cr:line_to(12, 5)
        cr:stroke()
        for x = 7, 9, 2 do
            cr:move_to(x, 7); cr:line_to(x, 14)
        end
        cr:stroke()
    end
    return icon
end

local section_padding, section_vertical_padding = 6, 5
local compact_spacing, list_spacing = 3, 4
local function card(widget, height)
    local surface = wibox.widget {
        {widget, left = section_padding, right = section_padding,
            top = section_vertical_padding, bottom = section_vertical_padding,
            widget = wibox.container.margin},
        bg = card_gradient, border_width = 1, border_color = palette.line,
        widget = wibox.container.background,
    }
    return wibox.widget {
        {surface, margins = 1, widget = wibox.container.margin},
        forced_height = height, bg = palette.bevel_shadow,
        border_width = 1, border_color = palette.bevel_light,
        widget = wibox.container.background,
    }
end

local function style_button(button, dismiss_menu)
    local hovered, pressed = false, false
    local function update()
        button.bg = pressed and button_pressed_gradient
            or (hovered and button_hover_gradient or button_gradient)
        button.border_color = pressed and palette.neon
            or (hovered and palette.teal or palette.bevel_light)
    end
    button:connect_signal("mouse::enter", function() hovered = true; update() end)
    button:connect_signal("mouse::leave", function() hovered = false; pressed = false; update() end)
    button:connect_signal("button::press", function()
        if dismiss_menu then dismiss_menu() end
        pressed = true
        update()
    end)
    button:connect_signal("button::release", function() pressed = false; update() end)
    return button
end

local progress_bar_height = 8
local function progress(color)
    return wibox.widget {
        max_value = 100, value = 0, forced_height = progress_bar_height,
        background_color = palette.bg, color = color,
        border_color = palette.line, border_width = 1,
        widget = wibox.widget.progressbar,
    }
end

local function rate(bytes)
    if bytes >= 1024 * 1024 then return string.format("%.1f MB/s", bytes / (1024 * 1024)) end
    if bytes >= 1024 then return string.format("%.0f KB/s", bytes / 1024) end
    return string.format("%.0f B/s", bytes)
end

local battery_module = dofile(config_dir .. "/sidebar-battery.lua")
local battery_stats = battery_module.new(battery_module.runtime(read))

local function filesystem_stats()
    local ok, info = pcall(function()
        return Gio.File.new_for_path("/"):query_filesystem_info("filesystem::size,filesystem::free", nil)
    end)
    if not ok or not info then return nil end
    local total = info:get_attribute_uint64("filesystem::size")
    local free = info:get_attribute_uint64("filesystem::free")
    if not total or not free or total <= 0 then return nil end
    return total, free
end

local function wallpaper_paths(roots)
    local image_extensions = {png = true, jpg = true, jpeg = true, webp = true, bmp = true, gif = true}
    local paths, seen = {}, {}
    for _, root in ipairs(roots) do
        local ok, enumerator = pcall(function()
            return Gio.File.new_for_path(root):enumerate_children("standard::name", 0)
        end)
        if ok and enumerator then
            pcall(function()
                while true do
                    local entry = enumerator:next_file()
                    if not entry then break end
                    local name = entry:get_name()
                    local extension = name:lower():match("%.([%w]+)$")
                    local path = root .. "/" .. name
                    if extension and image_extensions[extension] and not seen[path] then
                        paths[#paths + 1], seen[path] = path, true
                    end
                end
            end)
            pcall(function() enumerator:close() end)
        end
    end
    table.sort(paths)
    return paths
end

local function weather_icon_for(code)
    if code == 0 then return "☀" end
    if code == 1 or code == 2 then return "⛅" end
    if code == 3 then return "☁" end
    if code == 45 or code == 48 then return "≋" end
    if code and code >= 51 and code <= 67 then return "☂" end
    if code and code >= 71 and code <= 77 then return "❄" end
    if code and code >= 80 and code <= 82 then return "☂" end
    if code and code >= 85 and code <= 86 then return "❄" end
    if code and code >= 95 then return "⚡" end
    return "·"
end

local function weather_description(code)
    if code == 0 then return "Clear" end
    if code == 1 then return "Mostly clear" end
    if code == 2 then return "Partly cloudy" end
    if code == 3 then return "Overcast" end
    if code == 45 or code == 48 then return "Fog" end
    if code and code >= 51 and code <= 67 then return "Drizzle / rain" end
    if code and code >= 71 and code <= 77 then return "Snow" end
    if code and code >= 80 and code <= 82 then return "Rain showers" end
    if code and code >= 85 and code <= 86 then return "Snow showers" end
    if code and code >= 95 then return "Thunderstorm" end
    return "Conditions unavailable"
end

local function network_stats()
    local data = read("/proc/net/dev")
    if not data then return nil end
    local rx, tx = 0, 0
    for line in data:gmatch("[^\n]+") do
        local name, counters = line:match("^%s*([^:]+):%s*(.*)")
        if name and name:gsub("%s", "") ~= "lo" then
            local values = {}
            for value in counters:gmatch("%d+") do values[#values + 1] = tonumber(value) end
            rx, tx = rx + (values[1] or 0), tx + (values[9] or 0)
        end
    end
    return rx, tx
end

-- Clock ticks are cheap and shared; they never trigger system probes.
data.define("clock", 1, function(done) done(os.time()) end)

-- Fast-changing counters stay responsive; slow-changing battery/storage probes are separate.
data.define("stats", 1, function(done)
    local ok, value = pcall(function()
        local rx, tx = network_stats()
        return {stat = read("/proc/stat"), meminfo = read("/proc/meminfo") or "", rx = rx, tx = tx}
    end)
    if ok then done(value) else done(nil, tostring(value)) end
end)
data.define("power", 30, function(done)
    local root_total, root_free = filesystem_stats()
    return battery_stats(function(capacity, battery_state, mouse_capacity, mouse_state, err)
        if err then done(nil, err); return end
        done({root_total = root_total, root_free = root_free, capacity = capacity,
            battery_state = battery_state, mouse_capacity = mouse_capacity, mouse_state = mouse_state})
    end)
end)

local function action_button(text, callback, dismiss_menu, bind)
    local button = style_button(wibox.widget {
        {label(text, palette.teal, 14, true, "center"),
            halign = "center", valign = "center", widget = wibox.container.place},
        forced_width = 46, forced_height = 28,
        bg = button_gradient, border_width = 1, border_color = palette.bevel_light,
        widget = wibox.container.background,
    }, dismiss_menu)
    if bind then bind(button, callback) else button:buttons(gears.table.join(awful.button({}, 1, callback))) end
    return button
end

local function quick_launch_button(text, icon_name, callback, dismiss_menu, bind)
    local app_icon = wibox.widget.imagebox()
    app_icon.forced_width, app_icon.forced_height, app_icon.resize = 16, 16, true
    local icon_ok, icon_path = pcall(menubar.utils.lookup_icon, icon_name)
    local fallback_icons = {
        ["utilities-terminal"] = "utilities-terminal.png",
        ["system-file-manager"] = "system-file-manager.png",
        ["utilities-system-monitor"] = "utilities-system-monitor.png",
        ["preferences-system"] = "/usr/share/icons/breeze/apps/32/preferences-system.svg",
        ["system-run"] = "system-run.png",
        ["web-browser"] = "web-browser.png",
        ["audio-volume-high"] = "audio-volume-high.png",
        ["applications-games"] = "applications-games.png",
        ["input-gaming"] = "applications-games.png",
        ["system-suspend"] = "/usr/share/icons/hicolor/48x48/actions/xfsm-suspend.png",
    }
    if not icon_ok or type(icon_path) ~= "string" or not gears.filesystem.file_readable(icon_path) then
        local fallback = fallback_icons[icon_name]
        icon_path = fallback and (fallback:sub(1, 1) == "/" and fallback
            or "/usr/share/icons/AdwaitaLegacy/32x32/legacy/" .. fallback) or nil
    end
    if icon_path and gears.filesystem.file_readable(icon_path) then
        app_icon.image = icon_path
    end
    local contents = wibox.layout.fixed.horizontal()
    contents.spacing = 4
    contents:add(app_icon)
    contents:add(label(gstring.xml_escape(text), "#d7eee8", 9, true, "center"))
    local button = style_button(wibox.widget {
        {contents,
            halign = "center", valign = "center", widget = wibox.container.place},
        forced_width = 86, forced_height = 24,
        bg = button_gradient, border_width = 1, border_color = palette.bevel_light,
        widget = wibox.container.background,
    }, dismiss_menu)
    if bind then bind(button, callback) else button:buttons(gears.table.join(awful.button({}, 1, callback))) end
    return button
end

function sidebar.create(s, dismiss_menu)
    local ui = interaction.lifetime()
    local section_order, sections_by_id = {}, {}
    local panel
    s.sidebar_ui = ui
    local function bind_sidebar_action(widget, callback, section_id, extra_valid, group)
        local normal = button_gradient
        local binding = interaction.bind_button(widget, {
            activate = callback,
            valid = function()
                local section = section_id and sections_by_id[section_id]
                return not ui.disposed and s.valid and s.sidebar_mode > 0 and s.sidebar
                    and s.sidebar.visible and panel and (not section or not section.collapsed)
                    and (not extra_valid or extra_valid())
            end,
            paint = function(pressed, hovered)
                widget.bg = pressed and button_pressed_gradient or (hovered and button_hover_gradient or normal)
                widget.border_color = pressed and palette.neon or (hovered and palette.teal or palette.bevel_light)
            end,
        }, group or ui)
        widget._sidebar_keyboard_action = callback
        widget._sidebar_release_binding = binding
        return binding
    end
    local make_action_button = action_button
    local function action_button(text, callback, dismiss)
        local widget = make_action_button(text, callback, dismiss,
            function(button, activate) bind_sidebar_action(button, activate, "now-playing") end)
        ui.tip(widget, ({["«"] = "Previous track", ["▶"] = "Play / pause", ["»"] = "Next track"})[text])
        return widget
    end
    local sidebar_width = 300
    local state_root = os.getenv("XDG_STATE_HOME")
        or ((os.getenv("HOME") or ".") .. "/.local/state")
    local section_state_path = state_root .. "/awesome/sidebar-sections"
    local all_section_ids = {"calendar", "todo", "news", "quick-launch", "system-status", "codex",
        "crypto", "weather", "now-playing", "wallpaper"}
    local known_section_ids, collapsed_ids, saved_order_ids, saved_order_seen = {}, {}, {}, {}
    for _, id in ipairs(all_section_ids) do known_section_ids[id] = true end
    local saved_enabled_ids, saved_state_version
    local saved_sections = read(section_state_path) or ""
    for id in saved_sections:gmatch("[^\r\n]+") do
        id = id:gsub("^%s+", ""):gsub("%s+$", "")
        local order = id:match("^order=(.*)$")
        local enabled = id:match("^enabled=(.*)$")
        local version = id:match("^version=(%d+)$")
        if version then
            saved_state_version = tonumber(version)
        elseif order then
            for section_id in order:gmatch("[^,]+") do
                section_id = section_id:gsub("^%s+", ""):gsub("%s+$", "")
                if known_section_ids[section_id] and not saved_order_seen[section_id] then
                    saved_order_ids[#saved_order_ids + 1] = section_id
                    saved_order_seen[section_id] = true
                end
            end
        elseif enabled then
            saved_enabled_ids = {}
            for section_id in enabled:gmatch("[^,]+") do
                section_id = section_id:gsub("^%s+", ""):gsub("%s+$", "")
                if known_section_ids[section_id] then saved_enabled_ids[section_id] = true end
            end
        elseif known_section_ids[id] then
            collapsed_ids[id] = true
        end
    end
    if saved_enabled_ids and (saved_state_version or 0) < 2 then
        -- The news section did not exist before version 2, so honor the user's
        -- saved choices while enabling the newly introduced section once.
        saved_enabled_ids.news = true
    end
    if saved_sections ~= "" and next(saved_order_seen) and (saved_state_version or 0) < 2 and not saved_order_seen.news then
        for index, id in ipairs(saved_order_ids) do
            if id == "todo" then
                table.insert(saved_order_ids, index + 1, "news")
                saved_order_seen.news = true
                break
            end
        end
    end
    local enabled_ids = saved_enabled_ids or {}
    if not saved_enabled_ids then
        for _, id in ipairs(all_section_ids) do
            if id ~= "quick-launch" then enabled_ids[id] = true end
        end
    end
    for _, id in ipairs(all_section_ids) do
        if not saved_order_seen[id] then
            saved_order_ids[#saved_order_ids + 1] = id
            saved_order_seen[id] = true
        end
    end
    s.sidebar_enabled_sections = enabled_ids
    local function save_section_state()
        local ordered_ids, active_index = {}, 1
        for _, id in ipairs(saved_order_ids) do
            if enabled_ids[id] then
                local section = section_order[active_index]
                if section then
                    ordered_ids[#ordered_ids + 1] = section.id
                    active_index = active_index + 1
                end
            else
                ordered_ids[#ordered_ids + 1] = id
            end
        end
        while active_index <= #section_order do
            ordered_ids[#ordered_ids + 1] = section_order[active_index].id
            active_index = active_index + 1
        end
        saved_order_ids = ordered_ids

        local directory = section_state_path:match("^(.*)/")
        if not directory or not pcall(gears.filesystem.make_directories, directory) then return end
        local temporary = section_state_path .. ".tmp"
        local file = io.open(temporary, "w")
        if not file then return end
        file:write("version=2\n")
        file:write("order=", table.concat(saved_order_ids, ","), "\n")
        file:write("enabled=")
        local first_enabled = true
        for _, id in ipairs(all_section_ids) do
            if enabled_ids[id] then
                if not first_enabled then file:write(",") end
                file:write(id)
                first_enabled = false
            end
        end
        file:write("\n")
        for _, id in ipairs(all_section_ids) do
            local section = sections_by_id[id]
            if section and section.collapsed then file:write(id, "\n") end
        end
        file:close()
        if not os.rename(temporary, section_state_path) then os.remove(temporary) end
    end
    local begin_section_drag
    local function collapsible_card(id, title_text, body, expanded_height, trailing_widget)
        local header, title, marker = section_header(title_text, trailing_widget)
        local body_container = wibox.widget {
            body, left = 2, right = 2, top = 6, bottom = 0,
            widget = wibox.container.margin,
        }
        local contents = wibox.layout.fixed.vertical()
        contents.spacing = 0
        contents:add(header)
        contents:add(body_container)
        local section_card = card(contents, expanded_height)
        local section = {
            id = id, title = title_text, header = header, title_widget = title,
            marker = marker, body = body, body_container = body_container, card = section_card,
            trailing_widget = trailing_widget,
            expanded_height = expanded_height, collapsed = collapsed_ids[id] == true,
        }
        local collapsed_height = header.forced_height + 2 * section_vertical_padding + 6
        local function update()
            body.visible = not section.collapsed
            body_container.visible = not section.collapsed
            marker.markup = string.format(
                "<span foreground='%s' size='10pt' weight='bold'>%s</span>",
                "#d9f7f4", section.collapsed and "▸" or "▾")
            section_card.forced_height = section.collapsed and collapsed_height or section.expanded_height
        end
        local function toggle()
            section.collapsed = not section.collapsed
            update()
            save_section_state()
            if section.on_toggle then section.on_toggle(section.collapsed) end
            if dismiss_menu then dismiss_menu() end
        end
        section.toggle_action = toggle
        ui.tip(title, "Click to fold / expand · Drag to reorder")
        ui.tip(marker, "Fold / expand section")
        ui.add(function() title:buttons({}); marker:buttons({}) end)
        title:buttons(gears.table.join(awful.button({}, 1, function()
            if begin_section_drag then begin_section_drag(section) else toggle() end
        end)))
        marker:buttons(gears.table.join(awful.button({}, 1, toggle)))
        section.set_expanded_height = function(height)
            section.expanded_height = height
            if not section.collapsed then section_card.forced_height = height end
        end
        update()
        section_order[#section_order + 1] = section
        sections_by_id[id] = section
        s.sidebar_sections = sections_by_id
        return section_card, section.set_expanded_height, section
    end

    local clock_ui = clock_component.create {appearance = appearance, interaction = interaction,
        label = label, card = card, dismiss = dismiss_menu,
        on_mode = function(mode) s.sidebar_clock_mode = mode end}
    ui.add(clock_ui.destroy)
    local clock, digital_time, date = clock_ui.clock, clock_ui.digital, clock_ui.date
    local clock_card = clock_ui.widget
    s.sidebar_clock_toggle = clock_ui.toggle
    local cpu_text = label("CPU  ?", palette.text, 10, false)
    local memory_text = label("Memory  ?", palette.text, 10, false)
    local battery_text = label("Battery  --", palette.text, 10, false)
    local mouse_battery_text = label("Mouse  --", palette.text, 10, false)
    mouse_battery_text.visible = false
    local root_text = label("Free /  ?", palette.text, 10, false)
    local network_text = label("↓ ?   ↑ ?", palette.text, 10, false)
    local cpu_bar, memory_bar = progress(palette.green), progress(palette.green)
    local battery_bar, root_bar = progress(palette.green), progress(palette.green)
    local mouse_battery_bar = progress(palette.teal)
    mouse_battery_bar.visible = false
    local volume_text = label("Volume  --", palette.text, 10, false)
    local volume_bar = progress(palette.teal)
    local media_text = label("Checking player…", palette.text, 11, false, "center")
    media_text.wrap = "word_char"
    media_text.ellipsize = "end"

    local header_title = label("MashedD's AwesomeBar", "#f2fffb", 9, true)
    header_title.font = appearance.fonts.title
    local header = wibox.widget {
        {
            {forced_height = 1, bg = "#f2ffffff", widget = wibox.container.background},
            {
                {header_title, left = 10, right = 6, widget = wibox.container.margin},
                forced_height = 23, bg = sidebar_title_gradient,
                widget = wibox.container.background,
            },
            {forced_height = 1, bg = "#123f5eaa", widget = wibox.container.background},
            layout = wibox.layout.fixed.vertical,
        },
        forced_height = 26, bg = sidebar_title_gradient,
        border_width = 1, border_color = "#6bb5ca",
        widget = wibox.container.background,
    }
    local wallpapers = wallpaper_paths(preferences.wallpaper_dirs)
    local wallpaper_state = (os.getenv("XDG_STATE_HOME") or os.getenv("HOME") .. "/.local/state")
        .. "/awesome/wallpaper"
    local selected_wallpaper = read(wallpaper_state)
    if selected_wallpaper then selected_wallpaper = selected_wallpaper:gsub("%s+$", "") end
    local wallpaper_index = 1
    for index, path in ipairs(wallpapers) do
        if path == selected_wallpaper then wallpaper_index = index; break end
    end
    local preview = wibox.widget.imagebox()
    preview.resize = true
    preview.forced_height = 102
    local wallpaper_name = label("No PNG wallpapers found", palette.muted, 9, false, "center")
    wallpaper_name.forced_width = 190
    local function update_wallpaper_preview()
        local path = wallpapers[wallpaper_index]
        if not path then return end
        preview.image = path
        wallpaper_name.text = path:match("([^/]+)$") or path
        s.sidebar_wallpaper_index, s.sidebar_wallpaper_path = wallpaper_index, path
    end
    local function apply_wallpaper()
        local path = wallpapers[wallpaper_index]
        if not path then return end
        gears.wallpaper.maximized(path, s, false)
        local directory = wallpaper_state:match("^(.*)/")
        if directory then gears.filesystem.make_directories(directory) end
        local file = io.open(wallpaper_state, "w")
        if file then file:write(path, "\n"); file:close() end
    end
    local function small_button(text, callback, tooltip)
        local button = style_button(wibox.widget {
            label(text, palette.muted, 11, true, "center"),
            forced_width = 26, forced_height = 20,
            bg = button_gradient, border_width = 1, border_color = palette.bevel_light,
            widget = wibox.container.background,
        }, dismiss_menu)
        bind_sidebar_action(button, callback, "wallpaper")
        ui.tip(button, tooltip)
        return button
    end
    local function show_previous_wallpaper()
        if #wallpapers > 0 then
            wallpaper_index = ((wallpaper_index - 2) % #wallpapers) + 1
            update_wallpaper_preview()
        end
    end
    local function show_next_wallpaper()
        if #wallpapers > 0 then
            wallpaper_index = (wallpaper_index % #wallpapers) + 1
            update_wallpaper_preview()
        end
    end
    local previous_wallpaper = small_button("‹", show_previous_wallpaper, "Previous wallpaper")
    local next_wallpaper = small_button("›", show_next_wallpaper, "Next wallpaper")
    bind_sidebar_action(preview, apply_wallpaper, "wallpaper")
    ui.tip(preview, "Apply selected wallpaper")
    local wallpaper_controls = wibox.widget {
        previous_wallpaper, wallpaper_name, next_wallpaper,
        spacing = 8, layout = wibox.layout.fixed.horizontal,
    }
    update_wallpaper_preview()
    preview:connect_signal("button::press", function() if dismiss_menu then dismiss_menu() end end)
    local preview_centered = {preview, halign = "center", valign = "center", widget = wibox.container.place}
    local wallpaper_body = wibox.widget {
        preview_centered,
        {wallpaper_controls, halign = "center", widget = wibox.container.place},
        spacing = 5, layout = wibox.layout.fixed.vertical,
    }
    local wallpaper_card = collapsible_card("wallpaper", "WALLPAPER", wallpaper_body)

    local weather_icon = label("☁", palette.teal, 22, true, "center")
    weather_icon.font = "Noto Sans Symbols 2 20"
    weather_icon.forced_width = 32
    local weather_icon_slot = {
        weather_icon, halign = "center", valign = "center",
        forced_width = 32, forced_height = 36, widget = wibox.container.place,
    }
    local weather_main = label("Weather loading…", palette.text, 14, true, "center")
    local weather_detail = label(gstring.xml_escape(preferences.weather_label), palette.muted, 10, false, "center")
    weather_main.forced_width, weather_detail.forced_width = 190, 190
    local weather_text_stack = wibox.widget {
        weather_main, weather_detail, spacing = compact_spacing,
        layout = wibox.layout.fixed.vertical,
    }
    local weather_text_centered = {
        weather_text_stack, halign = "left", valign = "center", widget = wibox.container.place,
    }
    local weather_line = wibox.widget {
        weather_icon_slot, weather_text_centered, spacing = 8,
        layout = wibox.layout.fixed.horizontal,
    }
    local function freshness(name, body)
        local status = label("", palette.amber, 8, true, "center")
        status.visible = false
        body:add(status)
        local tooltip = awful.tooltip {objects = {body}, timer_function = function()
            local state = data.state(name)
            if not state.updated then return gstring.xml_escape(state.error or "Waiting for first reading") end
            return gstring.xml_escape(string.format("Last success: %s\nAge: %d minutes%s",
                os.date("%Y-%m-%d %H:%M:%S", state.updated),
                math.max(0, math.floor((os.time() - state.updated) / 60)),
                state.error and ("\n" .. state.error) or ""))
        end}
        return function(state)
            local changed = set_text(status, state.stale and "STALE" or "")
            changed = set_visible(status, state.stale == true) or changed
            if changed then body:emit_signal("widget::layout_changed") end
        end, tooltip
    end
    local function set_weather_icon(icon)
        set_markup(weather_icon, string.format("<span foreground='%s' size='22pt'>%s</span>", palette.teal, icon))
    end
    local function update_weather() data.refresh("weather") end
    local function render_weather(state)
        local value = state.value
        if not value then
            set_weather_icon("·")
            set_text(weather_main, "Weather unavailable")
            set_text(weather_detail, "Click to try again")
            return
        end
        set_weather_icon(weather_icon_for(value.condition))
        set_text(weather_main, string.format("%.0f°C  •  %s", value.temperature, weather_description(value.condition)))
        set_text(weather_detail, string.format("Feels %.0f°C  •  Wind %.0f km/h", value.apparent, value.wind))
    end
    local weather_body = wibox.widget {
        {weather_line, halign = "center", valign = "center", widget = wibox.container.place},
        spacing = 3, layout = wibox.layout.fixed.vertical,
    }
    weather_body:buttons(gears.table.join(awful.button({}, 1, function()
        if weather_enabled then update_weather() end
    end)))
    local weather_card = collapsible_card("weather",
        gstring.xml_escape(string.upper(preferences.weather_label)) .. " · WEATHER", weather_body)

    local function find_trezor_appimage()
        local root = (os.getenv("HOME") or "") .. "/Programs"
        local ok, enumerator = pcall(function()
            return Gio.File.new_for_path(root):enumerate_children(
                "standard::name,standard::type,time::modified", 0)
        end)
        if not ok or not enumerator then return nil end
        local candidates = {}
        local read_ok = pcall(function()
            while true do
                local info = enumerator:next_file()
                if not info then break end
                local name = info:get_name()
                if name:match("^Trezor%-Suite%-.+%.AppImage$")
                    and tostring(info:get_file_type()) == "REGULAR" then
                    local modified = tonumber(info:get_attribute_uint64("time::modified")) or 0
                    candidates[#candidates + 1] = {path = root .. "/" .. name, modified = modified}
                end
            end
        end)
        pcall(function() enumerator:close() end)
        if not read_ok then return nil end
        table.sort(candidates, function(a, b)
            if a.modified ~= b.modified then return a.modified < b.modified end
            return a.path < b.path
        end)
        return candidates[#candidates] and candidates[#candidates].path or nil
    end
    local function open_trezor_suite()
        if dismiss_menu then dismiss_menu() end
        local path = find_trezor_appimage()
        if not path then
            awful.spawn({"notify-send", "Trezor Suite", "No Trezor-Suite-*.AppImage found in ~/Programs"})
            return
        end
        local ok = pcall(awful.spawn, {path})
        if not ok then
            awful.spawn({"notify-send", "Trezor Suite", "Could not launch " .. path})
        end
    end
    local crypto_prices = {}
    local function crypto_cell(symbol)
        local entry = {text = "--", hovered = false}
        local row = wibox.widget.textbox()
        local function update()
            local underline = entry.hovered and " underline='single'" or ""
            set_markup(row, string.format(
                "<span foreground='%s' size='9pt' weight='bold'%s>%s</span> " ..
                    "<span foreground='%s' size='9pt' weight='bold'%s>%s</span>",
                palette.teal, underline, symbol, palette.green, underline, entry.text))
        end
        entry.set = function(value)
            entry.text = value
            update()
        end
        entry.widget = row
        row:buttons(gears.table.join(awful.button({}, 1, open_trezor_suite)))
        row:connect_signal("mouse::enter", function() entry.hovered = true; update() end)
        row:connect_signal("mouse::leave", function() entry.hovered = false; update() end)
        crypto_prices[symbol] = entry
        update()
        return row
    end
    local crypto_line = wibox.layout.fixed.horizontal()
    crypto_line.spacing = 12
    crypto_line:add(crypto_cell("BTC"))
    crypto_line:add(crypto_cell("ETH"))
    crypto_line:add(crypto_cell("LTC"))
    local crypto_body = wibox.widget {
        {crypto_line, halign = "center", widget = wibox.container.place},
        spacing = compact_spacing, layout = wibox.layout.fixed.vertical,
    }
    local crypto_card = collapsible_card("crypto", "CRYPTO PRICES · USD", crypto_body)
    local function refresh_crypto() data.refresh("crypto") end
    local function render_crypto(state)
        for symbol, entry in pairs(crypto_prices) do entry.set(state.value and state.value[symbol] or "--") end
    end

    local trash_icon = make_trash_icon()
    local trash_state = label("UNKNOWN", appearance.trash_color(nil), 9, true)
    local trash_status = wibox.widget {
        trash_icon, trash_state, spacing = 4,
        layout = wibox.layout.fixed.horizontal,
    }
    local function refresh_trash_status() data.refresh("trash") end
    local function render_trash(state)
        local full
        if state.value and not state.error then full = state.value.full end
        trash_icon.full = full
        trash_icon:emit_signal("widget::redraw_needed")
        local text, color = full == nil and "UNKNOWN" or (full and "FULL" or "EMPTY"),
            appearance.trash_color(full)
        set_markup(trash_state, string.format(
            "<span foreground='%s' size='9pt' weight='bold'>%s</span>", color, text))
        s.sidebar_trash_full = full
    end
    local function open_trash() awful.spawn({"pcmanfm", "trash:///"}) end
    trash_status:buttons(gears.table.join(awful.button({}, 1, open_trash)))
    if dismiss_menu then trash_status:connect_signal("button::press", dismiss_menu) end

    local keyboard_launches = {}
    local launch_rows = wibox.layout.fixed.vertical()
    launch_rows.spacing = 2
    s.sidebar_quick_launch_buttons = {}
    local visible_launches = {}
    for _, entry in ipairs(quick_launch_entries) do
        if entry.enabled then visible_launches[#visible_launches + 1] = entry end
    end
    s.sidebar_quick_launch_entries = quick_launch_entries
    s.sidebar_quick_launch_empty = #visible_launches == 0
    for first = 1, #visible_launches, 3 do
        local last = math.min(first + 2, #visible_launches)
        -- Rows are chunked from the filtered sequence of enabled entries.
        local row = wibox.layout.fixed.horizontal()
        row.spacing = 4
        for index = first, last do
            local entry = visible_launches[index]
            local button = quick_launch_button(entry.label, entry.icon,
                function() launcher.run(entry) end, dismiss_menu, function(widget, activate)
                    bind_sidebar_action(widget, activate, "quick-launch")
                end)
            ui.tip(button, function() return launcher.tooltip(entry) end)
            s.sidebar_quick_launch_buttons[entry.label] = {widget = button, entry = entry}
            keyboard_launches[#keyboard_launches + 1] = {id = "quick-launch:" .. entry.label,
                widget = button, activate = button._sidebar_keyboard_action,
                exit = true, section = "quick-launch"}
            row:add(button)
        end
        launch_rows:add(wibox.widget {
            row, halign = "center", valign = "center", widget = wibox.container.place,
        })
    end
    local quick_launch_body
    if #visible_launches == 0 then
        quick_launch_body = wibox.widget {
            label("No launchers configured", palette.muted, 9, false, "center"),
            layout = wibox.layout.fixed.vertical,
        }
    else
        quick_launch_body = wibox.widget {
            launch_rows,
            layout = wibox.layout.fixed.vertical,
        }
    end
    local quick_launch_card = collapsible_card(
        "quick-launch", "QUICK LAUNCH", quick_launch_body)
    s.sidebar_launch = launcher

    local volume_control = wibox.layout.fixed.vertical()
    volume_control.spacing = 4
    local stats_body = wibox.widget {
        cpu_text, cpu_bar,
        memory_text, memory_bar,
        battery_text, battery_bar,
        mouse_battery_text, mouse_battery_bar,
        root_text, root_bar,
        volume_control, network_text,
        spacing = compact_spacing, layout = wibox.layout.fixed.vertical,
    }
    local stats_card = collapsible_card("system-status", "SYSTEM STATUS", stats_body, nil, trash_status)

    local function codex_window_row(period)
        local summary = label(period .. " unavailable", palette.muted, 9, false)
        local bar = progress(palette.green)
        bar.forced_height = progress_bar_height
        return wibox.widget {
            {summary, bar, spacing = compact_spacing, layout = wibox.layout.fixed.vertical},
            layout = wibox.layout.fixed.vertical,
        }, {summary = summary, bar = bar, remaining = nil}
    end
    local codex_5h_widget, codex_5h = codex_window_row("5h")
    local codex_7d_widget, codex_7d = codex_window_row("7d")
    local codex_resets = label("--", palette.teal, 9, false)
    codex_resets.wrap = "word_char"
    local codex_body = wibox.widget {
        codex_5h_widget, codex_7d_widget, codex_resets,
        spacing = compact_spacing, layout = wibox.layout.fixed.vertical,
    }
    local function refresh_codex() data.refresh("codex") end
    local codex_refresh_button = style_button(wibox.widget {
        {label("⟳", palette.title, 10, true, "center"),
            halign = "center", valign = "center", widget = wibox.container.place},
        forced_width = 22, forced_height = 18,
        bg = button_gradient, border_width = 1, border_color = palette.bevel_light,
        widget = wibox.container.background,
    }, dismiss_menu)
    bind_sidebar_action(codex_refresh_button, refresh_codex, "codex")
    ui.tip(codex_refresh_button, "Refresh Codex usage")
    local codex_card = collapsible_card("codex", "CODEX", codex_body, nil, codex_refresh_button)
    local function render_codex(state)
        -- Quotas are a safety decision: history must never look like current headroom.
        local value = not state.error and not state.stale and state.value or nil
        for _, row in ipairs({{codex_5h, "5h", "five"}, {codex_7d, "7d", "week"}}) do
            local widget, period, key = row[1], row[2], row[3]
            widget.remaining = value and value[key] or nil
            set_visible(widget.bar, value ~= nil)
            if value then
                set_markup(widget.summary, string.format(
                    "<span foreground='%s' size='9pt'>%s  %d%% left · %s</span>",
                    palette.text, period, value[key], gstring.xml_escape(value[key .. "_reset"])))
                set_value(widget.bar, value[key])
                set_cached(widget.bar, "color", appearance.remaining_color(value[key]))
            else
                set_value(widget.bar, 0)
                set_text(widget.summary, period .. " usage unavailable")
            end
        end
        set_markup(codex_resets, string.format("<span foreground='%s' size='9pt'>%s</span>",
            palette.muted, gstring.xml_escape(value and value.resets or "--")))
    end

    local media_previous = action_button("«", function() data.command({"playerctl", "previous"}, function() return true end, function() end) end, dismiss_menu)
    local media_toggle = action_button("▶", function() data.command({"playerctl", "play-pause"}, function() return true end, function() end) end, dismiss_menu)
    local media_next = action_button("»", function() data.command({"playerctl", "next"}, function() return true end, function() end) end, dismiss_menu)
    local media_controls = wibox.widget {
        media_previous, media_toggle, media_next, spacing = 8,
        layout = wibox.layout.fixed.horizontal,
    }
    local media_controls_centered = {
        media_controls, halign = "center", valign = "center", widget = wibox.container.place,
    }
    local media_body = wibox.widget {
        media_text, media_controls_centered,
        spacing = list_spacing, layout = wibox.layout.fixed.vertical,
    }
    local media_card = collapsible_card("now-playing", "NOW PLAYING", media_body)

    volume_control:add(volume_text)
    volume_control:add(volume_bar)
    local function update_volume() data.refresh("volume") end
    local function render_volume(state)
        local value = not state.error and state.value
        set_markup(volume_text, string.format(
            "<span foreground='%s' size='9pt'>Volume  %s</span>",
            value and value.muted and palette.amber or palette.text,
            value and (value.muted and "Mute" or string.format("%.0f%%", value.level * 100)) or "--"))
        set_value(volume_bar, value and math.floor(value.level * 100 + 0.5) or 0)
    end
    local function change_volume(action)
        data.command({os.getenv("HOME") .. "/.local/bin/desktop-volume", action}, function() return true end, update_volume)
    end
    local function open_mixer() awful.spawn("pavucontrol") end
    volume_control:buttons(gears.table.join(
        awful.button({}, 1, open_mixer),
        awful.button({}, 2, function() change_volume("mute") end),
        awful.button({}, 3, function() change_volume("mute") end)
    ))
    if dismiss_menu then volume_control:connect_signal("button::press", dismiss_menu) end
    local suppress_scroll_click = false
    local todo_entries = {}
    local todo_list = wibox.layout.fixed.vertical()
    todo_list.spacing = list_spacing
    local function refresh_todo()
        todo_list:reset()
        todo_entries = read_sidebar_todo()
        if #todo_entries == 0 then
            local row = label("No items in " .. gstring.xml_escape(preferences.todo_path)
                .. " · ## Sidebar", palette.muted, 9, false)
            todo_list:add(row)
        else
            for _, entry in ipairs(todo_entries) do
                local row = label("•  " .. entry, palette.text, 9, false)
                row.wrap, row.valign = "word_char", "top"
                todo_list:add(row)
            end
        end
        s.sidebar_todo_entries = todo_entries
    end
    refresh_todo()
    local todo_body = wibox.widget {
        todo_list, spacing = 5, layout = wibox.layout.fixed.vertical,
    }
    local function open_todo_document()
        if suppress_scroll_click then return end
        launch_document(preferences.todo_path)
        if dismiss_menu then dismiss_menu() end
    end
    todo_body:buttons(gears.table.join(awful.button({}, 1, open_todo_document)))
    local todo_card = collapsible_card("todo", "TODO", todo_body)

    local function open_calendar_document()
        if suppress_scroll_click then return end
        launch_document(preferences.calendar_path)
        if dismiss_menu then dismiss_menu() end
    end
    local calendar_ui = calendar_component.create {
        appearance = appearance, interaction = interaction, label = label,
        path = preferences.calendar_path,
        blocked = function() return suppress_scroll_click end, open = open_calendar_document,
        button_normal = button_gradient, button_hover = button_hover_gradient,
        bind = function(widget, callback) bind_sidebar_action(widget, callback, "calendar") end,
        wrap = function(body) return collapsible_card("calendar", "CALENDAR", body) end,
        on_entries = function(entries) s.sidebar_calendar_entries = entries end,
    }
    ui.add(calendar_ui.destroy)
    local calendar_card, refresh_calendar = calendar_ui.widget, calendar_ui.refresh
    s.sidebar_calendar_refresh = refresh_calendar
    s.sidebar_calendar_month = calendar_ui.month
    s.sidebar_calendar_selected_date = calendar_ui.selected_date
    s.sidebar_calendar_select_date = calendar_ui.select_date
    s.sidebar_calendar_previous_action = function() calendar_ui.shift_month(-1) end
    s.sidebar_calendar_next_action = function() calendar_ui.shift_month(1) end
    s.sidebar_calendar_weekday_order = calendar_ui.weekday_order
    s.sidebar_calendar_grid = calendar_ui.grid
    s.sidebar_calendar_day_cells = calendar_ui.day_cells
    s.sidebar_calendar_events_widget = calendar_ui.events
    s.sidebar_calendar_previous_button = calendar_ui.previous
    s.sidebar_calendar_next_button = calendar_ui.next

    local sidebar_height = math.max(1, s.geometry.height - 30)
    s.sidebar_scroll_position = 0
    local scroll_ui
    local function set_scroll_offset(offset) scroll_ui.set_offset(offset) end
    local function scroll_by(delta) scroll_ui.scroll_by(delta) end
    local news_card
    local function make_news_button(text, callback, width, group)
        local text_widget = label("", palette.text, 8, true, "center")
        local button_text = tostring(text)
        local function update_text(value)
            button_text = tostring(value)
            set_markup(text_widget, string.format(
                "<span foreground='%s' size='8pt' weight='bold'>%s</span>",
                palette.text, gstring.xml_escape(button_text)))
        end
        update_text(text)
        local button = style_button(wibox.widget {
            {text_widget, left = 4, right = 4, widget = wibox.container.margin},
            forced_width = width, forced_height = 24,
            bg = button_gradient, border_width = 1, border_color = palette.bevel_light,
            widget = wibox.container.background,
        })
        bind_sidebar_action(button, callback, "news", nil, group)
        button.set_text = update_text
        button.get_text = function() return button_text end
        return button
    end
    local popup_width = math.max(180, math.min(520, s.geometry.width - sidebar_width - 24))
    local popup_height = sidebar_height
    local news_ui = news_component.new {
        screen = s, ui = ui, data = data, interaction = interaction, appearance = appearance,
        label = label, button = make_news_button, helper = (os.getenv("HOME") or "") .. "/.local/bin/desktop-news",
        dismiss = dismiss_menu, popup_width = popup_width, popup_height = popup_height,
        list_height = math.max(120, popup_height - 140),
    }
    local news_section, news_height
    news_card, news_height, news_section = collapsible_card("news", "NEWS", news_ui.body)
    news_section.on_toggle = function(collapsed) if collapsed then news_ui.hide() end end
    local default_content_sections = {
        {id = "calendar", widget = calendar_card},
        {id = "todo", widget = todo_card},
        {id = "news", widget = news_card},
        {id = "quick-launch", widget = quick_launch_card},
        {id = "system-status", widget = stats_card},
        {id = "codex", widget = codex_card},
        {id = "crypto", widget = crypto_card},
        {id = "weather", widget = weather_card},
        {id = "now-playing", widget = media_card},
        {id = "wallpaper", widget = wallpaper_card},
    }
    local content_sections, default_by_id, seen = {}, {}, {}
    for _, entry in ipairs(default_content_sections) do default_by_id[entry.id] = entry end
    local function append_ordered_section(id)
        local entry = default_by_id[id]
        if entry and enabled_ids[id] and not seen[id] then
            content_sections[#content_sections + 1] = entry
            section_order[#section_order + 1] = sections_by_id[id]
            seen[id] = true
        end
    end
    local function insert_missing_default(entry)
        if not enabled_ids[entry.id] or seen[entry.id] then return end
        local insert_at, reached_entry = nil, false
        if entry.id == "quick-launch" then
            for index, current in ipairs(content_sections) do
                if current.id == "todo" then
                    insert_at = index + 1
                    break
                end
            end
        else
            for _, default_entry in ipairs(default_content_sections) do
                if default_entry.id == entry.id then
                    reached_entry = true
                elseif reached_entry and seen[default_entry.id] then
                    for index, current in ipairs(content_sections) do
                        if current.id == default_entry.id then
                            insert_at = index
                            break
                        end
                    end
                    if insert_at then break end
                end
            end
        end
        insert_at = insert_at or (#content_sections + 1)
        table.insert(content_sections, insert_at, entry)
        table.insert(section_order, insert_at, sections_by_id[entry.id])
        seen[entry.id] = true
    end
    section_order = {}
    for _, id in ipairs(saved_order_ids) do
        -- Respect saved positions; only genuinely missing sections use defaults.
        append_ordered_section(id)
    end
    for _, entry in ipairs(default_content_sections) do insert_missing_default(entry) end
    local content = wibox.layout.fixed.vertical()
    content.spacing = 0
    for _, section in ipairs(content_sections) do content:add(section.widget) end
    scroll_ui = scroll_component.create {
        screen = s, content = content, width = sidebar_width, header = header, clock = clock_card,
        appearance = appearance, interaction = interaction, panel = function() return panel end,
        on_scroll = function(offset) s.sidebar_scroll_position = offset end,
        on_suppress = function(value) suppress_scroll_click = value end,
    }
    ui.add(scroll_ui.destroy)
    s.sidebar_components = {clock = clock_ui, calendar = calendar_ui, news = news_ui, scroll = scroll_ui}
    local scroll_view, scrollbar, sidebar_column, scrollbar_panel =
        scroll_ui.view, scroll_ui.bar, scroll_ui.widget, scroll_ui.bar_panel
    panel = wibox {
        screen = s, type = "dock", visible = false, ontop = false,
        width = sidebar_width, height = sidebar_height,
        x = s.geometry.x + s.geometry.width - sidebar_width, y = s.geometry.y + 30,
        bg = sidebar_gradient, fg = palette.text,
        border_width = 0, opacity = appearance.sidebar_opacity,
        shape = gears.shape.rectangle, restrict_workarea = false,
    }
    scroll_ui.attach(panel)
    panel:setup {
        {
            {forced_width = 2, bg = "#5ba7e8dd", widget = wibox.container.background},
            sidebar_column,
            layout = wibox.layout.fixed.horizontal,
        },
        bg = sidebar_gradient, widget = wibox.container.background,
    }
    local function refresh_content_order()
        content:reset()
        s.sidebar_content_order = {}
        for _, entry in ipairs(content_sections) do
            content:add(entry.widget)
            s.sidebar_content_order[#s.sidebar_content_order + 1] = entry.id
        end
        content:emit_signal("widget::layout_changed")
        sidebar_column:emit_signal("widget::layout_changed")
        panel:emit_signal("widget::layout_changed")
    end
    local function drag_target(y, dragged)
        local viewport_top = panel.y + header.forced_height + clock_card.forced_height
        local content_y = y - viewport_top + s.sidebar_scroll_position
        local heights, dragged_height = {}, 0
        for _, entry in ipairs(content_sections) do
            local card_height = entry.widget.forced_height
            if not card_height and scroll_ui.context then
                local _, fitted_height = wibox.widget.base.fit_widget(
                    content, scroll_ui.context, entry.widget, scroll_ui.content_width, 2^20)
                card_height = fitted_height
            end
            card_height = card_height or 0
            heights[entry.id] = card_height
            if entry.id == dragged.id then dragged_height = card_height end
        end
        local before_dragged = 0
        for _, entry in ipairs(content_sections) do
            if entry.id == dragged.id then break end
            before_dragged = before_dragged + heights[entry.id]
        end
        if content_y > before_dragged then content_y = content_y - dragged_height end
        local height, index, last = 0, 1, nil
        for _, entry in ipairs(content_sections) do
            if entry.id ~= dragged.id then
                local card_height = heights[entry.id]
                if content_y < height + card_height / 2 then return index, entry, true end
                height = height + card_height
                index, last = index + 1, entry
            end
        end
        return index, last, false
    end
    local cancel_section_drag
    local section_drag_owner = {}
    ui.add(function() if cancel_section_drag then cancel_section_drag() end end)
    begin_section_drag = function(dragged)
        if mousegrabber.isrunning() or ui.disposed then return end
        local cancelled = false
        local origin = mouse.coords()
        local dragging, last_y, edge_direction = false, origin.y, 0
        local scroll_motion = interaction.scroll_motion()
        local drop_index, target_section
        local highlighted
        local function update_highlight(y)
            local new_index, new_entry, before = drag_target(y, dragged)
            local new_target = new_entry and sections_by_id[new_entry.id] or nil
            if highlighted and highlighted ~= new_target then
                highlighted.header.border_color = "#588cd4"
                highlighted.marker.markup = string.format(
                    "<span foreground='%s' size='10pt' weight='bold'>%s</span>",
                    "#d9f7f4", highlighted.collapsed and "▸" or "▾")
                highlighted.header:emit_signal("widget::redraw_needed")
                highlighted.marker:emit_signal("widget::redraw_needed")
            end
            target_section, drop_index, highlighted = new_target, new_index, new_target
            dragged.header.border_color = "#ffffff"
            if highlighted then highlighted.header.border_color = "#b8dcff" end
            dragged.header:emit_signal("widget::redraw_needed")
            if highlighted then highlighted.header:emit_signal("widget::redraw_needed") end
            if target_section then
                local arrow = before and "↑" or "↓"
                target_section.marker.markup = string.format(
                    "<span foreground='%s' size='10pt' weight='bold'>%s</span>", "#ffffff", arrow)
                target_section.marker:emit_signal("widget::redraw_needed")
            end
        end
        local function clear_highlight()
            dragged.header.border_color = "#588cd4"
            dragged.header:emit_signal("widget::redraw_needed")
            if highlighted then
                highlighted.header.border_color = "#588cd4"
                highlighted.marker.markup = string.format(
                    "<span foreground='%s' size='10pt' weight='bold'>%s</span>",
                    "#d9f7f4", highlighted.collapsed and "▸" or "▾")
                highlighted.header:emit_signal("widget::redraw_needed")
                highlighted.marker:emit_signal("widget::redraw_needed")
            end
        end
        local auto_scroll = gears.timer {
            timeout = 0.05,
            callback = function()
                if not dragging or edge_direction == 0 then return end
                set_scroll_offset(s.sidebar_scroll_position + scroll_motion.step())
                update_highlight(last_y)
            end,
        }
        local dragged_entry
        for _, entry in ipairs(content_sections) do
            if entry.id == dragged.id then dragged_entry = entry; break end
        end
        local function finish_drag(commit)
            if auto_scroll.started then auto_scroll:stop() end
            edge_direction = 0
            scroll_motion.reset()
            dragging = false
            clear_highlight()
            if not commit or not drop_index then return end
            local reordered, others = {}, {}
            for _, entry in ipairs(content_sections) do
                if entry.id ~= dragged.id then others[#others + 1] = entry end
            end
            drop_index = math.max(1, math.min(#others + 1, drop_index))
            for index, entry in ipairs(others) do
                if index == drop_index then reordered[#reordered + 1] = dragged_entry end
                reordered[#reordered + 1] = entry
            end
            if drop_index == #others + 1 then reordered[#reordered + 1] = dragged_entry end
            local changed = false
            for index, entry in ipairs(reordered) do
                if content_sections[index].id ~= entry.id then changed = true end
            end
            if changed then
                for index, entry in ipairs(reordered) do content_sections[index] = entry end
                for index = #content_sections, #reordered + 1, -1 do content_sections[index] = nil end
                section_order = {}
                for _, entry in ipairs(content_sections) do section_order[#section_order + 1] = sections_by_id[entry.id] end
                refresh_content_order()
                save_section_state()
            end
        end
        cancel_section_drag = function()
            cancelled = true
            if auto_scroll.started then auto_scroll:stop() end
            finish_drag(false)
            interaction.stop_grab(section_drag_owner)
        end
        local started = interaction.start_grab(section_drag_owner, function(pointer)
            if cancelled or not s.valid or ui.disposed then finish_drag(false); return false end
            last_y = pointer.y
            if pointer.buttons[1] then
                if not dragging then
                    local dx, dy = pointer.x - origin.x, pointer.y - origin.y
                    if dx * dx + dy * dy >= 49 then
                        dragging = true
                        scroll_motion.reset()
                        auto_scroll:start()
                    end
                end
                if dragging then
                    local viewport_top = panel.y + header.forced_height + clock_card.forced_height
                    local viewport_bottom = viewport_top + scroll_view.forced_height
                    edge_direction = 0
                    if pointer.x >= panel.x and pointer.x <= panel.x + panel.width then
                        if pointer.y < viewport_top + 28 then edge_direction = -1
                        elseif pointer.y > viewport_bottom - 28 then edge_direction = 1 end
                    end
                    scroll_motion.set_direction(edge_direction)
                    update_highlight(pointer.y)
                end
                return true
            end
            cancel_section_drag = nil
            if auto_scroll.started then auto_scroll:stop() end
            if dragging then
                update_highlight(pointer.y)
                finish_drag(true)
            else
                dragged.toggle_action()
            end
            return false
        end, "fleur")
        if not started then cancel_section_drag() end
    end
    ui.connect(panel, "button::press", function(_, _, _, button)
        if dismiss_menu then dismiss_menu() end
        local delta = button == 4 and -32 or (button == 5 and 32 or nil)
        if delta and mouse.coords().y >= panel.y + header.forced_height then scroll_by(delta) end
    end)
    s.sidebar = panel
    news_ui.attach()
    s.sidebar_news, s.sidebar_news_card = news_ui, news_card
    s.sidebar_news_popup = news_ui.popup
    s.sidebar_news_hide = news_ui.hide
    local keyboard_targets = {}
    local function target(section,id,widget,activate,exit,key,space,resolve)
        local entries=keyboard_targets[section] or {}
        keyboard_targets[section]=entries
        entries[#entries+1]={id=section..':'..id, section=section, widget=widget,
            activate=activate, exit=exit, key=key, space=space, resolve=resolve}
    end
    for _,entry in ipairs(keyboard_launches) do
        keyboard_targets['quick-launch']=keyboard_targets['quick-launch'] or {}
        table.insert(keyboard_targets['quick-launch'],entry)
    end
    target('wallpaper','apply',preview,apply_wallpaper)
    target('wallpaper','previous',previous_wallpaper,show_previous_wallpaper)
    target('wallpaper','next',next_wallpaper,show_next_wallpaper)
    for _,entry in ipairs({{'previous',media_previous},{'toggle',media_toggle},{'next',media_next}}) do
        target('now-playing',entry[1],entry[2],entry[2]._sidebar_keyboard_action)
    end
    target('system-status','volume',volume_control,open_mixer,true,
        function(key)
            if key~='Left' and key~='Right' then return false end
            change_volume(key=='Left' and 'down' or 'up'); return true
        end,function() change_volume('mute') end)
    if weather_enabled then target('weather','refresh',weather_body,update_weather) end
    target('news','open',news_ui.open_button,news_ui.open,true)
    target('crypto','open',crypto_body,open_trezor_suite,true)
    target('codex','refresh',codex_refresh_button,refresh_codex)
    target('todo','open',todo_body,open_todo_document,true)
    target('calendar','previous',calendar_ui.previous,calendar_ui.previous._sidebar_keyboard_action)
    target('calendar','next',calendar_ui.next,calendar_ui.next._sidebar_keyboard_action)
    target('calendar','grid',calendar_ui.grid,function()
        calendar_ui.keyboard_key('Current'); open_calendar_document()
    end,true,calendar_ui.keyboard_key,nil,calendar_ui.keyboard_cell)
    target('calendar','open',calendar_ui.events,open_calendar_document,true,nil,nil,
        function() return calendar_ui.events:get_children()[1] end)
    keyboard_view.create {
        screen=s,panel=panel,ui=ui,scroll=scroll_ui,
        targets=function()
            local result={{id='clock',widget=clock_card,activate=clock_ui.toggle}}
            for _,section in ipairs(section_order) do
                result[#result+1]={id=section.id..':header',section=section.id,widget=section.header,
                    activate=section.toggle_action,key=function(key)
                        if key~='Left' and key~='Right' then return false end
                        if section.collapsed~=(key=='Left') then section.toggle_action() end
                        return true
                    end}
                if section.id=='system-status' then
                    result[#result+1]={id='system-status:trash',section='system-status',widget=trash_status,activate=open_trash,exit=true}
                end
                if not section.collapsed then
                    for _,entry in ipairs(keyboard_targets[section.id] or {}) do result[#result+1]=entry end
                end
            end
            return result
        end,
    }
    s.sidebar_scroll_view, s.sidebar_scrollbar = scroll_view, scrollbar
    s.sidebar_scrollbar_panel = scrollbar_panel
    s.sidebar_scroll_by = scroll_by
    s.sidebar_scroll_offset = function() return s.sidebar_scroll_position end
    s.sidebar_scroll_max = scroll_ui.max
    s.sidebar_header = header
    s.sidebar_content_order = {}
    for _, section in ipairs(content_sections) do
        s.sidebar_content_order[#s.sidebar_content_order + 1] = section.id
    end
    s.sidebar_mode = 0
    s.sidebar_clock, s.sidebar_digital_time, s.sidebar_date = clock, digital_time, date
    s.sidebar_clock_card = clock_card
    s.sidebar_cpu, s.sidebar_battery = cpu_text, battery_text
    s.sidebar_mouse_battery, s.sidebar_mouse_battery_bar = mouse_battery_text, mouse_battery_bar
    s.sidebar_stats_card = stats_card
    s.sidebar_progress_bars = {cpu_bar, memory_bar, battery_bar, mouse_battery_bar, root_bar, volume_bar, codex_5h.bar, codex_7d.bar}
    s.sidebar_volume, s.sidebar_volume_text = volume_control, volume_text
    s.sidebar_trash_icon, s.sidebar_trash_state = trash_icon, trash_state
    s.sidebar_trash_status, s.sidebar_trash_refresh = trash_status, refresh_trash_status
    s.sidebar_todo_entries, s.sidebar_todo_card = todo_entries, todo_card
    s.sidebar_todo_open = open_todo_document
    s.sidebar_calendar_card = calendar_card
    s.sidebar_calendar_open = open_calendar_document
    s.sidebar_crypto_card, s.sidebar_crypto_prices = crypto_card, crypto_prices
    s.sidebar_crypto_refresh = refresh_crypto
    s.sidebar_codex_card, s.sidebar_codex_5h, s.sidebar_codex_7d = codex_card, codex_5h, codex_7d
    s.sidebar_codex_resets = codex_resets
    s.sidebar_codex_refresh = refresh_codex
    s.sidebar_codex_refresh_button = codex_refresh_button
    s.sidebar_media_text = media_text
    s.sidebar_media_buttons = {previous = media_previous, toggle = media_toggle, next = media_next}
    s.sidebar_root_text = root_text
    s.sidebar_weather_text = weather_main
    s.sidebar_wallpaper_preview, s.sidebar_wallpaper_name = preview, wallpaper_name
    s.sidebar_wallpaper_controls = wallpaper_controls
    s.sidebar_wallpaper_previous, s.sidebar_wallpaper_next = previous_wallpaper, next_wallpaper
    s.sidebar_wallpaper_previous_action, s.sidebar_wallpaper_next_action =
        show_previous_wallpaper, show_next_wallpaper
    s.sidebar_wallpaper_apply = apply_wallpaper
    s.sidebar_wallpaper_count = #wallpapers
    ui.connect(s, "property::geometry", function()
        if not s.valid then return end
        panel.x = s.geometry.x + s.geometry.width - sidebar_width
        panel.y = s.geometry.y + 30
        panel.height = math.max(1, s.geometry.height - 30)
        sidebar_column:emit_signal("widget::layout_changed")
    end)

    local previous_total, previous_idle, previous_rx, previous_tx, previous_net_time
    local function update_network(snapshot)
        local rx, tx = snapshot and snapshot.rx, snapshot and snapshot.tx
        if not rx or not tx then return end
        local now = interaction.monotonic_time()
        if previous_rx and previous_tx and previous_net_time and now > previous_net_time then
            set_text(network_text, string.format("↓ %s   ↑ %s",
                rate(math.max(0, rx - previous_rx) / (now - previous_net_time)),
                rate(math.max(0, tx - previous_tx) / (now - previous_net_time))))
        else
            set_text(network_text, "↓ ?   ↑ ?")
        end
        previous_rx, previous_tx, previous_net_time = rx, tx, now
    end
    local function update_stats(state)
        local snapshot = state.value
        if not snapshot then return end
        local stat = snapshot.stat
        local first_line = stat and stat:match("^([^\n]+)")
        if first_line then
            local values = {}
            for value in first_line:gmatch("%d+") do values[#values + 1] = tonumber(value) end
            local total = 0
            for i = 1, math.min(8, #values) do total = total + values[i] end
            local idle = (values[4] or 0) + (values[5] or 0)
            if previous_total and total > previous_total then
                local usage = math.max(0, math.min(100,
                    100 * (1 - (idle - previous_idle) / (total - previous_total))))
                set_text(cpu_text, string.format("CPU  %.0f%%", usage))
                set_value(cpu_bar, math.floor(usage + 0.5))
            end
            previous_total, previous_idle = total, idle
        end

        local mem_total = tonumber(snapshot.meminfo:match("MemTotal:%s+(%d+)"))
        local mem_available = tonumber(snapshot.meminfo:match("MemAvailable:%s+(%d+)"))
        if mem_total and mem_available and mem_total > 0 then
            local used = mem_total - mem_available
            set_text(memory_text, string.format("Memory  %.1f / %.1f GiB", used / 1048576, mem_total / 1048576))
            set_value(memory_bar, math.floor(used * 100 / mem_total + 0.5))
        end

        update_network(snapshot)
    end

    local function update_power(state)
        local snapshot = state.value
        if not snapshot then return end
        local root_total, root_free = snapshot.root_total, snapshot.root_free
        if root_total and root_total > 0 and root_free then
            set_cached(root_bar, "color", appearance.remaining_color(root_free * 100 / root_total, 10, 5))
            set_text(root_text, string.format("Free /  %.1f GiB", root_free / 1073741824))
            set_value(root_bar, math.floor((root_total - root_free) * 100 / root_total + 0.5))
        end

        local capacity, battery_state, mouse_capacity, mouse_state = snapshot.capacity,
            snapshot.battery_state, snapshot.mouse_capacity, snapshot.mouse_state
        local battery_layout_changed = set_visible(battery_text, capacity ~= nil)
        battery_layout_changed = set_visible(battery_bar, capacity ~= nil) or battery_layout_changed
        if capacity then
            set_text(battery_text, string.format("Battery  %d%%  %s", capacity, battery_state))
            set_value(battery_bar, capacity)
            set_cached(battery_bar, "color", appearance.remaining_color(capacity))
        end
        battery_layout_changed = set_visible(mouse_battery_text, mouse_capacity ~= nil) or battery_layout_changed
        battery_layout_changed = set_visible(mouse_battery_bar, mouse_capacity ~= nil) or battery_layout_changed
        if mouse_capacity then
            set_text(mouse_battery_text, string.format("Mouse  %d%%  %s", mouse_capacity, mouse_state or "Unknown"))
            set_value(mouse_battery_bar, mouse_capacity)
            set_cached(mouse_battery_bar, "color", appearance.remaining_color(mouse_capacity))
        end
        if battery_layout_changed then stats_card:emit_signal("widget::layout_changed") end
    end

    local refresh_ui = refresh_component.new {
        timer = gears.timer, delay = 0.05,
        update_stats = update_stats,
        update_power = update_power,
        update_clock = function(timestamp) clock_ui.tick(timestamp) end,
    }
    ui.add(refresh_ui.destroy)

    local function bind(name, render, body)
        local mark, tooltip
        if body then mark, tooltip = freshness(name, body) end
        local handle = data.subscribe(name, function(state)
            render(state)
            if mark then mark(state) end
        end)
        handle.tooltip = tooltip -- retain tooltip for the lifetime of this subscriber
        s["sidebar_" .. name .. "_timer"] = handle
    end
    bind("clock", function(state)
        if state.value then refresh_ui.clock(state.value) end
    end)
    bind("stats", refresh_ui.stats)
    bind("power", refresh_ui.power)
    bind("volume", render_volume)
    bind("media", function(state)
        set_text(media_text, state.value and state.value ~= "" and state.value or "Nothing playing")
    end)
    bind("trash", render_trash)
    s.sidebar_data = data -- inspectable session state for diagnostics and isolated tests
    s.sidebar_todo_refresh = refresh_todo
    s.sidebar_todo_timer = gears.timer {
        timeout = 60, autostart = true, call_now = false, callback = refresh_todo,
    }
    s.sidebar_calendar_refresh = refresh_calendar
    s.sidebar_calendar_timer = gears.timer {
        timeout = 60, autostart = true, call_now = false, callback = refresh_calendar,
    }
    bind("crypto", render_crypto, crypto_body)
    bind("codex", render_codex, codex_body)
    bind("news", news_ui.render)
    if weather_enabled then
        bind("weather", render_weather, weather_body)
    else
        weather_main.text = "Weather disabled in test"
    end
    ui.connect(s, "removed", function()
        ui.destroy()
        s.sidebar_clock_timer:stop()
        s.sidebar_stats_timer:stop()
        s.sidebar_power_timer:stop()
        s.sidebar_volume_timer:stop()
        s.sidebar_media_timer:stop()
        s.sidebar_trash_timer:stop()
        s.sidebar_todo_timer:stop()
        s.sidebar_calendar_timer:stop()
        s.sidebar_news_timer:stop()
        s.sidebar_crypto_timer:stop()
        s.sidebar_codex_timer:stop()
        if s.sidebar_weather_timer then s.sidebar_weather_timer:stop() end
        for _, name in ipairs({"crypto", "codex", "weather"}) do
            local handle = s["sidebar_" .. name .. "_timer"]
            if handle and handle.tooltip then
                handle.tooltip.visible = false
                handle.tooltip:remove_from_object(
                    name == "crypto" and crypto_body or (name == "codex" and codex_body or weather_body))
            end
        end
        panel.visible = false
    end)
end

return sidebar
