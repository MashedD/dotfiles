-- Longhorn-inspired gadget rail; resource, media, and volume tools live here.
local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local beautiful = require("beautiful")
local Gio = require("lgi").Gio
local cairo = require("lgi").cairo
local gstring = require("gears.string")
local sidebar = {}

local palette = {
    bg = "#07110d", card = "#101a15", line = "#29434a",
    bevel_light = "#4c7180", bevel_shadow = "#050b07",
    text = "#c7d5cb", muted = "#819289", teal = "#70c5bd",
    green = "#70c98b", neon = "#00ff41", amber = "#d6bd72",
}

local sidebar_gradient = gears.color {
    type = "linear", from = {0, 0}, to = {300, 0},
    stops = {{0, "#09150f"}, {0.38, "#14271b"}, {0.78, "#1b3022"}, {1, "#0a1710"}},
}
local card_gradient = gears.color {
    type = "linear", from = {0, 0}, to = {0, 180},
    stops = {{0, "#1b302e"}, {0.16, "#172a28"}, {0.58, "#12231e"}, {1, "#0d1915"}},
}
local sidebar_title_gradient = gears.color {
    type = "linear", from = {0, 0}, to = {0, 30},
    stops = {{0, "#a5ecf4"}, {0.16, "#55b1d6"}, {0.48, "#2b88b8"}, {0.76, "#1d638f"}, {1, "#123f5e"}},
}
local section_header_gradient = gears.color {
    type = "linear", from = {0, 0}, to = {0, 24},
    stops = {{0, "#70b9c9"}, {0.16, "#478da6"}, {0.5, "#2c6986"}, {1, "#173d57"}},
}
local button_gradient = gears.color {
    type = "linear", from = {0, 0}, to = {0, 30},
    stops = {{0, "#263a2c"}, {0.5, "#1a2a1f"}, {1, "#0d1811"}},
}
local button_hover_gradient = gears.color {
    type = "linear", from = {0, 0}, to = {0, 30},
    stops = {{0, "#3b6246"}, {0.5, "#294432"}, {1, "#17291d"}},
}
local button_pressed_gradient = gears.color {
    type = "linear", from = {0, 0}, to = {0, 30},
    stops = {{0, "#0a140d"}, {0.5, "#17271c"}, {1, "#233a2a"}},
}

