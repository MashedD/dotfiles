-- User-configured currency pairs; gold and silver are always included.
local M = {}
local home = os.getenv("HOME") or "."
local config_home = os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
local allowed = {USD=true, EUR=true, PLN=true, GBP=true, CHF=true, JPY=true,
    CAD=true, AUD=true, NZD=true, SEK=true, NOK=true, DKK=true, CZK=true, HUF=true}
function M.defaults()
    return {pairs = {{base="EUR",quote="PLN"},{base="USD",quote="PLN"}}}
end
function M.load()
    local defaults = M.defaults()
    local file = io.open(config_home .. "/desktop-control-center/market-pairs.json", "r")
    if not file then return defaults end
    local text = file:read(65537)
    file:close()
    if not text or #text > 65536 then return defaults end
    local ok, result = pcall(function()
        local Json = require("lgi").require("Json", "1.0")
        local parser = Json.Parser()
        if parser:load_from_data(text, #text) == false then error("invalid JSON") end
        local root = parser:get_root():get_object()
        if root:get_int_member("version") ~= 1 then error("unsupported version") end
        local array = root:get_array_member("pairs")
        if not array or array:get_length() > 8 then error("too many pairs") end
        local pairs, seen = {}, {}
        for i = 0, array:get_length() - 1 do
            local pair = array:get_element(i):get_object()
            local base, quote = pair:get_string_member("base"), pair:get_string_member("quote")
            local key = base .. "/" .. quote
            if not allowed[base] or not allowed[quote] or base == quote or seen[key] then error("invalid pair") end
            seen[key] = true
            pairs[#pairs + 1] = {base=base, quote=quote}
        end
        return {pairs=pairs}
    end)
    if ok then return result end
    io.stderr:write("Market sidebar settings: " .. tostring(result) .. "; using defaults\n")
    return defaults
end
return M
