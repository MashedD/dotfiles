-- Versioned user Quick Launch list, kept outside the Stow-managed config.
local M = {}
local home = os.getenv("HOME") or "."
local MAX_BYTES, MAX_ENTRIES, MAX_ARGUMENTS = 65536, 24, 32
local function expand(path)
    if path == "~" then return home end
    if path:sub(1, 2) == "~/" then return home .. path:sub(2) end
    return path
end
function M.defaults()
    local control_center = home .. "/.local/bin/desktop-control-center"
    local quake_one = home .. "/Games/quake-rerelease/vkquake.sh"
    local quake_two = home .. "/Games/quake2/q2pro.sh"
    return {
        {label = "Terminal", icon = "utilities-terminal", argv = {"kitty"}, enabled = true},
        {label = "Files", icon = "system-file-manager", argv = {"pcmanfm"}, enabled = true},
        {label = "Control Panel", icon = "preferences-system", argv = {control_center}, enabled = true},
        {label = "Finder", icon = "system-run", argv = {"xfce4-appfinder"}, enabled = true},
        {label = "Firefox", icon = "web-browser", argv = {"firefox"}, enabled = true},
        {label = "Quake 1", icon = "applications-games", argv = {quake_one}, enabled = true},
        {label = "Quake 2", icon = "input-gaming", argv = {quake_two}, enabled = true},
        {label = "Sleep", icon = "system-suspend", argv = {"systemctl", "suspend"}, enabled = true},
    }
end

local function read_config(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local contents = file:read(MAX_BYTES + 1)
    file:close()
    if #contents > MAX_BYTES then error("Quick Launch settings file is too large") end
    local lgi = require("lgi")
    local Json = lgi.require("Json", "1.0")
    local parser = Json.Parser()
    if parser:load_from_data(contents, #contents) == false then error("Quick Launch JSON could not be parsed") end
    local root = parser:get_root()
    local object_ok, config = pcall(function() return root and root:get_object() end)
    if not object_ok or not config then error("Quick Launch settings must be a JSON object") end
    if config:get_int_member("version") ~= 1 then error("Unsupported Quick Launch version") end
    local array = config:get_array_member("entries")
    if not array then error("Quick Launch entries are missing") end
    local length = array:get_length()
    if length > MAX_ENTRIES then error("Too many Quick Launch entries") end
    local entries, labels = {}, {}
    for index = 0, length - 1 do
        local node = array:get_element(index)
        local object = node and node:get_object()
        if not object then error("Quick Launch entry must be an object") end
        local label = object:get_string_member("label")
        local icon = object:get_string_member("icon")
        local enabled = object:get_boolean_member("enabled")
        local argv_array = object:get_array_member("argv")
        if type(label) ~= "string" or label:match("^%s*$") or #label > 40
            or type(icon) ~= "string" or #icon > 256 or type(enabled) ~= "boolean"
            or not argv_array then
            error("Quick Launch entry has invalid fields")
        end
        local key = label:lower()
        if labels[key] then error("Duplicate Quick Launch label: " .. label) end
        labels[key] = true
        local argument_count = argv_array:get_length()
        if argument_count < 1 or argument_count > MAX_ARGUMENTS then
            error("Quick Launch command has an invalid number of arguments")
        end
        local argv = {}
        for argument_index = 0, argument_count - 1 do
            local argument = argv_array:get_element(argument_index):get_string()
            if type(argument) ~= "string" or argument == "" or #argument > 4096
                or argument:find("[%z\1-\31\127]") then
                error("Quick Launch command contains an invalid argument")
            end
            argv[#argv + 1] = expand(argument)
        end
        if label:find("[%z\1-\31\127]") or icon:find("[%z\1-\31\127]") then
            error("Quick Launch entry contains a control character")
        end
        entries[#entries + 1] = {label = label, icon = icon, argv = argv, enabled = enabled}
    end
    return entries
end

function M.load()
    local config_home = os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
    M.path = config_home .. "/desktop-control-center/quick-launch.json"
    local ok, entries = pcall(read_config, M.path)
    if ok and entries then return entries end
    if not ok then
        io.stderr:write("Quick Launch settings: " .. tostring(entries) .. "; using defaults\n")
    end
    return M.defaults()
end
return M
