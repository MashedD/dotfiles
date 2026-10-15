-- Shared square Aero/Win98 surfaces. Text sits below the narrow glass highlight.
local gears = require("gears")
local appearance = {}
appearance.palette = {
    bg = "#07110df5", card = "#101a15f5", line = "#446a62",
    bevel_light = "#73a79f", bevel_shadow = "#020805",
    text = "#e0eee7", muted = "#b7c8bd", teal = "#9cddd4",
    green = "#a8f0bd", neon = "#00ff41", amber = "#ffd36e", red = "#ff8e89",
    title = "#f2fffb", inactive = "#d6e7e3", minimized = "#c1d1dd",
    active_border = "#b4e8ff", inactive_border = "#527797",
}
appearance.fonts = {body = "Microsoft Sans Serif 8", title = "Segoe UI bold 9"}
appearance.stops = {
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
