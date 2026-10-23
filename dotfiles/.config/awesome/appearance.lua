-- Only allow bundled profile names; the mutable selection is not executable Lua.
local directory = debug.getinfo(1, "S").source:sub(2):match("^(.*)/") or "."
local state = os.getenv("XDG_STATE_HOME") or ((os.getenv("HOME") or ".") .. "/.local/state")
local file = io.open(state .. "/awesome/theme", "r")
local selected = file and file:read("*l") or "aero"
if file then file:close() end
if selected ~= "aero" and selected ~= "night-circuit" then selected = "aero" end
local appearance = dofile(directory .. "/themes/" .. selected .. ".lua")
appearance.name = selected
appearance.cyberpunk = selected == "night-circuit"
-- Shared widgets use semantic surfaces, with original Aero fallbacks.
appearance.stops.panel = appearance.stops.panel or appearance.stops.blue
appearance.stops.section = appearance.stops.section or appearance.stops.blue
appearance.fonts.telemetry = appearance.fonts.telemetry or appearance.fonts.title
appearance.palette.urgency = appearance.palette.urgency or appearance.palette.neon
appearance.palette.urgency_bg = appearance.palette.urgency_bg or "#001a00"
return appearance