local function read(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local value = file:read("*a")
    file:close()
    return value
end

local function open_document(filename)
    return io.open((os.getenv("HOME") or "") .. "/Documents/" .. filename, "r")
end

local function read_sidebar_todo()
    local file = open_document("todo.md")
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

local function read_calendar_entries(include_all)
    local file = open_document("calendar.md")
    if not file then return {} end
    local today = os.date("%Y-%m-%d")
    local entries, all_entries, previous, current, future = {}, {}, {}, {}, {}

    for line in file:lines() do
        local year, month, day, description = line:match("^%s*(%d%d%d%d)%-(%d%d)%-(%d%d)%s+(.+)%s*$")
        if year then
            year, month, day = tonumber(year), tonumber(month), tonumber(day)
            if day > 0 and month > 0 and month <= 12 then
                local timestamp = os.time({year = year, month = month, day = day, hour = 12})
                if os.date("%Y-%m-%d", timestamp) == string.format("%04d-%02d-%02d", year, month, day) then
                    local range_start, range_end = description:find("%d%d:%d%d%s*%-%s*%d%d:%d%d")
                    local time_start, time_end
                    if range_start then
                        time_start, time_end = range_start, range_end
                    else
                        time_start, time_end = description:find("%d%d:%d%d")
                    end
                    local time_text = time_start and description:sub(time_start, time_end):gsub("%s+", "") or nil
                    local event_text = description
                    if time_start then
                        event_text = description:sub(1, time_start - 1) .. description:sub(time_end + 1)
                        event_text = event_text:gsub(":%s*,", ":", 1):gsub("^%s*[,;:]%s*", "")
                    end
                    event_text = event_text:gsub("%s+", " "):gsub("^%s+", "")
                        :gsub("^%s*[,;:]%s*", ""):gsub("%s*[,;:]%s*$", "")
                    local entry = {
                        date = string.format("%04d-%02d-%02d", year, month, day),
                        timestamp = timestamp, time = time_text, text = event_text,
                    }
                    all_entries[#all_entries + 1] = entry
                    if entry.date < today then
                        entry.day = "past"
                        previous[#previous + 1] = entry
                    elseif entry.date == today then
                        entry.day = "today"
                        current[#current + 1] = entry
                    elseif entry.date > today then
                        entry.day = "future"
                        future[#future + 1] = entry
                    end
                end
            end
        end
    end
    file:close()

    local function sort_entries(a, b)
        if a.date ~= b.date then return a.date < b.date end
        return (a.time or "") < (b.time or "")
    end
    table.sort(all_entries, sort_entries)
    if include_all then return all_entries end
    table.sort(previous, sort_entries)
    table.sort(current, sort_entries)
    table.sort(future, sort_entries)
    if #previous > 0 then entries[#entries + 1] = previous[#previous] end
    for _, entry in ipairs(current) do entries[#entries + 1] = entry end
    for i = 1, math.min(3, #future) do entries[#entries + 1] = future[i] end
    return entries
end

local function label(text, color, size, bold, align)
    return wibox.widget {
        markup = string.format("<span foreground='%s' size='%dpt'%s>%s</span>",
            color, size, bold and " weight='bold'" or "", text),
        align = align or "left", valign = "center", widget = wibox.widget.textbox,
    }
end

local function section_header(text, trailing_widget)
    local title = label(text, "#edfaff", 10, true, "center")
    local marker = label("−", "#d9f7f4", 10, true, "center")
    marker.forced_width = 18
    local contents = wibox.layout.stack()
    local adornments = wibox.layout.align.horizontal()
    adornments:set_left(marker)
    if trailing_widget then adornments:set_right(trailing_widget) end
    contents:add(adornments)
    contents:add(wibox.widget {
        title, halign = "center", valign = "center", widget = wibox.container.place,
    })
    local header = wibox.widget {
        {
            {forced_height = 1, bg = "#a5ecf4", widget = wibox.container.background},
            {
                {contents, left = 2, right = 2, top = 1, bottom = 1,
                    widget = wibox.container.margin},
                forced_height = 20, bg = section_header_gradient,
                widget = wibox.container.background,
            },
            {forced_height = 1, bg = "#12364d", widget = wibox.container.background},
            layout = wibox.layout.fixed.vertical,
        },
        forced_height = 24, bg = section_header_gradient,
        border_width = 1, border_color = "#5b9bad",
        widget = wibox.container.background,
    }
    return header, title, marker
end

local function make_trash_icon()
    local icon = wibox.widget.base.make_widget()
    icon.forced_width, icon.forced_height = 16, 18
    icon.fit = function() return 16, 18 end
    icon.full = false
    icon.draw = function(_, _, cr)
        local red, green, blue = icon.full and 0.44 or 0.57,
            icon.full and 0.79 or 0.72, icon.full and 0.55 or 0.75
        cr:set_source_rgb(red, green, blue)
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

local function make_analog_clock()
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

local section_padding, section_vertical_padding = 6, 8
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

local progress_bar_height = 7
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

local function battery_stats()
    local root = "/sys/class/power_supply/"
    local enumerator = Gio.File.new_for_path(root):enumerate_children("standard::name", 0)
    if not enumerator then return nil, nil, nil, nil end
    local capacities, states = {}, {}
    local mouse_capacity, mouse_state
    while true do
        local entry = enumerator:next_file()
        if not entry then break end
        local name = entry:get_name()
        local supply_type = read(root .. name .. "/type") or ""
        if name:match("^BAT") and supply_type:match("^Battery") then
            local capacity = tonumber(read(root .. name .. "/capacity"))
            if capacity then
                capacities[#capacities + 1] = capacity
                states[#states + 1] = (read(root .. name .. "/status") or "Unknown"):gsub("%s+$", "")
            end
        elseif name:match("^hidpp_battery") and supply_type:match("^Battery") and not mouse_capacity then
            mouse_capacity = tonumber(read(root .. name .. "/capacity"))
            mouse_state = (read(root .. name .. "/status") or "Unknown"):gsub("%s+$", "")
        end
    end
    enumerator:close()
    local laptop_capacity, laptop_state
    if #capacities > 0 then
        local sum = 0
        for _, capacity in ipairs(capacities) do sum = sum + capacity end
        laptop_capacity, laptop_state = math.floor(sum / #capacities + 0.5), table.concat(states, ", ")
    end
    return laptop_capacity, laptop_state, mouse_capacity, mouse_state
end

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

local function wallpaper_paths()
    local home = os.getenv("HOME") or "."
    local roots = {
        (os.getenv("XDG_DATA_HOME") or (home .. "/.local/share")) .. "/wallpapers",
        home .. "/Pictures/Wallpapers",
    }
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

local function launcher(text, command, dismiss_menu, accent)
    local button = style_button(wibox.widget {
        label(text, accent or palette.teal, 10, true, "center"),
        forced_width = 112, forced_height = 34,
        bg = button_gradient, border_width = 1, border_color = accent or palette.bevel_light,
        widget = wibox.container.background,
    }, dismiss_menu)
    button:buttons(gears.table.join(awful.button({}, 1, function() awful.spawn(command) end)))
    return button
end

local function action_button(text, callback, dismiss_menu)
    local button = style_button(wibox.widget {
        {label(text, palette.teal, 14, true, "center"),
            halign = "center", valign = "center", widget = wibox.container.place},
        forced_width = 46, forced_height = 28,
        bg = button_gradient, border_width = 1, border_color = palette.bevel_light,
        widget = wibox.container.background,
    }, dismiss_menu)
    button:buttons(gears.table.join(awful.button({}, 1, callback)))
    return button
end

function sidebar.create(s, dismiss_menu)
    local sidebar_width = 300
    local state_root = os.getenv("XDG_STATE_HOME")
        or ((os.getenv("HOME") or ".") .. "/.local/state")
    local section_state_path = state_root .. "/awesome/sidebar-sections"
    local collapsed_ids = {}
    local saved_sections = read(section_state_path) or ""
    for id in saved_sections:gmatch("[^\r\n]+") do
        id = id:gsub("^%s+", ""):gsub("%s+$", "")
        if id:match("^[%w-]+$") then collapsed_ids[id] = true end
    end
    local section_order, sections_by_id = {}, {}
    local function save_section_state()
        local directory = section_state_path:match("^(.*)/")
        if not directory or not pcall(gears.filesystem.make_directories, directory) then return end
        local temporary = section_state_path .. ".tmp"
        local file = io.open(temporary, "w")
        if not file then return end
        for _, section in ipairs(section_order) do
            if section.collapsed then file:write(section.id, "\n") end
        end
        file:close()
        if not os.rename(temporary, section_state_path) then os.remove(temporary) end
    end
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
            if dismiss_menu then dismiss_menu() end
        end
        title:buttons(gears.table.join(awful.button({}, 1, toggle)))
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

    local clock = make_analog_clock()
    local digital_time = label("00:00:00", palette.neon, 24, true, "center")
    local date = label("", palette.teal, 12, true, "center")
    local cpu_text = label("CPU  measuring…", palette.text, 10, false)
    local memory_text = label("Memory  reading…", palette.text, 10, false)
    local battery_text = label("Battery  --", palette.text, 10, false)
    local mouse_battery_text = label("Mouse  --", palette.text, 10, false)
    mouse_battery_text.visible = false
    local root_text = label("Free /  reading…", palette.text, 10, false)
    local network_text = label("Network  measuring…", palette.text, 10, false)
    local cpu_bar, memory_bar = progress(palette.neon), progress(palette.green)
    local battery_bar, root_bar = progress(palette.amber), progress(palette.teal)
    local mouse_battery_bar = progress(palette.teal)
    mouse_battery_bar.visible = false
    local volume_text = label("Volume  --", palette.text, 10, false)
    local volume_bar = progress(palette.teal)
    local media_text = label("Checking player…", palette.text, 11, false, "center")
    media_text.wrap = "word_char"
    media_text.ellipsize = "end"

    local header_title = label("MashedD's AwesomeBar", "#f2fffb", 9, true)
    header_title.font = "Segoe UI bold 9"
    local header = wibox.widget {
        {
            {forced_height = 1, bg = "#c5f7fb", widget = wibox.container.background},
            {
                {header_title, left = 10, right = 6, widget = wibox.container.margin},
                forced_height = 23, bg = sidebar_title_gradient,
                widget = wibox.container.background,
            },
            {forced_height = 1, bg = "#123f5e", widget = wibox.container.background},
            layout = wibox.layout.fixed.vertical,
        },
        forced_height = 26, bg = sidebar_title_gradient,
        border_width = 1, border_color = "#6bb5ca",
        widget = wibox.container.background,
    }
    local clock_centered = wibox.widget {
        clock, halign = "center", valign = "center", widget = wibox.container.place,
    }
    local clock_content = wibox.layout.fixed.vertical()
    clock_content.spacing = 3
    clock_content:add(date)
    clock_content:add(clock_centered)
    clock_content:add(digital_time)
    digital_time.visible = false
    local clock_card = card(clock_content, 142)
    local clock_mode = "analog"
    local function set_clock_mode(mode)
        clock_mode = mode
        clock.visible = mode == "analog"
        clock_centered.visible = mode == "analog"
        digital_time.visible = mode == "text"
        clock_card.forced_height = mode == "analog" and 142 or 66
        s.sidebar_clock_mode = mode
    end
    local function toggle_clock_mode()
        set_clock_mode(clock_mode == "analog" and "text" or "analog")
    end
    local function bind_clock_toggle(widget)
        widget:buttons(gears.table.join(awful.button({}, 1, toggle_clock_mode)))
        if dismiss_menu then widget:connect_signal("button::press", dismiss_menu) end
    end
    bind_clock_toggle(clock)
    bind_clock_toggle(digital_time)
    local date_calendar
    s.sidebar_clock_toggle = toggle_clock_mode
    set_clock_mode("analog")

    local wallpapers = wallpaper_paths()
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
    local function small_button(text, callback)
        local button = style_button(wibox.widget {
            label(text, palette.muted, 11, true, "center"),
            forced_width = 26, forced_height = 20,
            bg = button_gradient, border_width = 1, border_color = palette.bevel_light,
            widget = wibox.container.background,
        }, dismiss_menu)
        button:buttons(gears.table.join(awful.button({}, 1, callback)))
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
    local previous_wallpaper = small_button("‹", show_previous_wallpaper)
    local next_wallpaper = small_button("›", show_next_wallpaper)
    local wallpaper_controls = wibox.widget {
        previous_wallpaper, wallpaper_name, next_wallpaper,
        spacing = 8, layout = wibox.layout.fixed.horizontal,
    }
    update_wallpaper_preview()
    preview:buttons(gears.table.join(awful.button({}, 1, apply_wallpaper)))
    if dismiss_menu then preview:connect_signal("button::press", dismiss_menu) end
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
    local weather_detail = label("Bydgoszcz, Poland", palette.muted, 10, false, "center")
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
    local weather_pending = false
    local weather_url = "https://api.open-meteo.com/v1/forecast?latitude=53.1235&longitude=17.9871"
        .. "&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m&timezone=Europe%2FWarsaw"
    local function set_weather_icon(icon)
        weather_icon.markup = string.format("<span foreground='%s' size='22pt'>%s</span>", palette.teal, icon)
    end
    local function update_weather()
        if weather_pending then return end
        weather_pending = true
        awful.spawn.easy_async({"curl", "--fail", "--silent", "--show-error", "--max-time", "12", weather_url},
            function(stdout, _, _, code)
                weather_pending = false
                local current = code == 0 and stdout:match('"current"%s*:%s*{([^}]+)}') or nil
                local function field(name)
                    return current and tonumber(current:match('"' .. name .. '"%s*:%s*([%-0-9.]+)')) or nil
                end
                local temperature, apparent = field("temperature_2m"), field("apparent_temperature")
                local condition, wind = field("weather_code"), field("wind_speed_10m")
                if not temperature then
                    set_weather_icon("·")
                    weather_main.text = "Weather unavailable"
                    weather_detail.text = "Click to try again"
                    return
                end
                set_weather_icon(weather_icon_for(condition))
                weather_main.text = string.format("%.0f°C  •  %s", temperature, weather_description(condition))
                weather_detail.text = string.format("Feels %.0f°C  •  Wind %.0f km/h", apparent or temperature, wind or 0)
            end)
    end
    local weather_body = wibox.widget {
        {weather_line, halign = "center", valign = "center", widget = wibox.container.place},
        spacing = 3, layout = wibox.layout.fixed.vertical,
    }
    local weather_card = collapsible_card("weather", "BYDGOSZCZ · WEATHER", weather_body)

    local crypto_prices = {}
    local function crypto_cell(symbol)
        local entry = {text = "--"}
        local row = wibox.widget.textbox()
        local function update()
            row.markup = string.format(
                "<span foreground='%s' size='9pt' weight='bold'>%s</span> " ..
                    "<span foreground='%s' size='9pt' weight='bold'>%s</span>",
                palette.teal, symbol, palette.green, entry.text)
        end
        entry.set = function(value)
            entry.text = value
            update()
        end
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
    local crypto_pending = false
    local function refresh_crypto()
        if crypto_pending then return end
        crypto_pending = true
        awful.spawn.easy_async({os.getenv("HOME") .. "/.local/bin/crypto-prices"}, function(stdout, _, _, code)
            crypto_pending = false
            local display = code == 0 and stdout:gsub("#%b[]", ""):gsub("%s+$", "") or ""
            local btc, eth, ltc = display:match("BTC%s+(%S+)%s+ETH%s+(%S+)%s+LTC%s+(%S+)")
            crypto_prices.BTC.set((btc or "--"):gsub("^%$", ""))
            crypto_prices.ETH.set((eth or "--"):gsub("^%$", ""))
            crypto_prices.LTC.set((ltc or "--"):gsub("^%$", ""))
        end)
    end

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
    local stats_card = collapsible_card("system-status", "SYSTEM STATUS", stats_body)

    local function codex_window_row(period)
        local summary = label(period .. " unavailable", palette.muted, 8, false)
        local bar = progress(palette.green)
        bar.forced_height = progress_bar_height
        return wibox.widget {
            {summary, bar, spacing = compact_spacing, layout = wibox.layout.fixed.vertical},
            layout = wibox.layout.fixed.vertical,
        }, {summary = summary, bar = bar, remaining = nil}
    end
    local codex_5h_widget, codex_5h = codex_window_row("5h")
    local codex_7d_widget, codex_7d = codex_window_row("7d")
    local codex_resets = label("--", palette.teal, 8, false)
    codex_resets.wrap = "word_char"
    local codex_body = wibox.widget {
        codex_5h_widget, codex_7d_widget, codex_resets,
        spacing = compact_spacing, layout = wibox.layout.fixed.vertical,
    }
    local codex_card = collapsible_card("codex", "CODEX", codex_body)
    local codex_pending = false
    local function refresh_codex()
        if codex_pending then return end
        codex_pending = true
        awful.spawn.easy_async({os.getenv("HOME") .. "/.local/bin/codex-usage", "--sidebar"}, function(stdout, _, _, code)
            codex_pending = false
            local report = code == 0 and stdout or ""
            local display, reset_dates = report:match("^(.-)\t([^\r\n]+)")
            display = (display or report):gsub("#%b[]", ""):gsub("^C%*?%s*", ""):gsub("%s+$", "")
            local pretty_reset_dates = reset_dates and reset_dates:gsub(" · ", "\n")
            local reset_text = pretty_reset_dates and reset_dates ~= "--"
                and pretty_reset_dates or "--"
            codex_resets.markup = string.format(
                "<span foreground='%s' size='8pt'>%s</span>", palette.teal, gstring.xml_escape(reset_text))
            local five_left, five_reset, week_left, week_reset = display:match(
                "5h%s+(%d+)%%@([%a]+%s+%d%d:%d%d)%s+7d%s+(%d+)%%@([%a]+%s+%d%d:%d%d)")
            if five_left then
                codex_5h.summary.markup = string.format(
                    "<span foreground='%s'>5h  %s%% left · %s</span>", palette.text, five_left, five_reset)
                codex_5h.remaining = tonumber(five_left) or 0
                codex_5h.bar.value = codex_5h.remaining
            else
                codex_5h.summary.text = "5h usage unavailable"
                codex_5h.remaining = nil
                codex_5h.bar.value = 0
            end
            if week_left then
                codex_7d.summary.markup = string.format(
                    "<span foreground='%s'>7d  %s%% left · %s</span>", palette.text, week_left, week_reset)
                codex_7d.remaining = tonumber(week_left) or 0
                codex_7d.bar.value = codex_7d.remaining
            else
                codex_7d.summary.text = "7d usage unavailable"
                codex_7d.remaining = nil
                codex_7d.bar.value = 0
            end
        end)
    end

    local media_controls = wibox.widget {
        action_button("«", function() awful.spawn.easy_async({"playerctl", "previous"}, function() end) end, dismiss_menu),
        action_button("▶", function() awful.spawn.easy_async({"playerctl", "play-pause"}, function() end) end, dismiss_menu),
        action_button("»", function() awful.spawn.easy_async({"playerctl", "next"}, function() end) end, dismiss_menu),
        spacing = 8, layout = wibox.layout.fixed.horizontal,
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
    local volume_pending = false
    local function update_volume()
        if volume_pending then return end
        volume_pending = true
        awful.spawn.easy_async({"wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"}, function(stdout, _, _, code)
            volume_pending = false
            local value = code == 0 and tonumber(stdout:match("Volume:%s*([%d.]+)")) or nil
            local muted = stdout:find("MUTED", 1, true) ~= nil
            volume_text.markup = string.format(
                "<span foreground='%s' size='8pt'>Volume  %s</span>",
                muted and palette.amber or palette.text,
                value and (muted and "Mute" or string.format("%.0f%%", value * 100)) or "--")
            volume_bar.value = value and math.floor(value * 100 + 0.5) or 0
        end)
    end
    local function change_volume(action)
        awful.spawn.easy_async({os.getenv("HOME") .. "/.local/bin/openbox-volume", action}, update_volume)
    end
    volume_control:buttons(gears.table.join(
        awful.button({}, 1, function() awful.spawn("pavucontrol") end),
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
            local row = label("No items in ~/Documents/todo.md · ## Sidebar", palette.muted, 9, false)
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
        awful.spawn({"xdg-open", (os.getenv("HOME") or "") .. "/Documents/todo.md"})
        if dismiss_menu then dismiss_menu() end
    end
    todo_body:buttons(gears.table.join(awful.button({}, 1, open_todo_document)))
    local todo_card = collapsible_card("todo", "TODO", todo_body)

    local function open_calendar_document()
        if suppress_scroll_click then return end
        awful.spawn({"xdg-open", (os.getenv("HOME") or "") .. "/Documents/calendar.md"})
        if dismiss_menu then dismiss_menu() end
    end
    local calendar_entries = {}
    local calendar_list = wibox.layout.fixed.vertical()
    calendar_list.spacing = list_spacing
    local function calendar_row(entry)
        local now = os.date("*t")
        local yesterday = os.date("%Y-%m-%d", os.time({year = now.year, month = now.month, day = now.day - 1, hour = 12}))
        local date_color, time_color, event_color, weight
        if entry.day == "today" then
            date_color, time_color, event_color, weight = palette.neon, "#ffe08a", "#ffffff", "bold"
        elseif entry.day == "future" then
            date_color, time_color, event_color, weight = palette.teal, palette.green, palette.text, "normal"
        else
            date_color, time_color, event_color, weight = palette.muted, palette.muted, palette.muted, "normal"
        end
        local short_date = os.date("%d.%m", entry.timestamp)
        local date_text = entry.day == "today" and ("TODAY · " .. short_date)
            or (entry.date == yesterday and ("YDAY · " .. short_date)
                or os.date("%a · %d.%m", entry.timestamp):upper())
        local date_label = label(date_text, date_color, 8, true)
        local time_label = label(entry.time or "ALL DAY", time_color, 8, false)
        local metadata = wibox.widget {
            date_label, time_label, spacing = 1,
            layout = wibox.layout.fixed.vertical,
        }
        metadata.forced_width = 82
        local event_label = wibox.widget {
            markup = string.format("<span foreground='%s' weight='%s'>%s</span>",
                event_color, weight, gstring.xml_escape(entry.text)),
            wrap = "word_char", valign = "top", widget = wibox.widget.textbox,
        }
        local content = wibox.widget {
            {
                {forced_width = 2, bg = date_color, widget = wibox.container.background},
                {
                    {metadata, event_label, spacing = 7,
                        layout = wibox.layout.fixed.horizontal},
                    left = 6, right = 5, top = 4, bottom = 4,
                    widget = wibox.container.margin,
                },
                layout = wibox.layout.fixed.horizontal,
            },
            bg = "#0c1b15", border_width = 1, border_color = "#254238",
            widget = wibox.container.background,
        }
        content:connect_signal("mouse::enter", function() content.bg = "#152b21" end)
        content:connect_signal("mouse::leave", function() content.bg = "#0c1b15" end)
        content:buttons(gears.table.join(awful.button({}, 1, open_calendar_document)))
        return content
    end
    local function refresh_calendar()
        calendar_list:reset()
        calendar_entries = read_calendar_entries()
        if #calendar_entries == 0 then
            calendar_list:add(label("No nearby events", palette.muted, 9, false))
        else
            for _, entry in ipairs(calendar_entries) do calendar_list:add(calendar_row(entry)) end
        end
        s.sidebar_calendar_entries = calendar_entries
    end
    refresh_calendar()
    local calendar_body = wibox.widget {
        calendar_list, spacing = 5, layout = wibox.layout.fixed.vertical,
    }
    local calendar_card = collapsible_card("calendar", "CALENDAR", calendar_body)

    local calendar_path = (os.getenv("HOME") or "") .. "/Documents/calendar.md"
    local calendar_view_month = os.time({year = tonumber(os.date("%Y")), month = tonumber(os.date("%m")), day = 1, hour = 12})
    local calendar_selected_date = os.date("%Y-%m-%d")
    local calendar_selected_event
    local render_calendar_popup
    local calendar_month_title = label("", "#edfaff", 11, true, "center")
    local calendar_selected_title = label("", palette.teal, 10, true)
    local calendar_grid = wibox.layout.fixed.vertical()
    calendar_grid.spacing = 2
    local calendar_grid_centered = {
        calendar_grid, halign = "center", widget = wibox.container.place,
    }
    local calendar_events_widget = wibox.layout.fixed.vertical()
    calendar_events_widget.spacing = 3
    local function events_for_date(date_text)
        local result = {}
        local file = io.open(calendar_path, "r")
        if not file then return result end
        for line in file:lines() do
            local event_date, source = line:match("^%s*(%d%d%d%d%-%d%d%-%d%d)%s+(.+)%s*$")
            if event_date == date_text then
                result[#result + 1] = {index = #result + 1, source = source}
            end
        end
        file:close()
        return result
    end
    local function calendar_action(text, callback, width)
        local widget = wibox.widget {
            label(text, "#d7eee8", 9, true, "center"),
            forced_width = width or 75, forced_height = 28,
            bg = button_gradient, border_width = 1, border_color = palette.bevel_light,
            widget = wibox.container.background,
        }
        widget:buttons(gears.table.join(awful.button({}, 1, callback)))
        widget:connect_signal("mouse::enter", function() widget.bg = button_hover_gradient end)
        widget:connect_signal("mouse::leave", function() widget.bg = button_gradient end)
        return widget
    end
    local calendar_previous = calendar_action("◀", function()
        local current = os.date("*t", calendar_view_month)
        calendar_view_month = os.time({year = current.year, month = current.month - 1, day = 1, hour = 12})
        calendar_selected_date = os.date("%Y-%m-%d", calendar_view_month)
        calendar_selected_event = nil
        render_calendar_popup()
    end, 34)
    local calendar_next = calendar_action("▶", function()
        local current = os.date("*t", calendar_view_month)
        calendar_view_month = os.time({year = current.year, month = current.month + 1, day = 1, hour = 12})
        calendar_selected_date = os.date("%Y-%m-%d", calendar_view_month)
        calendar_selected_event = nil
        render_calendar_popup()
    end, 34)
    local calendar_popup = wibox {
        screen = s, type = "utility", visible = false, ontop = true,
        width = 340, height = 430, bg = "#0b1712", fg = palette.text,
        border_width = 1, border_color = "#70c5bd",
        x = math.max(s.geometry.x + 8, s.geometry.x + s.geometry.width - sidebar_width - 372),
        y = s.geometry.y + 34,
    }
    date_calendar = calendar_popup
    date_calendar.start_sunday = false
    render_calendar_popup = function()
        local view = os.date("*t", calendar_view_month)
        calendar_month_title.text = os.date("%B %Y", calendar_view_month)
        calendar_selected_title.text = os.date("%A · %d %B %Y", os.time({
            year = tonumber(calendar_selected_date:sub(1, 4)),
            month = tonumber(calendar_selected_date:sub(6, 7)),
            day = tonumber(calendar_selected_date:sub(9, 10)), hour = 12,
        }))

        local by_date = {}
        for _, event in ipairs(read_calendar_entries(true)) do
            by_date[event.date] = (by_date[event.date] or 0) + 1
        end
        calendar_grid:reset()
        local weekday_names = {"M", "T", "W", "T", "F", "S", "S"}
        local weekday_row = wibox.layout.fixed.horizontal()
        weekday_row.spacing = 2
        for _, name in ipairs(weekday_names) do
            weekday_row:add(wibox.widget {
                label(name, palette.muted, 8, true, "center"),
                forced_width = 42, forced_height = 18, widget = wibox.container.background,
            })
        end
        calendar_grid:add(weekday_row)
        local first_weekday = (os.date("*t", calendar_view_month).wday + 5) % 7
        local days_in_month = tonumber(os.date("%d", os.time({year = view.year, month = view.month + 1, day = 0, hour = 12})))
        local weeks = math.ceil((first_weekday + days_in_month) / 7)
        local day = 1
        for week = 1, weeks do
            local row = wibox.layout.fixed.horizontal()
            row.spacing = 2
            for column = 1, 7 do
                local index = (week - 1) * 7 + column - 1
                if index < first_weekday or day > days_in_month then
                    row:add(wibox.widget {forced_width = 42, forced_height = 30, widget = wibox.container.background})
                else
                    local day_number = day
                    local day_date = string.format("%04d-%02d-%02d", view.year, view.month, day_number)
                    local is_selected = day_date == calendar_selected_date
                    local has_events = by_date[day_date] ~= nil
                    local day_color = day_date == os.date("%Y-%m-%d") and palette.neon
                        or (has_events and palette.teal or palette.text)
                    local cell = wibox.widget {
                        label(tostring(day_number), day_color, 9, is_selected or has_events, "center"),
                        forced_width = 42, forced_height = 30,
                        bg = is_selected and "#1d5944" or (has_events and "#10291f" or "#0e1d17"),
                        border_width = is_selected and 1 or 0,
                        border_color = palette.neon, widget = wibox.container.background,
                    }
                    cell:buttons(gears.table.join(awful.button({}, 1, function()
                        calendar_selected_date = day_date
                        calendar_selected_event = nil
                        render_calendar_popup()
                    end)))
                    row:add(cell)
                    day = day + 1
                end
            end
            calendar_grid:add(row)
        end

        calendar_events_widget:reset()
        local events = events_for_date(calendar_selected_date)
        if #events == 0 then
            calendar_events_widget:add(label("No events for this date", palette.muted, 9, false))
            calendar_selected_event = nil
        else
            if not calendar_selected_event then calendar_selected_event = events[1].index end
            local selected_exists = false
            for _, event in ipairs(events) do
                local chosen = event.index == calendar_selected_event
                if chosen then selected_exists = true end
                local event_text = wibox.widget {
                    markup = string.format("<span foreground='%s' weight='%s'>%s</span>",
                        chosen and "#ffffff" or palette.text, chosen and "bold" or "normal",
                        gstring.xml_escape(event.source)),
                    wrap = "word_char", valign = "top", widget = wibox.widget.textbox,
                }
                local event_row = wibox.widget {
                    {event_text, left = 5, right = 5, top = 3, bottom = 3,
                        widget = wibox.container.margin},
                    bg = chosen and "#173b2b" or "#0d1b15",
                    border_width = chosen and 1 or 0, border_color = palette.teal,
                    widget = wibox.container.background,
                }
                event_row:buttons(gears.table.join(awful.button({}, 1, function()
                    calendar_selected_event = event.index
                    render_calendar_popup()
                end)))
                calendar_events_widget:add(event_row)
            end
            if not selected_exists then calendar_selected_event = events[1].index end
        end
        local _, content_height = calendar_popup.widget:fit({}, calendar_popup.width, 1000)
        calendar_popup.height = math.max(280, math.min(520, math.ceil(content_height + 60)))
    end
    local calendar_navigation = wibox.layout.align.horizontal()
    calendar_navigation:set_left(calendar_previous)
    calendar_navigation:set_middle(calendar_month_title)
    calendar_navigation:set_right(calendar_next)
    local calendar_content = {
        {
            {
                calendar_navigation,
                calendar_grid_centered,
                calendar_selected_title,
                calendar_events_widget,
                spacing = 7, layout = wibox.layout.fixed.vertical,
            },
            left = 10, right = 10, top = 8, bottom = 8,
            widget = wibox.container.margin,
        },
        bg = card_gradient, widget = wibox.container.background,
    }
    calendar_popup:setup(calendar_content)
    calendar_popup:buttons(gears.table.join(awful.button({}, 3, function()
        calendar_popup.visible = false
    end)))
    local function toggle_calendar_popup()
        if calendar_popup.visible then
            calendar_popup.visible = false
            return
        end
        local today = os.date("*t")
        calendar_view_month = os.time({year = today.year, month = today.month, day = 1, hour = 12})
        calendar_selected_date = os.date("%Y-%m-%d")
        calendar_selected_event = nil
        render_calendar_popup()
        calendar_popup.x = math.max(s.geometry.x + 8,
            s.geometry.x + s.geometry.width - sidebar_width - calendar_popup.width - 12)
        calendar_popup.y = s.geometry.y + 34
        calendar_popup.visible = true
        if dismiss_menu then dismiss_menu() end
    end
    date:buttons(gears.table.join(awful.button({}, 1, toggle_calendar_popup)))
    if dismiss_menu then date:connect_signal("button::press", dismiss_menu) end
    s.sidebar_date_calendar = date_calendar
    s.sidebar_calendar_refresh = refresh_calendar

    local trash_icon = make_trash_icon()
    local trash_state = label("UNKNOWN", palette.amber, 8, true)
    local trash_status = wibox.widget {
        trash_icon, trash_state, spacing = 3,
        layout = wibox.layout.fixed.horizontal,
    }
    local function refresh_trash_status()
        local full
        local ok, enumerator = pcall(function()
            return Gio.File.new_for_uri("trash:///"):enumerate_children("standard::name", 0)
        end)
        if ok and enumerator then
            local read_ok, child = pcall(function() return enumerator:next_file() end)
            pcall(function() enumerator:close() end)
            if read_ok then full = child ~= nil end
        end
        trash_icon.full = full == true
        trash_icon:emit_signal("widget::redraw_needed")
        local text, color = full == nil and "UNKNOWN" or (full and "FULL" or "EMPTY"),
            full == nil and palette.amber or (full and palette.green or palette.muted)
        trash_state.markup = string.format(
            "<span foreground='%s' size='8pt' weight='bold'>%s</span>", color, text)
        s.sidebar_trash_full = full
    end
    refresh_trash_status()
    trash_status:buttons(gears.table.join(awful.button({}, 1, function()
        awful.spawn({"pcmanfm", "trash:///"})
    end)))
    if dismiss_menu then trash_status:connect_signal("button::press", dismiss_menu) end

    local quake2_button = launcher("Quake 2", {os.getenv("HOME") .. "/Games/quake2/q2pro.sh"}, dismiss_menu)
    local sleep_button = launcher("Sleep", {"systemctl", "suspend"}, dismiss_menu, palette.green)
    local quick_body = wibox.widget {
        {
            {
                launcher("Terminal", {"kitty"}, dismiss_menu), launcher("Files", {"pcmanfm"}, dismiss_menu),
                spacing = 8, layout = wibox.layout.fixed.horizontal,
            }, halign = "center", widget = wibox.container.place,
        },
        {
            {
                launcher("Monitor", {"kitty", "--title", "System Monitor", "btop"}, dismiss_menu),
                launcher("Finder", {"xfce4-appfinder"}, dismiss_menu),
                spacing = 8, layout = wibox.layout.fixed.horizontal,
            }, halign = "center", widget = wibox.container.place,
        },
        {
            {quake2_button, sleep_button, spacing = 8,
                layout = wibox.layout.fixed.horizontal},
            halign = "center", widget = wibox.container.place,
        },
        spacing = 6, layout = wibox.layout.fixed.vertical,
    }
    local quick_card = collapsible_card("quick-launch", "QUICK LAUNCH", quick_body, nil, trash_status)

    local scrollbar_height = 12
    local sidebar_height = math.max(1, s.geometry.height - 30)
    local scroll_max = 0
    s.sidebar_scroll_position = 0
    local scroll_content_height, scroll_viewport_height = 1, 1
    local scroll_view, scrollbar, panel, sidebar_column, scrollbar_panel
    local function set_scroll_offset(offset)
        s.sidebar_scroll_position = math.max(0, math.min(scroll_max, offset))
        if scroll_view then
            scroll_view:emit_signal("widget::layout_changed")
            scroll_view:emit_signal("widget::redraw_needed")
        end
        if scrollbar then scrollbar:emit_signal("widget::redraw_needed") end
    end
    local function scroll_by(delta)
        set_scroll_offset(s.sidebar_scroll_position + delta)
    end
    local content_sections = {
        {id = "system-status", widget = stats_card},
        {id = "codex", widget = codex_card},
        {id = "crypto", widget = crypto_card},
        {id = "weather", widget = weather_card},
        {id = "now-playing", widget = media_card},
        {id = "todo", widget = todo_card},
        {id = "calendar", widget = calendar_card},
        {id = "quick-launch", widget = quick_card},
        {id = "wallpaper", widget = wallpaper_card},
    }
    local content = wibox.layout.fixed.vertical()
    content.spacing = 0
    for _, section in ipairs(content_sections) do content:add(section.widget) end
    scroll_view = wibox.widget.base.make_widget()
    scroll_view.fit = function(_, _, width, height)
        return width, math.min(height, scroll_view.forced_height or height)
    end
    scroll_view.draw = function() end
    scroll_view.before_draw_children = function(_, _, cr, width, height)
        cr:save()
        cr:rectangle(0, 0, width, height)
        cr:clip()
    end
    scroll_view.after_draw_children = function(_, _, cr, width, height)
        local fade_height = math.min(38, height)
        if scroll_max > s.sidebar_scroll_position + 1 then
            local gradient = cairo.LinearPattern.create(0, height - fade_height, 0, height)
            gradient:add_color_stop_rgba(0, 0, 0, 0, 0)
            gradient:add_color_stop_rgba(1, 0, 0, 0, 0.72)
            cr:set_source(gradient)
            cr:rectangle(0, height - fade_height, width, fade_height)
            cr:fill()
            gradient:destroy()
        end
        if s.sidebar_scroll_position > 1 then
            local gradient = cairo.LinearPattern.create(0, 0, 0, fade_height)
            gradient:add_color_stop_rgba(0, 0, 0, 0, 0.72)
            gradient:add_color_stop_rgba(1, 0, 0, 0, 0)
            cr:set_source(gradient)
            cr:rectangle(0, 0, width, fade_height)
            cr:fill()
            gradient:destroy()
        end
        cr:restore()
    end
    scroll_view.layout = function(_, context, width)
        return {wibox.widget.base.place_widget_at(content, 0, -s.sidebar_scroll_position,
            width, scroll_content_height)}
    end
    local function thumb_geometry(width)
        if scroll_max <= 0 then return 0, width end
        local thumb_width = math.max(24, math.floor(width * scroll_viewport_height / scroll_content_height))
        thumb_width = math.min(width, thumb_width)
        local x = (width - thumb_width) * s.sidebar_scroll_position / scroll_max
        return x, thumb_width
    end
    scrollbar = wibox.widget.base.make_widget()
    scrollbar.visible = false
    scrollbar.forced_height = 0
    scrollbar.fit = function(_, _, width) return width, scrollbar_height end
    scrollbar.draw = function(_, _, cr, width, height)
        cr:set_source_rgb(0.025, 0.07, 0.05)
        cr:rectangle(0, 0, width, height)
        cr:fill()
        cr:set_source_rgb(0.16, 0.28, 0.25)
        cr:rectangle(0, math.floor(height / 2) - 2, width, 4)
        cr:fill()
        local x, thumb_width = thumb_geometry(width)
        cr:set_source_rgb(0.44, 0.77, 0.74)
        cr:rectangle(x, 1, thumb_width, height - 2)
        cr:fill()
        cr:set_source_rgb(0.78, 1, 0.91)
        cr:rectangle(x + 1, 1, math.max(0, thumb_width - 2), 1)
        cr:fill()
    end
    scrollbar_panel = wibox {
        screen = s, type = "utility", visible = false, ontop = true,
        width = sidebar_width - 2, height = scrollbar_height,
        x = s.geometry.x + s.geometry.width - sidebar_width + 2,
        y = s.geometry.y + s.geometry.height - scrollbar_height,
        bg = "#07120d", border_width = 0, restrict_workarea = false,
    }
    scrollbar_panel:setup {
        scrollbar, bg = "#07120d", widget = wibox.container.background,
    }
    sidebar_column = wibox.widget.base.make_widget()
    sidebar_column.fit = function(_, _, width, height) return width, height end
    sidebar_column.layout = function(_, context, width, height)
        local header_height = header.forced_height
        local clock_height = clock_card.forced_height
        local fixed_height = header_height + clock_height
        local full_viewport_height = math.max(1, height - fixed_height)
        local _, content_height = wibox.widget.base.fit_widget(
            sidebar_column, context, content, width, 2^20)
        local needs_scrollbar = content_height > full_viewport_height
        local bar_height = needs_scrollbar and scrollbar_height or 0
        local viewport_height = math.max(1, full_viewport_height - bar_height)
        local previous_max = scroll_max
        scroll_content_height, scroll_viewport_height = content_height, viewport_height
        scroll_max = math.max(0, content_height - viewport_height)
        s.sidebar_scroll_position = math.max(0, math.min(scroll_max, s.sidebar_scroll_position))
        scrollbar.visible, scrollbar.forced_height = needs_scrollbar, bar_height
        scroll_view.forced_height = viewport_height
        scrollbar_panel.visible = needs_scrollbar
        scrollbar_panel.x = (panel and panel.x or (s.geometry.x + s.geometry.width - sidebar_width)) + 2
        scrollbar_panel.y = (panel and panel.y or (s.geometry.y + 30))
            + fixed_height + viewport_height
        scrollbar_panel.width, scrollbar_panel.height = width, scrollbar_height
        if previous_max ~= scroll_max then scrollbar:emit_signal("widget::redraw_needed") end
        return {
            wibox.widget.base.place_widget_at(header, 0, 0, width, header_height),
            wibox.widget.base.place_widget_at(clock_card, 0, header_height, width, clock_height),
            wibox.widget.base.place_widget_at(scroll_view, 0, fixed_height, width, viewport_height),
        }
    end
    local function set_scroll_from_pointer(x)
        local track_x = (panel and panel.x or (s.geometry.x + s.geometry.width - sidebar_width)) + 2
        local track_width = sidebar_width - 2
        local thumb_width = select(2, thumb_geometry(track_width))
        local travel = math.max(1, track_width - thumb_width)
        local fraction = math.max(0, math.min(1, (x - track_x - thumb_width / 2) / travel))
        set_scroll_offset(fraction * scroll_max)
    end
    scrollbar:buttons(gears.table.join(awful.button({}, 1, function()
        suppress_scroll_click = true
        set_scroll_from_pointer(mouse.coords().x)
        mousegrabber.run(function(pointer)
            set_scroll_from_pointer(pointer.x)
            if pointer.buttons[1] then return true end
            gears.timer.start_new(0.18, function()
                suppress_scroll_click = false
                return false
            end)
            return false
        end, "sb_h_double_arrow")
    end)))
    panel = wibox {
        screen = s, type = "dock", visible = false, ontop = false,
        width = sidebar_width, height = sidebar_height,
        x = s.geometry.x + s.geometry.width - sidebar_width, y = s.geometry.y + 30,
        bg = sidebar_gradient, fg = palette.text,
        border_width = 0,
        shape = gears.shape.rectangle, restrict_workarea = false,
    }
    panel:setup {
        {
            {forced_width = 2, bg = palette.teal, widget = wibox.container.background},
            sidebar_column,
            layout = wibox.layout.fixed.horizontal,
        },
        bg = sidebar_gradient, widget = wibox.container.background,
    }
    panel:connect_signal("button::press", function(_, _, _, button)
        if dismiss_menu then dismiss_menu() end
        local delta = button == 4 and -32 or (button == 5 and 32 or nil)
        if delta and mouse.coords().y >= panel.y + header.forced_height then scroll_by(delta) end
    end)
    s.sidebar = panel
    s.sidebar_scroll_view, s.sidebar_scrollbar = scroll_view, scrollbar
    s.sidebar_scrollbar_panel = scrollbar_panel
    s.sidebar_scroll_by = scroll_by
    s.sidebar_scroll_offset = function() return s.sidebar_scroll_position end
    s.sidebar_scroll_max = function() return scroll_max end
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
    s.sidebar_quake2_button, s.sidebar_sleep_button = quake2_button, sleep_button
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
    s.sidebar_media_text = media_text
    s.sidebar_root_text = root_text
    s.sidebar_weather_text = weather_main
    s.sidebar_wallpaper_preview, s.sidebar_wallpaper_name = preview, wallpaper_name
    s.sidebar_wallpaper_controls = wallpaper_controls
    s.sidebar_wallpaper_previous, s.sidebar_wallpaper_next = previous_wallpaper, next_wallpaper
    s.sidebar_wallpaper_previous_action, s.sidebar_wallpaper_next_action =
        show_previous_wallpaper, show_next_wallpaper
    s.sidebar_wallpaper_apply = apply_wallpaper
    s.sidebar_wallpaper_count = #wallpapers
    s:connect_signal("property::geometry", function()
        if not s.valid then return end
        panel.x = s.geometry.x + s.geometry.width - sidebar_width
        panel.y = s.geometry.y + 30
        panel.height = math.max(1, s.geometry.height - 30)
        sidebar_column:emit_signal("widget::layout_changed")
    end)

    local previous_total, previous_idle, previous_rx, previous_tx, previous_net_time
    local function update_stats()
        clock.current_time = os.date("*t")
        clock:emit_signal("widget::redraw_needed")
        digital_time.markup = string.format("<span foreground='%s' size='24pt' weight='bold'>%s</span>",
            palette.neon, os.date("%H:%M:%S"))
        date.markup = string.format("<span foreground='%s' size='12pt' weight='bold'>%s</span>",
            palette.teal, os.date("%A  •  %d %B %Y"))

        local stat = read("/proc/stat")
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
                cpu_text.text = string.format("CPU  %.0f%%", usage)
                cpu_bar.value = math.floor(usage + 0.5)
            end
            previous_total, previous_idle = total, idle
        end

        local mem_total = tonumber((read("/proc/meminfo") or ""):match("MemTotal:%s+(%d+)"))
        local mem_available = tonumber((read("/proc/meminfo") or ""):match("MemAvailable:%s+(%d+)"))
        if mem_total and mem_available and mem_total > 0 then
            local used = mem_total - mem_available
            memory_text.text = string.format("Memory  %.1f / %.1f GiB", used / 1048576, mem_total / 1048576)
            memory_bar.value = math.floor(used * 100 / mem_total + 0.5)
        end

        local root_total, root_free = filesystem_stats()
        if root_total and root_free then
            root_text.text = string.format("Free /  %.1f GiB", root_free / 1073741824)
            root_bar.value = math.floor((root_total - root_free) * 100 / root_total + 0.5)
        end

        local capacity, state, mouse_capacity, mouse_state = battery_stats()
        battery_text.visible, battery_bar.visible = capacity ~= nil, capacity ~= nil
        if capacity then
            battery_text.text = string.format("Battery  %d%%  %s", capacity, state)
            battery_bar.value = capacity
        end
        mouse_battery_text.visible, mouse_battery_bar.visible = mouse_capacity ~= nil, mouse_capacity ~= nil
        if mouse_capacity then
            mouse_battery_text.text = string.format("Mouse  %d%%  %s", mouse_capacity, mouse_state or "Unknown")
            mouse_battery_bar.value = mouse_capacity
        end
        stats_card:emit_signal("widget::layout_changed")

        local rx, tx = network_stats()
        if rx and tx then
            local now = os.time()
            if previous_rx and previous_tx and previous_net_time and now > previous_net_time then
                network_text.text = string.format("↓ %s   ↑ %s",
                    rate(math.max(0, rx - previous_rx) / (now - previous_net_time)),
                    rate(math.max(0, tx - previous_tx) / (now - previous_net_time)))
            else
                network_text.text = "Network  measuring…"
            end
            previous_rx, previous_tx, previous_net_time = rx, tx, now
        end
    end

    local media_pending = false
    local function update_media()
        if media_pending then return end
        media_pending = true
        awful.spawn.easy_async({"playerctl", "metadata", "--format", "{{artist}} — {{title}}"},
            function(stdout, _, _, code)
                media_pending = false
                local track = stdout:gsub("%s+$", "")
                media_text.text = code == 0 and track ~= "" and track or "Nothing playing"
            end)
    end

    s.sidebar_stats_timer = gears.timer {
        timeout = 1, autostart = true, call_now = true, callback = update_stats,
    }
    s.sidebar_volume_timer = gears.timer {
        timeout = 3, autostart = true, call_now = true, callback = update_volume,
    }
    s.sidebar_media_timer = gears.timer {
        timeout = 5, autostart = true, call_now = true, callback = update_media,
    }
    s.sidebar_trash_timer = gears.timer {
        timeout = 30, autostart = true, call_now = false, callback = refresh_trash_status,
    }
    s.sidebar_todo_refresh = refresh_todo
    s.sidebar_todo_timer = gears.timer {
        timeout = 60, autostart = true, call_now = false, callback = refresh_todo,
    }
    s.sidebar_calendar_refresh = refresh_calendar
    s.sidebar_calendar_timer = gears.timer {
        timeout = 60, autostart = true, call_now = false, callback = refresh_calendar,
    }
    s.sidebar_crypto_timer = gears.timer {
        timeout = 60, autostart = true, call_now = true, callback = refresh_crypto,
    }
    s.sidebar_codex_timer = gears.timer {
        timeout = 60, autostart = true, call_now = true, callback = refresh_codex,
    }
    if os.getenv("AWESOME_TEST_MODE") ~= "1" then
        s.sidebar_weather_timer = gears.timer {
            timeout = 1800, autostart = true, call_now = true, callback = update_weather,
        }
    else
        weather_main.text = "Weather disabled in test"
    end
    s:connect_signal("removed", function()
        s.sidebar_stats_timer:stop()
        s.sidebar_volume_timer:stop()
        s.sidebar_media_timer:stop()
        s.sidebar_trash_timer:stop()
        s.sidebar_todo_timer:stop()
        s.sidebar_calendar_timer:stop()
        s.sidebar_crypto_timer:stop()
        s.sidebar_codex_timer:stop()
        if s.sidebar_weather_timer then s.sidebar_weather_timer:stop() end
        panel.visible = false
    end)
end

return sidebar
