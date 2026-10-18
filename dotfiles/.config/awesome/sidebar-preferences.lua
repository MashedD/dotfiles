-- User-editable sidebar locations live outside the Stow-managed configuration.
local M = {}
local home = os.getenv("HOME") or "."
local data_home = os.getenv("XDG_DATA_HOME") or (home .. "/.local/share")
local function expand(path)
    path = tostring(path or "")
    if path == "~" then return home end
    if path:sub(1, 2) == "~/" then return home .. path:sub(2) end
    if path:sub(1, 1) ~= "/" then return home .. "/" .. path end
    return path
end
local function expand_argument(argument)
    if argument == "~" then return home end
    if argument:sub(1, 2) == "~/" then return home .. argument:sub(2) end
    return argument
end
local function defaults()
    return {
        weather_label = "Bydgoszcz, Poland", latitude = 53.1235, longitude = 17.9871,
        todo_path = home .. "/Documents/todo.md",
        calendar_path = home .. "/Documents/calendar.md",
        wallpaper_dirs = {data_home .. "/wallpapers", home .. "/Pictures/Wallpapers"},
        editor_command = {}, browser_command = {"firefox", "--new-tab", "{url}"},
    }
end
function M.load()
    local result = defaults()
    local config_home = os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
    M.path = config_home .. "/desktop-control-center/sidebar-preferences"
    local file = io.open(M.path, "r")
    if not file then return result end
    local values, directories, has_directories = {}, {}, false
    local commands = {editor_command = {}, browser_command = {}}
    local has_commands = {}
    for line in file:lines() do
        local key, value = line:match("^([^=]+)=(.*)$")
        if key == "weather_label" or key == "todo_path" or key == "calendar_path" then
            values[key] = value
        elseif key == "latitude" or key == "longitude" then
            values[key] = tonumber(value)
        elseif key == "wallpaper_dirs" then
            has_directories = true
            if value ~= "" then directories[#directories + 1] = expand(value) end
        elseif key == "editor_command" or key == "browser_command" then
            has_commands[key] = true
            if value ~= "" then commands[key][#commands[key] + 1] = expand_argument(value) end
        end
    end
    file:close()
    if values.weather_label and values.weather_label:match("%S") and #values.weather_label <= 100
        and not values.weather_label:find("[%z\1-\31\127]") then
        result.weather_label = values.weather_label
    end
    if values.latitude and values.latitude >= -90 and values.latitude <= 90 then
        result.latitude = values.latitude
    end
    if values.longitude and values.longitude >= -180 and values.longitude <= 180 then
        result.longitude = values.longitude
    end
    for _, key in ipairs({"todo_path", "calendar_path"}) do
        if values[key] and values[key]:match("%S") and not values[key]:find("[%z\1-\31\127]") then
            result[key] = expand(values[key])
        end
    end
    if has_directories and #directories <= 32 then result.wallpaper_dirs = directories end
    for key in pairs(has_commands) do
        local command = commands[key]
        if #command <= 32 and (key ~= "browser_command" or #command > 0) then
            result[key] = command
        end
    end
    return result
end
return M
