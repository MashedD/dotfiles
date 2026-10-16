-- Shared square Aero/Win98 surfaces. Text sits below the narrow glass highlight.
local gears = require("gears")
local appearance = {sidebar_opacity = 0.94}
appearance.palette = {
    bg = "#07110df5", card = "#101a15f5", line = "#446a62",
    bevel_light = "#73a79f", bevel_shadow = "#020805",
    text = "#e0eee7", muted = "#b7c8bd", teal = "#9cddd4",
    green = "#a8f0bd", neon = "#00ff41", amber = "#ffd36e", red = "#ff8e89",
    title = "#f2fffb", inactive = "#d6e7e3", minimized = "#c1d1dd",
    active_border = "#b4e8ff", inactive_border = "#527797",
    menu_border = "#73a7c5", menu_separator = "#527b96", menu_base = "#183d5b",
    control_border = "#93d6c2", close_border = "#eaa39a",
    scrollbar_track = "#0b2338", scrollbar_rail = "#122d43",
    scrollbar_highlight = "#c1edff",
}
appearance.palette.calendar_weekend = appearance.palette.amber
appearance.palette.calendar_weekend_bg = "#211c12"
appearance.fonts = {body = "Microsoft Sans Serif 8", title = "Segoe UI bold 9", menu = "Segoe UI 9"}
appearance.stops = {
    scrollbar = {{0, "#afdff0"}, {0.14, "#659fc4"}, {0.55, "#3d82b4"}, {1, "#397ca6"}},
    control_pressed = {{0, "#0a3529"}, {0.5, "#124b3a"}, {1, "#17634f"}},
    close_pressed = {{0, "#581a21"}, {0.5, "#822727"}, {1, "#a83936"}},
    scrollbar_hover = {{0, "#d0efff"}, {0.14, "#82b8d8"}, {0.55, "#5194c2"}, {1, "#4488b2"}},
    scrollbar_drag = {{0, "#e6f7ff"}, {0.14, "#9dcbe5"}, {0.55, "#68a7cf"}, {1, "#5197bd"}},
    control = {{0, "#ddfff2"}, {0.035, "#82d2bc"}, {0.10, "#17634f"},
        {0.55, "#12513e"}, {1, "#0a3529"}},
    control_hover = {{0, "#effff7"}, {0.035, "#a0e8cf"}, {0.10, "#1c7159"},
        {0.55, "#176049"}, {1, "#0e4432"}},
    close = {{0, "#fff0e8"}, {0.035, "#edaca0"}, {0.10, "#a83936"},
        {0.55, "#8c2929"}, {1, "#581a21"}},
    close_hover = {{0, "#fff8ef"}, {0.035, "#ffc2ae"}, {0.10, "#bd4238"},
        {0.55, "#a7332d"}, {1, "#742227"}},
    -- Whole-popup surface: no broad pale highlight behind the first menu rows.
    menu = {{0, "#204665"}, {0.45, "#183d5b"}, {1, "#102b43"}},
    blue = {{0, "#d8fbff"}, {0.035, "#83bddb"}, {0.10, "#245a86"},
        {0.50, "#174a77"}, {1, "#0c2b50"}},
    selected = {{0, "#efffff"}, {0.035, "#a8dcf0"}, {0.10, "#286794"},
        {0.50, "#205b89"}, {1, "#123d68"}},
    inactive = {{0, "#ccdde9"}, {0.035, "#91abc1"}, {0.10, "#3a516a"},
        {0.50, "#2e465f"}, {1, "#20344c"}},
    card = {{0, "#527d75"}, {0.01, "#28443c"}, {0.10, "#172d24f5"}, {1, "#09170ff5"}},
    forest = {{0, "#06110df5"}, {0.32, "#123326f5"}, {0.72, "#183e2bf5"}, {1, "#07160ff5"}},
}
function appearance.gradient(name, height)
    return gears.color {type = "linear", from = {0, 0}, to = {0, height}, stops = appearance.stops[name]}
end
function appearance.forest(width)
    return gears.color {type = "linear", from = {0, 0}, to = {width, 0}, stops = appearance.stops.forest}
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
