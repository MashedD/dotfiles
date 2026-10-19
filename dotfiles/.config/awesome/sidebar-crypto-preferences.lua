-- User-managed token/currency formatting for the Awesome sidebar only.
local M = {}
local home = os.getenv("HOME") or "."
local MAX_BYTES, MAX_TOKENS = 65536, 12
function M.defaults()
    return {
        version = 1, currency = "USD", currency_symbol = "$",
        decimal_separator = ",", thousands_separator = ".",
        click_action_enabled = true, click_command = {},
        tokens = {
            {symbol = "BTC", id = "bitcoin", decimals = 0},
            {symbol = "ETH", id = "ethereum", decimals = 0},
            {symbol = "LTC", id = "litecoin", decimals = 2},
        },
    }
end
local function read_config(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local text = file:read(MAX_BYTES + 1)
    file:close()
    if #text > MAX_BYTES then error("Crypto settings file is too large") end
    local Json = require("lgi").require("Json", "1.0")
    local parser = Json.Parser()
    if parser:load_from_data(text, #text) == false then error("Crypto settings JSON could not be parsed") end
    local root = parser:get_root()
    local object_ok, config = pcall(function() return root and root:get_object() end)
    if not object_ok or not config or config:get_int_member("version") ~= 1 then
        error("Crypto settings have an unsupported format")
    end
    local currency = config:get_string_member("currency")
    local currency_symbol = config:get_string_member("currency_symbol")
    local decimal_separator = config:get_string_member("decimal_separator")
    local thousands_separator = config:get_string_member("thousands_separator")
    local tokens_array = config:get_array_member("tokens")
    if type(currency) ~= "string" or not currency:match("^[A-Za-z][A-Za-z][A-Za-z]$")
        or type(currency_symbol) ~= "string" or currency_symbol == "" or #currency_symbol > 8
        or currency_symbol:match("^%d") or currency_symbol:find("%s")
        or currency_symbol:find("%c")
        or (decimal_separator ~= "." and decimal_separator ~= ",")
        or (thousands_separator ~= "." and thousands_separator ~= ",")
        or decimal_separator == thousands_separator or not tokens_array then
        error("Crypto settings contain invalid currency or formatting")
    end
    local click_action_enabled, click_command = true, {}
    if config:has_member("click_action_enabled") then
        click_action_enabled = config:get_boolean_member("click_action_enabled")
    end
    if type(click_action_enabled) ~= "boolean" then error("Invalid crypto click action setting") end
    if config:has_member("click_command") then
        local command_array = config:get_array_member("click_command")
        if not command_array or command_array:get_length() > 32 then error("Invalid crypto click command") end
        for index = 0, command_array:get_length() - 1 do
            local node = command_array:get_element(index)
            local argument = node and node:get_string()
            if type(argument) ~= "string" or #argument > 4096 or argument:find("%c") then
                error("Invalid crypto click command argument")
            end
            if argument == "~" then argument = home
            elseif argument:sub(1, 2) == "~/" then argument = home .. argument:sub(2) end
            click_command[#click_command + 1] = argument
        end
    end
    if click_command[1] and click_command[1]:match("^%s*$") then error("Empty crypto click executable") end
    local length = tokens_array:get_length()
    if length > MAX_TOKENS then error("Too many configured crypto tokens") end
    local result = {version = 1, currency = currency:upper(), currency_symbol = currency_symbol,
        decimal_separator = decimal_separator, thousands_separator = thousands_separator,
        click_action_enabled = click_action_enabled, click_command = click_command, tokens = {}}
    local symbols, ids = {}, {}
    for index = 0, length - 1 do
        local node = tokens_array:get_element(index)
        local token = node and node:get_object()
        if not token then error("Crypto token must be an object") end
        local symbol = token:get_string_member("symbol")
        local coin_id = token:get_string_member("id")
        local decimals = token:get_int_member("decimals")
        if type(symbol) ~= "string" or not symbol:match("^[A-Z0-9]+$")
            or #symbol > 10 or type(coin_id) ~= "string"
            or not coin_id:match("^[a-z0-9][a-z0-9-]*$") or #coin_id > 64
            or decimals < 0 or decimals > 8 then
            error("Crypto token contains invalid fields")
        end
        if symbols[symbol] or ids[coin_id] then error("Duplicate crypto token or CoinGecko ID") end
        symbols[symbol], ids[coin_id] = true, true
        result.tokens[#result.tokens + 1] = {symbol = symbol, id = coin_id, decimals = decimals}
    end
    return result
end
function M.load()
    local config_home = os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
    M.path = config_home .. "/desktop-control-center/crypto-prices.json"
    local ok, result = pcall(read_config, M.path)
    if ok and result then return result end
    if not ok then io.stderr:write("Crypto sidebar settings: " .. tostring(result) .. "; using defaults\n") end
    return M.defaults()
end
return M
