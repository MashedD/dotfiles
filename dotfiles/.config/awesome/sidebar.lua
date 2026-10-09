-- Longhorn-inspired gadget rail; resource, media, and volume tools live here.
local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local Gio = require("lgi").Gio
local sidebar = {}

local palette = {
    bg = "#07110d", card = "#101a15", line = "#263b30",
    text = "#c7d5cb", muted = "#63736a", teal = "#70c5bd",
    green = "#70c98b", neon = "#00ff41", amber = "#d6bd72",
}

local function read(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local value = file:read("*a")
    file:close()
    return value
end

local function label(text, color, size, bold)
    return wibox.widget {
        markup = string.format("<span foreground='%s' size='%dpt'%s>%s</span>",
            color, size, bold and " weight='bold'" or "", text),
        align = "left", valign = "center", widget = wibox.widget.textbox,
    }
end

local function card(widget, height)
    return wibox.widget {
        {widget, margins = 10, widget = wibox.container.margin},
        forced_height = height, bg = palette.card,
        border_width = 1, border_color = palette.line,
        widget = wibox.container.background,
    }
end

local function progress(color)
    return wibox.widget {
        max_value = 100, value = 0, forced_height = 8,
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
    local button = wibox.widget {
        label(text, palette.teal, 9, true),
        forced_width = 94, forced_height = 30,
        bg = palette.bg, border_width = 1, border_color = palette.line,
        widget = wibox.container.background,
    }
    button:buttons(gears.table.join(awful.button({}, 1, function() awful.spawn(command) end)))
    awful.tooltip {objects = {button}, text = text}
    return button
end

local function action_button(text, callback)
    local button = wibox.widget {
        label(text, palette.teal, 12, true),
        forced_width = 42, forced_height = 24,
        bg = palette.bg, border_width = 1, border_color = palette.line,
        widget = wibox.container.background,
    }
    button:buttons(gears.table.join(awful.button({}, 1, callback)))
    return button
end

function sidebar.create(s)
    local time = label("00:00:00", palette.neon, 22, true)
    local date = label("", palette.muted, 9, false)
    local cpu_text = label("CPU  measuring…", palette.text, 9, false)
    local memory_text = label("Memory  reading…", palette.text, 9, false)
    local battery_text = label("Battery  --", palette.text, 9, false)
    local network_text = label("Network  measuring…", palette.text, 9, false)
    local cpu_bar, memory_bar, battery_bar = progress(palette.neon), progress(palette.green), progress(palette.amber)
    local volume_text = label("Volume  --", palette.text, 9, false)
    local volume_bar = progress(palette.teal)
    local media_text = label("Checking player…", palette.text, 9, false)
    media_text.wrap = "word_char"
    media_text.ellipsize = "end"
    local volume_tip = awful.tooltip {objects = {volume_text}, text = "Volume"}

    local header = wibox.widget {
        label("AURORA  /  SIDEBAR", palette.teal, 10, true),
        forced_height = 24, widget = wibox.container.background,
    }
    local clock_card = card({
        time, date, spacing = 3, layout = wibox.layout.fixed.vertical,
    }, 72)
    local stats_card = card({
        label("SYSTEM STATUS", palette.teal, 9, true),
        cpu_text, cpu_bar,
        memory_text, memory_bar,
        battery_text, battery_bar,
        network_text,
        spacing = 4, layout = wibox.layout.fixed.vertical,
    }, 142)

    local media_controls = wibox.widget {
        action_button("«", function() awful.spawn.easy_async({"playerctl", "previous"}, function() end) end),
        action_button("▶", function() awful.spawn.easy_async({"playerctl", "play-pause"}, function() end) end),
        action_button("»", function() awful.spawn.easy_async({"playerctl", "next"}, function() end) end),
        spacing = 8, layout = wibox.layout.fixed.horizontal,
    }
    local media_card = card({
        label("NOW PLAYING", palette.teal, 9, true),
        media_text, media_controls,
        spacing = 4, layout = wibox.layout.fixed.vertical,
    }, 86)

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
                "<span foreground='%s' size='9pt'>Volume  %s</span>",
                muted and palette.amber or palette.text,
                value and (muted and "Mute" or string.format("%.0f%%", value * 100)) or "--")
            volume_bar.value = value and math.floor(value * 100 + 0.5) or 0
            volume_tip.text = value and ("Volume: " .. (muted and "Mute" or string.format("%.0f%%", value * 100))
                .. "\nClick: mixer; right-click: mute; wheel: volume")
                or "No default audio output\nClick to open Volume Control"
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
    local volume_card = card({
        label("AUDIO", palette.teal, 9, true), volume_control,
        spacing = 4, layout = wibox.layout.fixed.vertical,
    }, 64)

    local quick_card = card({
        label("QUICK LAUNCH", palette.teal, 9, true),
        {
            launcher("Terminal", {"kitty"}), launcher("Files", {"pcmanfm"}),
            spacing = 8, layout = wibox.layout.fixed.horizontal,
        },
        {
            launcher("Monitor", {"kitty", "--title", "System Monitor", "btop"}),
            launcher("Finder", {"xfce4-appfinder"}),
            spacing = 8, layout = wibox.layout.fixed.horizontal,
        },
        spacing = 6, layout = wibox.layout.fixed.vertical,
    }, 110)
    local footer = label("LOCAL  •  LIVE", palette.muted, 8, false)

    local panel = wibox {
        screen = s, type = "dock", visible = false, ontop = true,
        width = 232, height = math.max(1, s.geometry.height - 34),
        x = s.geometry.x + s.geometry.width - 234, y = s.geometry.y + 32,
        bg = palette.bg, fg = palette.text,
        border_width = 1, border_color = palette.teal,
        shape = gears.shape.rectangle, restrict_workarea = false,
    }
    panel:setup {
        {
            header, clock_card, stats_card, media_card, volume_card, quick_card, footer,
            spacing = 6, layout = wibox.layout.fixed.vertical,
        },
        margins = 10, widget = wibox.container.margin,
    }
    s.sidebar = panel
    s.sidebar_clock, s.sidebar_date = time, date
    s.sidebar_cpu, s.sidebar_battery = cpu_text, battery_text
    s.sidebar_volume, s.sidebar_volume_text = volume_control, volume_text
    s.sidebar_media_text = media_text
    s:connect_signal("property::geometry", function()
        if not s.valid then return end
        panel.x = s.geometry.x + s.geometry.width - 234
        panel.y = s.geometry.y + 32
        panel.height = math.max(1, s.geometry.height - 34)
    end)

    local previous_total, previous_idle, previous_rx, previous_tx, previous_net_time
    local function update_stats()
        time.text = os.date("%H:%M:%S")
        date.text = os.date("%A  •  %d %B %Y")

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
    s:connect_signal("removed", function()
        s.sidebar_stats_timer:stop()
        s.sidebar_volume_timer:stop()
        s.sidebar_media_timer:stop()
        panel.visible = false
    end)
end

return sidebar
