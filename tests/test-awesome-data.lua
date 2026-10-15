-- Deterministic, X11-free tests: lua tests/test-awesome-data.lua
local module = dofile("dotfiles/.config/awesome/sidebar-data.lua")
local now, timers, callbacks = 100, {}, {}
local service = module.new {now = function() return now end, timer = function(options)
    options.stop = function(self) self.stopped = true end
    timers[#timers + 1] = options
    return options
end}
service.define("test", 60, function(done) callbacks[#callbacks + 1] = done end)
local a, b
local first = service.subscribe("test", function(state) a = state end)
local second = service.subscribe("test", function(state) b = state end)
assert(#timers == 1 and #callbacks == 1 and a == b)
assert(not a.value and not a.updated)
service.refresh("test")
assert(#callbacks == 1, "pending request must not overlap")
callbacks[1](nil, "Invalid response")
assert(a.error and not a.value and not a.updated)
service.refresh("test")
callbacks[2]({remaining = 0})
assert(a.value.remaining == 0 and a.updated == 100 and not a.error and not a.stale)
now = 160
service.refresh("test")
callbacks[3](nil, "Command failed")
assert(a.value.remaining == 0 and a.updated == 100 and a.stale)
now = 170
service.refresh("test")
callbacks[4]({remaining = 84})
assert(a.value.remaining == 84 and a.updated == 170 and not a.stale and not a.error)
now = 290
assert(service.state("test").stale, "two intervals without success is stale")
first:stop()
assert(not timers[1].stopped)
service.refresh("test")
second:stop()
assert(timers[1].stopped and not service.collectors.test.pending)
callbacks[5]({remaining = 1})
assert(a.value.remaining == 84, "late results from a disposed generation must be ignored")
local third = service.subscribe("test", function(state) a = state end)
assert(#timers == 2 and #callbacks == 6)
callbacks[5]({remaining = 2})
assert(a.value.remaining == 84)
callbacks[6]({remaining = 33})
assert(a.value.remaining == 33 and not a.stale)
third:stop(); third:stop()
assert(timers[2].stopped)

assert(module.parse_weather('{"current":{"temperature_2m":12.3,"apparent_temperature":11,"weather_code":3,"wind_speed_10m":9}}').temperature == 12.3)
assert(not module.parse_weather('{"current":{"temperature_2m":12}}'))
assert(not module.parse_weather('bad response'))
local prices = module.parse_crypto('#[fg=green]BTC $97.123 ETH $3.456 LTC $123,45')
assert(prices.BTC == '97.123' and prices.LTC == '123,45')
assert(not module.parse_crypto('BTC $1 ETH $2'))
assert(not module.parse_crypto('BTC <bad> ETH $2 LTC $3'))
local quotas = module.parse_codex('C 5h 0%@Sat 13:46 7d 100%@Wed 06:41\tA & B · C < D')
assert(quotas.five == 0 and quotas.week == 100 and quotas.resets == 'A & B\nC < D')
assert(not module.parse_codex('C 5h 101%@Sat 13:46 7d 33%@Wed 06:41'))
assert(not module.parse_codex('C 5h unavailable 7d unavailable'))

-- Exercise the real command adapter with a mocked Awesome runtime.
awesome = {}
package.preload.gears = function() return {timer = function() end} end
local argv, callback
package.preload.awful = function() return {spawn = {easy_async = function(command, cb)
    argv, callback = command, cb
    return 42
end}} end
package.preload.lgi = function() return {Gio = {}} end
local adapter = dofile("dotfiles/.config/awesome/sidebar-data.lua")
local result, failure
adapter.command({"mock-helper", "--sidebar"}, module.parse_codex, function(value, err)
    result, failure = value, err
end)
assert(table.concat(argv, ' ') == 'timeout --kill-after=2s 20s mock-helper --sidebar')
callback('', '', 'exit', 124)
assert(not result and failure == 'Request timed out')
callback('invalid', '', 'exit', 0)
assert(not result and failure == 'Invalid response')
callback('C 5h 0%@Sat 13:46 7d 33%@Wed 06:41', '', 'exit', 0)
assert(result.five == 0 and not failure)
require('awful').spawn.easy_async = function() return 'spawn failed' end
adapter.command({'missing'}, function() return true end, function(value, err) result, failure = value, err end)
assert(not result and failure == 'spawn failed')
print('Awesome data tests passed')
