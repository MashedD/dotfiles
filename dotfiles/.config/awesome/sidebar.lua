-- Longhorn-inspired gadget rail; resource, media, and volume tools live here.
local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local Gio = require("lgi").Gio
local cairo = require("lgi").cairo
local gstring = require("gears.string")
local sidebar = {}

local palette = {
    bg = "#07110d", card = "#101a15", line = "#263b30",
    bevel_light = "#496653", bevel_shadow = "#050b07",
    text = "#c7d5cb", muted = "#63736a", teal = "#70c5bd",
    green = "#70c98b", neon = "#00ff41", amber = "#d6bd72",
}

local sidebar_gradient = gears.color {
    type = "linear", from = {0, 0}, to = {300, 0},
    stops = {{0, "#09150f"}, {0.38, "#14271b"}, {0.78, "#1b3022"}, {1, "#0a1710"}},
}
local card_gradient = gears.color {
    type = "linear", from = {0, 0}, to = {300, 0},
    stops = {{0, "#17271c"}, {0.5, "#142219"}, {1, "#101a14"}},
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

local function read_calendar_entries()
    local file = open_document("calendar.md")
    if not file then return {} end
    local today = os.date("%Y-%m-%d")
    local entries, previous, current, future = {}, {}, {}, {}

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

local function make_analog_clock()
    local clock = wibox.widget.base.make_widget()
    clock.forced_width, clock.forced_height = 124, 124
    clock.fit = function() return 124, 124 end
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

local function card(widget, height, padding)
    local surface = wibox.widget {
        {widget, margins = padding or 9, widget = wibox.container.margin},
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

local function style_button(button)
    local hovered, pressed = false, false
    local function update()
        button.bg = pressed and button_pressed_gradient
            or (hovered and button_hover_gradient or button_gradient)
        button.border_color = pressed and palette.neon
            or (hovered and palette.teal or palette.bevel_light)
    end
    button:connect_signal("mouse::enter", function() hovered = true; update() end)
    button:connect_signal("mouse::leave", function() hovered = false; pressed = false; update() end)
    button:connect_signal("button::press", function() pressed = true; update() end)
    button:connect_signal("button::release", function() pressed = false; update() end)
    return button
end

local function progress(color)
    return wibox.widget {
        max_value = 100, value = 0, forced_height = 10,
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
    if not enumerator then return nil end
    local capacities, states = {}, {}
    while true do
        local entry = enumerator:next_file()
        if not entry then break end
        local name = entry:get_name()
        -- Only laptop batteries; ignore wireless mice and headsets.
        local supply_type = read(root .. name .. "/type") or ""
        if name:match("^BAT") and supply_type:match("^Battery") then
            local capacity = tonumber(read(root .. name .. "/capacity"))
            if capacity then
                capacities[#capacities + 1] = capacity
                states[#states + 1] = (read(root .. name .. "/status") or "Unknown"):gsub("%s+$", "")
            end
        end
    end
    enumerator:close()
    if #capacities == 0 then return nil end
    local sum = 0
    for _, capacity in ipairs(capacities) do sum = sum + capacity end
    return math.floor(sum / #capacities + 0.5), table.concat(states, ", ")
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
    local root = (os.getenv("XDG_DATA_HOME") or os.getenv("HOME") .. "/.local/share") .. "/wallpapers"
    local enumerator = Gio.File.new_for_path(root):enumerate_children("standard::name", 0)
    local paths = {}
    if enumerator then
        while true do
            local entry = enumerator:next_file()
            if not entry then break end
            local name = entry:get_name()
            if name:match("%.png$") then paths[#paths + 1] = root .. "/" .. name end
        end
        enumerator:close()
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

local function launcher(text, command)
    local button = style_button(wibox.widget {
        label(text, palette.teal, 10, true, "center"),
        forced_width = 112, forced_height = 34,
        bg = button_gradient, border_width = 1, border_color = palette.bevel_light,
        widget = wibox.container.background,
    })
    button:buttons(gears.table.join(awful.button({}, 1, function() awful.spawn(command) end)))
    return button
end

local function action_button(text, callback)
    local button = style_button(wibox.widget {
        label(text, palette.teal, 14, true, "center"),
        forced_width = 46, forced_height = 28,
        bg = button_gradient, border_width = 1, border_color = palette.bevel_light,
        widget = wibox.container.background,
    })
    button:buttons(gears.table.join(awful.button({}, 1, callback)))
    return button
end

function sidebar.create(s)
    local clock = make_analog_clock()
    local digital_time = label("00:00:00", palette.neon, 24, true, "center")
    local date = label("", palette.teal, 12, true, "center")
    local cpu_text = label("CPU  measuring…", palette.text, 10, false)
    local memory_text = label("Memory  reading…", palette.text, 10, false)
    local battery_text = label("Battery  --", palette.text, 10, false)
    local root_text = label("Free /  reading…", palette.text, 10, false)
    local network_text = label("Network  measuring…", palette.text, 10, false)
    local cpu_bar, memory_bar = progress(palette.neon), progress(palette.green)
    local battery_bar, root_bar = progress(palette.amber), progress(palette.teal)
    local volume_text = label("Volume  --", palette.text, 10, false)
    local volume_bar = progress(palette.teal)
    local media_text = label("Checking player…", palette.text, 11, false, "center")
    media_text.wrap = "word_char"
    media_text.ellipsize = "end"

    local header = wibox.widget {
        {
            label("MashedD's AwesomeBar", palette.teal, 12, true),
            left = 10, right = 6, widget = wibox.container.margin,
        },
        forced_height = 30, bg = button_gradient,
        border_width = 1, border_color = palette.bevel_light,
        widget = wibox.container.background,
    }
    local clock_centered = wibox.widget {
        clock, halign = "center", valign = "center", widget = wibox.container.place,
    }
    local clock_content = wibox.layout.fixed.vertical()
    clock_content.spacing = 3
    clock_content:add(clock_centered)
    clock_content:add(date)
    clock_content:add(digital_time)
    digital_time.visible = false
    local clock_card = card(clock_content, 154, 4)
    local clock_mode = "analog"
    local function set_clock_mode(mode)
        clock_mode = mode
        clock.visible = mode == "analog"
        clock_centered.visible = mode == "analog"
        digital_time.visible = mode == "text"
        clock_card.forced_height = mode == "analog" and 154 or 66
        s.sidebar_clock_mode = mode
    end
    local function toggle_clock_mode()
        set_clock_mode(clock_mode == "analog" and "text" or "analog")
    end
    local function bind_clock_toggle(widget)
        widget:buttons(gears.table.join(awful.button({}, 1, toggle_clock_mode)))
    end
    bind_clock_toggle(clock)
    bind_clock_toggle(digital_time)
    bind_clock_toggle(date)
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
    preview.forced_height = 112
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
        })
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
    local preview_centered = {preview, halign = "center", valign = "center", widget = wibox.container.place}
    local wallpaper_card = card({
        label("WALLPAPER", palette.teal, 10, true, "center"),
        preview_centered,
        {wallpaper_controls, halign = "center", widget = wibox.container.place},
        spacing = 5, layout = wibox.layout.fixed.vertical,
    }, 180)

    local weather_icon = label("☁", palette.teal, 22, true, "center")
    weather_icon.font = "Noto Sans Symbols 2 20"
    weather_icon.forced_width = 32
    local weather_main = label("Weather loading…", palette.text, 14, true, "center")
    local weather_detail = label("Bydgoszcz, Poland", palette.muted, 10, false, "center")
    weather_main.forced_width, weather_detail.forced_width = 190, 190
    local weather_text_stack = wibox.widget {
        weather_main, weather_detail, spacing = 2,
        layout = wibox.layout.fixed.vertical,
    }
    local weather_line = wibox.widget {
        weather_icon, weather_text_stack, spacing = 8,
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
    local weather_card = card({
        label("BYDGOSZCZ · WEATHER", palette.teal, 10, true, "center"),
        {weather_line, halign = "center", valign = "center", widget = wibox.container.place},
        spacing = 3, layout = wibox.layout.fixed.vertical,
    }, 72, 5)

    local stats_card = card({
        label("SYSTEM STATUS", palette.teal, 10, true, "center"),
        cpu_text, cpu_bar,
        memory_text, memory_bar,
        battery_text, battery_bar,
        root_text, root_bar,
        network_text,
        spacing = 4, layout = wibox.layout.fixed.vertical,
    }, 172)

    local media_controls = wibox.widget {
        action_button("«", function() awful.spawn.easy_async({"playerctl", "previous"}, function() end) end),
        action_button("▶", function() awful.spawn.easy_async({"playerctl", "play-pause"}, function() end) end),
        action_button("»", function() awful.spawn.easy_async({"playerctl", "next"}, function() end) end),
        spacing = 8, layout = wibox.layout.fixed.horizontal,
    }
    local media_controls_centered = {
        media_controls, halign = "center", valign = "center", widget = wibox.container.place,
    }
    local media_card = card({
        label("NOW PLAYING", palette.teal, 10, true, "center"),
        media_text, media_controls_centered,
        spacing = 4, layout = wibox.layout.fixed.vertical,
    }, 100)

    local volume_control = wibox.widget {
        volume_text, volume_bar, spacing = 4,
        layout = wibox.layout.fixed.vertical,
    }
    local volume_pending = false
    local function update_volume()
        if volume_pending then return end
        volume_pending = true
        awful.spawn.easy_async({"wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"}, function(stdout, _, _, code)
            volume_pending = false
            local value = code == 0 and tonumber(stdout:match("Volume:%s*([%d.]+)")) or nil
            local muted = stdout:find("MUTED", 1, true) ~= nil
            volume_text.markup = string.format(
                "<span foreground='%s' size='10pt'>Volume  %s</span>",
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
        awful.button({}, 3, function() change_volume("mute") end),
        awful.button({}, 4, function() change_volume("up") end),
        awful.button({}, 5, function() change_volume("down") end)
    ))
    local audio_header = label("AUDIO", palette.teal, 10, true, "center")
    local volume_card = card({
        audio_header, volume_control,
        spacing = 4, layout = wibox.layout.fixed.vertical,
    }, 80)

    local todo_entries = {}
    local todo_list = wibox.layout.fixed.vertical()
    todo_list.spacing = 4
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
    local todo_card = card({
        label("TODO", palette.teal, 10, true, "center"),
        todo_list, spacing = 5, layout = wibox.layout.fixed.vertical,
    }, nil, 7)

    local calendar_entries = {}
    local calendar_list = wibox.layout.fixed.vertical()
    calendar_list.spacing = 4
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
        local date_text = entry.day == "today" and ("TODAY " .. short_date)
            or (entry.date == yesterday and ("YESTERDAY " .. short_date)
                or os.date("%a %d.%m", entry.timestamp))
        local time_markup = entry.time and string.format(
            " <span foreground='%s'>%s</span>", time_color, gstring.xml_escape(entry.time)) or ""
        local row = wibox.widget {
            markup = string.format("<span foreground='%s' weight='bold'>%s</span>%s <span foreground='%s' weight='%s'>%s</span>",
                date_color, date_text, time_markup, event_color, weight, gstring.xml_escape(entry.text)),
            wrap = "word_char", valign = "top", widget = wibox.widget.textbox,
        }
        return row
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
    local calendar_card = card({
        label("CALENDAR", palette.teal, 10, true, "center"),
        calendar_list, spacing = 5, layout = wibox.layout.fixed.vertical,
    }, nil, 7)

    local quick_card = card({
        label("QUICK LAUNCH", palette.teal, 10, true, "center"),
        {
            {
                launcher("Terminal", {"kitty"}), launcher("Files", {"pcmanfm"}),
                spacing = 8, layout = wibox.layout.fixed.horizontal,
            }, halign = "center", widget = wibox.container.place,
        },
        {
            {
                launcher("Monitor", {"kitty", "--title", "System Monitor", "btop"}),
                launcher("Finder", {"xfce4-appfinder"}),
                spacing = 8, layout = wibox.layout.fixed.horizontal,
            }, halign = "center", widget = wibox.container.place,
        },
        spacing = 6, layout = wibox.layout.fixed.vertical,
    }, 124)

    local sidebar_width = 300
    local panel = wibox {
        screen = s, type = "dock", visible = false, ontop = false,
        width = sidebar_width, height = math.max(1, s.geometry.height - 30),
        x = s.geometry.x + s.geometry.width - sidebar_width, y = s.geometry.y + 30,
        bg = sidebar_gradient, fg = palette.text,
        border_width = 0,
        shape = gears.shape.rectangle, restrict_workarea = false,
    }
    panel:setup {
        {
            {forced_width = 2, bg = palette.teal, widget = wibox.container.background},
            {
                header, clock_card, wallpaper_card, weather_card, stats_card, volume_card, media_card, quick_card, todo_card, calendar_card,
                spacing = 6, layout = wibox.layout.fixed.vertical,
            },
            layout = wibox.layout.fixed.horizontal,
        },
        bg = sidebar_gradient, widget = wibox.container.background,
    }
    s.sidebar = panel
    s.sidebar_mode = 0
    s.sidebar_clock, s.sidebar_digital_time, s.sidebar_date = clock, digital_time, date
    s.sidebar_clock_card = clock_card
    s.sidebar_cpu, s.sidebar_battery = cpu_text, battery_text
    s.sidebar_volume, s.sidebar_volume_text = volume_control, volume_text
    s.sidebar_audio_header = audio_header
    s.sidebar_todo_entries, s.sidebar_todo_card = todo_entries, todo_card
    s.sidebar_calendar_card = calendar_card
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

        local capacity, state = battery_stats()
        battery_text.visible, battery_bar.visible = capacity ~= nil, capacity ~= nil
        if capacity then
            battery_text.text = string.format("Battery  %d%%  %s", capacity, state)
            battery_bar.value = capacity
        end

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
    s.sidebar_todo_refresh = refresh_todo
    s.sidebar_todo_timer = gears.timer {
        timeout = 60, autostart = true, call_now = false, callback = refresh_todo,
    }
    s.sidebar_calendar_refresh = refresh_calendar
    s.sidebar_calendar_timer = gears.timer {
        timeout = 60, autostart = true, call_now = false, callback = refresh_calendar,
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
        s.sidebar_todo_timer:stop()
        s.sidebar_calendar_timer:stop()
        if s.sidebar_weather_timer then s.sidebar_weather_timer:stop() end
        panel.visible = false
    end)
end

return sidebar
