-- Optional Longhorn-inspired gadget rail with a restrained wavy workspace edge.
local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local sidebar = {}

local palette = {
    bg = "#07110d", card = "#101a15", line = "#263b30",
    text = "#c7d5cb", muted = "#63736a", teal = "#70c5bd",
    green = "#70c98b", neon = "#00ff41",
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
        {
            widget, margins = 10, widget = wibox.container.margin,
        },
        forced_height = height, bg = palette.card,
        border_width = 1, border_color = palette.line,
        widget = wibox.container.background,
    }
end

local function rate(bytes)
    if not bytes then return "--" end
    if bytes >= 1024 * 1024 then return string.format("%.1f MB/s", bytes / (1024 * 1024)) end
    if bytes >= 1024 then return string.format("%.0f KB/s", bytes / 1024) end
    return string.format("%.0f B/s", bytes)
end

local function memory_stats()
    local data = read("/proc/meminfo")
    if not data then return nil end
    local total = tonumber(data:match("MemTotal:%s+(%d+)"))
    local available = tonumber(data:match("MemAvailable:%s+(%d+)"))
    if not total or not available or total <= 0 then return nil end
    return total, math.max(0, total - available)
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
            rx = rx + (values[1] or 0)
            tx = tx + (values[9] or 0)
        end
    end
    return rx, tx
end

local function wavy_edge(cr, width, height)
    local edge, amplitude = 16, 9
    local segments = math.max(4, math.floor(height / 120))
    local step = height / segments
    cr:move_to(edge, 0)
    cr:line_to(width, 0)
    cr:line_to(width, height)
    cr:line_to(edge, height)
    for i = segments, 1, -1 do
        local y0, y1 = i * step, (i - 1) * step
        local bulge = i % 2 == 0 and amplitude or -amplitude
        cr:curve_to(edge + bulge, y0 - step * 0.25,
            edge + bulge, y0 - step * 0.75, edge, y1)
    end
    cr:close_path()
end

local function launcher(text, command)
    local button = wibox.widget {
        label(text, palette.teal, 9, true),
        forced_width = 94, forced_height = 34,
        bg = palette.bg, border_width = 1, border_color = palette.line,
        widget = wibox.container.background,
    }
    button:buttons(gears.table.join(awful.button({}, 1, function()
        awful.spawn(command)
    end)))
    awful.tooltip {objects = {button}, text = text}
    return button
end

function sidebar.create(s)
    local time = label("00:00", palette.neon, 28, true)
    local date = label("", palette.muted, 9, false)
    local memory = label("Reading memory…", palette.text, 10, false)
    local network = label("Network  --", palette.text, 9, false)
    local memory_bar = wibox.widget {
        max_value = 100, value = 0, forced_height = 8,
        background_color = palette.bg, color = palette.green,
        border_color = palette.line, border_width = 1,
        widget = wibox.widget.progressbar,
    }

    local header = wibox.widget {
        label("AURORA  /  SIDEBAR", palette.teal, 10, true),
        forced_height = 26, widget = wibox.container.background,
    }
    local clock_card = card({
        time, date, spacing = 3, layout = wibox.layout.fixed.vertical,
    }, 84)
    local stats_card = card({
        label("SYSTEM STATUS", palette.teal, 9, true),
        memory, memory_bar,
        wibox.widget {forced_height = 1, color = palette.line, widget = wibox.widget.separator},
        network,
        spacing = 7, layout = wibox.layout.fixed.vertical,
    }, 132)
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
        spacing = 8, layout = wibox.layout.fixed.vertical,
    }, 132)
    local footer = label("LOCAL  •  LIVE", palette.muted, 8, false)

    local panel = wibox {
        screen = s, type = "dock", visible = false, ontop = true,
        width = 232, height = math.max(1, s.geometry.height - 34),
        x = s.geometry.x + s.geometry.width - 234, y = s.geometry.y + 32,
        bg = palette.bg, fg = palette.text,
        border_width = 1, border_color = palette.teal,
        shape = wavy_edge, restrict_workarea = false,
    }
    panel:setup {
        {
            header, clock_card, stats_card, quick_card, footer,
            spacing = 10, layout = wibox.layout.fixed.vertical,
        },
        left = 27, right = 10, top = 12, bottom = 12,
        widget = wibox.container.margin,
    }
    s.sidebar = panel
    s:connect_signal("property::geometry", function()
        if not s.valid then return end
        panel.x = s.geometry.x + s.geometry.width - 234
        panel.y = s.geometry.y + 32
        panel.height = math.max(1, s.geometry.height - 34)
    end)

    local previous_rx, previous_tx
    local function update()
        time.text = os.date("%H:%M")
        date.text = os.date("%A  •  %d %B %Y")
        local total, used = memory_stats()
        if total and used then
            memory.text = string.format("Memory  %.1f / %.1f GiB", used / 1048576, total / 1048576)
            memory_bar.value = math.floor(used * 100 / total + 0.5)
        end
        local rx, tx = network_stats()
        if rx and tx then
            if previous_rx and previous_tx then
                network.text = string.format("↓ %s    ↑ %s", rate(math.max(0, rx - previous_rx) / 2), rate(math.max(0, tx - previous_tx) / 2))
            else
                network.text = "Network  measuring…"
            end
            previous_rx, previous_tx = rx, tx
        end
    end
    s.sidebar_timer = gears.timer {timeout = 2, autostart = true, call_now = true, callback = update}
    s:connect_signal("removed", function()
        s.sidebar_timer:stop()
        panel.visible = false
    end)
end

return sidebar
