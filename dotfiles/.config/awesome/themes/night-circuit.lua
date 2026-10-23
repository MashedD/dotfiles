-- NIGHT CIRCUIT: ink, ultraviolet, ice-cyan and mint over square geometry.
-- Static surfaces only. Highlights are narrow enough to stay clear of text.
local gears = require("gears")
local appearance = {sidebar_opacity = 1}
appearance.palette = {
    bg = "#070a13", card = "#0e1220", line = "#293249",
    bevel_light = "#43536c", bevel_shadow = "#03050c",
    text = "#e0e8f5", muted = "#a7b3c9", teal = "#64e6d8",
    green = "#80f7a5", neon = "#00ff41", amber = "#ffd36e", red = "#ff8e99",
    title = "#edfaff", inactive = "#c0cbe0", minimized = "#9ba9c0",
    active_border = "#48e5ef", inactive_border = "#333c55",
    menu_border = "#52668e", menu_separator = "#333852", menu_base = "#111527",
    workspace_active = "#68e8ef", workspace_text = "#080c18", accent = "#f082d5",
    control_border = "#48c5b4", close_border = "#ed6d85",
    urgency = "#ff83d5", urgency_bg = "#31132b",
    scrollbar_track = "#080c17", scrollbar_rail = "#141c30",
    scrollbar_highlight = "#a1edff",
}
appearance.palette.calendar_weekend = appearance.palette.amber
appearance.palette.calendar_weekend_bg = "#211c12"
appearance.fonts = {body = "Microsoft Sans Serif 8", title = "Segoe UI bold 9", menu = "Segoe UI 9",
    telemetry = "FiraCode Nerd Font Mono 8"}
appearance.stops = {
    scrollbar = {{0, "#afdff0"}, {0.14, "#659fc4"}, {0.55, "#3d82b4"}, {1, "#397ca6"}},
    control_pressed = {{0, "#072c2d"}, {0.5, "#0b4140"}, {1, "#12615b"}},
    close_pressed = {{0, "#581a21"}, {0.5, "#822727"}, {1, "#a83936"}},
    scrollbar_hover = {{0, "#d0efff"}, {0.14, "#82b8d8"}, {0.55, "#5194c2"}, {1, "#4488b2"}},
    scrollbar_drag = {{0, "#e6f7ff"}, {0.14, "#9dcbe5"}, {0.55, "#68a7cf"}, {1, "#5197bd"}},
    control = {{0, "#86e8dc"}, {0.035, "#299e92"}, {0.10, "#104e49"},
        {0.55, "#0c3538"}, {1, "#09272d"}},
    control_hover = {{0, "#b5fff0"}, {0.035, "#55ceba"}, {0.10, "#14665a"},
        {0.55, "#104e49"}, {1, "#0a3838"}},
    close = {{0, "#fff0e8"}, {0.035, "#edaca0"}, {0.10, "#a83936"},
        {0.55, "#8c2929"}, {1, "#581a21"}},
    close_hover = {{0, "#fff8ef"}, {0.035, "#ffc2ae"}, {0.10, "#bd4238"},
        {0.55, "#a7332d"}, {1, "#742227"}},
    -- Whole-popup surface: no broad pale highlight behind the first menu rows.
    menu = {{0, "#20243d"}, {0.45, "#151b30"}, {1, "#0c1121"}},
    panel = {{0, "#20263d"}, {0.10, "#101524"}, {1, "#090d18"}},
    section = {{0, "#20273e"}, {1, "#151c30"}},
    blue = {{0, "#62cfe8"}, {0.035, "#29627b"}, {0.10, "#123047"},
        {0.50, "#0c2238"}, {1, "#071425"}},
    selected = {{0, "#7debf6"}, {0.035, "#4c7ba6"}, {0.10, "#323657"},
        {0.50, "#222a49"}, {1, "#151d34"}},
    inactive = {{0, "#3c425c"}, {0.035, "#292f46"}, {0.10, "#1c2235"},
        {0.50, "#141a2b"}, {1, "#0e1422"}},
    card = {{0, "#202a40"}, {0.01, "#151d2f"}, {0.10, "#0e1422"}, {1, "#0b101d"}},
    forest = {{0, "#060a12"}, {0.32, "#0a101d"}, {0.72, "#11192a"}, {1, "#080d19"}},
}
function appearance.gradient(name, height)
    return gears.color {type = "linear", from = {0, 0}, to = {0, height}, stops = appearance.stops[name]}
end
function appearance.forest(width)
    return gears.color {type = "linear", from = {0, 0}, to = {width, 0}, stops = appearance.stops.forest}
end
-- Fine PCB traces across unused panel space; child widgets cover their own area.
-- This is painted only on redraw, with no animation, polling or image allocation.
function appearance.circuit(_, cr, width, height)
    if width < 700 then return end
    cr:set_line_width(1)
    cr:set_source(gears.color("#48e5ef22"))
    local start = math.floor(width * 0.48)
    for lane = 0, 2 do
        local y = 7 + lane * 6
        cr:move_to(start + lane * 35, y)
        for x = start + 80 + lane * 35, width - 150, 150 do
            cr:line_to(x, y)
            cr:line_to(x + 6, y + 3)
            cr:line_to(x + 24, y + 3)
            cr:line_to(x + 30, y)
        end
        cr:stroke()
    end
    cr:set_source(gears.color("#f082d566"))
    for x = start + 140, width - 160, 300 do
        cr:rectangle(x, math.min(height - 3, 20), 7, 2)
    end
    cr:fill()
end
-- Remaining capacity: attention at 20%, urgent at 10% (disk uses 10%/5%).
function appearance.remaining_color(percent, attention, urgent)
    if percent <= (urgent or 10) then return appearance.palette.red end
    if percent <= (attention or 20) then return appearance.palette.amber end
    return appearance.palette.green
end
function appearance.trash_color(full)
    if full == nil then return appearance.palette.text end
    return full and appearance.palette.amber or appearance.palette.green
end
return appearance
