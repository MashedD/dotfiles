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

-- Existing screens are not rebroadcast on subscribe or on unchanged results.
local count_service, pending = module.new {
    now = function() return now end,
    timer = function(options) options.stop = function(self) self.stopped = true end; return options end,
}
count_service.define("values", 10, function(done) pending = done end)
local count_a, count_b = 0, 0
local stop_a = count_service.subscribe("values", function() count_a = count_a + 1 end)
assert(count_a == 1)
pending({level = 5, flags = {muted = false}, now = 1})
assert(count_a == 2)
local stop_b = count_service.subscribe("values", function() count_b = count_b + 1 end)
assert(count_a == 2 and count_b == 1, "new subscriber gets current state; existing listener is quiet")
count_service.refresh("values")
pending({level = 5, flags = {muted = false}, now = 2})
assert(count_a == 2 and count_b == 1, "identical values and sample timestamps only advance freshness")
now = now + 25
count_service.refresh("values")
assert(count_a == 3 and count_b == 2, "fresh to stale transition notifies exactly once")
pending({level = 5, flags = {muted = false}})
assert(count_a == 4 and count_b == 3, "stale recovery notifies exactly once")
count_service.refresh("values")
pending(nil, "down")
assert(count_a == 5 and count_b == 4)
count_service.refresh("values")
pending(nil, "down")
assert(count_a == 5 and count_b == 4, "repeated error is not rebroadcast")
count_service.refresh("values")
pending(nil, "different")
assert(count_a == 6 and count_b == 5, "different error notifies")
stop_a:stop(); stop_b:stop()

-- Optional fetch cancellation follows the final subscriber and generation only.
local cancelled, finishes, cancel_logs = 0, {}, {}
local cancellable = module.new {
    now=function() return now end,
    timer=function(options) options.stop=function() end; return options end,
    log=function(err) cancel_logs[#cancel_logs+1]=err end,
}
cancellable.define('battery',1,function(done)
    finishes[#finishes+1]=done
    return function() cancelled=cancelled+1 end
end)
local ca=cancellable.subscribe('battery',function() end)
local cb=cancellable.subscribe('battery',function() end)
cancellable.refresh('battery'); assert(#finishes==1)
ca:stop(); assert(cancelled==0)
cb:stop(); cb:stop(); assert(cancelled==1)
finishes[1]({capacity=99}); assert(cancellable.state('battery').value==nil)
ca=cancellable.subscribe('battery',function() end)
finishes[1]({capacity=99}); assert(cancellable.collectors.battery.pending)
finishes[2]({capacity=0}); assert(cancellable.state('battery').value.capacity==0)
ca:stop(); assert(cancelled==1, 'completed fetch has no outstanding cancellation')
ca=cancellable.subscribe('battery',function() end)
now=now+3
cancellable.refresh('battery')
assert(#finishes==3 and cancellable.state('battery').stale, 'slow read becomes stale without overlapping')
assert(cancellable.state('battery').value.capacity==0, 'pending read retains the last sample')
ca:stop(); assert(cancelled==2)
finishes[3]({capacity=99}); assert(cancellable.state('battery').value.capacity==0)
cancellable.define('sync',1,function(done) done(1); return function() error('already finished') end end)
ca=cancellable.subscribe('sync',function() end); ca:stop(); assert(#cancel_logs==0)
cancellable.define('bad-cancel',1,function() return function() error('cancel failed') end end)
ca=cancellable.subscribe('bad-cancel',function() end); ca:stop(); ca:stop(); assert(#cancel_logs==1)

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

assert(not module.parse_codex('C* 5h 84%@Sat 13:46 7d 33%@Wed 06:41'))
assert(not module.parse_crypto('STALE BTC $1 ETH $2 LTC $3'))
local codex_sample='codex-v1\tfresh\t100\tC 5h 0%@Sat 13:46 7d 100%@Wed 06:41\tA & B · C < D'
local sample=assert(module.parse_codex_sample(codex_sample,170))
assert(sample.five==0 and sample.week==100 and sample.source_updated==100)
assert(module.parse_codex_sample(codex_sample,100+module.SOURCE_MAX_AGE-1))
assert(not module.parse_codex_sample(codex_sample,100+module.SOURCE_MAX_AGE))
assert(not module.parse_codex_sample(codex_sample,99))
assert(not module.parse_codex_sample(codex_sample:gsub('fresh','stale'),170))
assert(not module.parse_codex_sample(codex_sample:gsub('C 5h','C* 5h'),170))
assert(not module.parse_codex_sample('C 5h 84%@Sat 13:46 7d 33%@Wed 06:41',170))
assert(module.parse_crypto_sample('crypto-v1\tfresh\t100\tBTC $1 ETH $2 LTC $3',170).source_updated==100)
assert(not module.parse_crypto_sample('crypto-v1\tstale\t100\tBTC $1 ETH $2 LTC $3',170))
local source_now=170
local sourced=module.new{now=function() return source_now end,timer=function() return {stop=function() end} end}
sourced.define('quota',60,function(done) done({remaining=0,source_updated=100}) end)
local source_handle=sourced.subscribe('quota',function() end)
assert(sourced.state('quota').updated==100 and not sourced.state('quota').stale)
source_now=99;assert(sourced.state('quota').stale,'Future confirmation is not fresh')
source_now=220;sourced.refresh('quota')
assert(sourced.state('quota').updated==100 and sourced.state('quota').stale,'Reading old cache cannot renew source age')
source_handle.stop()

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
