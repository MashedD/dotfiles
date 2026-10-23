-- Deterministic, X11-free tests: lua tests/test-awesome-data.lua
local module = dofile("dotfiles/.config/awesome/sidebar-data.lua")
local market_sample = module.parse_markets("markets-v1\t123\nquote\tEURPLN\t4.1234\nquote\tUSDPLN\t3.9981\nquote\tXAU\t3021.5\nquote\tXAG\t31.25\n")
assert(market_sample and market_sample.updated == 123 and market_sample.EURPLN == 4.1234
    and market_sample.USDPLN == 3.9981 and market_sample.XAU == 3021.5 and market_sample.XAG == 31.25)
assert(module.parse_markets("invalid\n") == nil)
assert(module.parse_markets("markets-v1\t1\nquote\tEURPLN\t0\n") == nil)
assert(module.parse_markets("markets-v1\t1\nquote\tEURPLN\t4.1\nquote\tEURPLN\t4.2\n") == nil)
local weather_url = module.weather_url(41.4034, 2.1740)
assert(weather_url:find("latitude=41.403400", 1, true)
    and weather_url:find("longitude=2.174000", 1, true)
    and weather_url:find("timezone=auto", 1, true), "weather request uses configured coordinates")
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

-- Fast stats and slow battery/storage probes have independent shared timers and failures.
local independent_now, fast_done, power_done, power_cancels = 1000, nil, nil, 0
local independent_timers={}
local independent=module.new {
    now=function() return independent_now end,
    timer=function(options)
        local timer={timeout=options.timeout,callback=options.callback,stopped=false}
        function timer:stop() self.stopped=true end
        independent_timers[#independent_timers+1]=timer
        return timer
    end,
}
independent.define('stats',1,function(done) fast_done=done end)
independent.define('power',30,function(done)
    power_done=done
    return function() power_cancels=power_cancels+1 end
end)
local fast_a,fast_b,power_a,power_b=0,0,0,0
local stop_fast_a=independent.subscribe('stats',function() fast_a=fast_a+1 end)
local stop_fast_b=independent.subscribe('stats',function() fast_b=fast_b+1 end)
local stop_power_a=independent.subscribe('power',function() power_a=power_a+1 end)
local stop_power_b=independent.subscribe('power',function() power_b=power_b+1 end)
assert(#independent_timers==2 and independent_timers[1].timeout==1
    and independent_timers[2].timeout==30)
assert(independent.collectors.stats.requests==1 and independent.collectors.power.requests==1)
fast_done({cpu=5,network=10})
power_done({capacity=80,root_free=500})
assert(independent.state('stats').value.cpu==5 and independent.state('power').value.capacity==80)
assert(fast_a==2 and fast_b==2 and power_a==2 and power_b==2)
independent_now=1030
assert(independent.state('stats').stale and not independent.state('power').stale,
    'Fast and slow collectors must use independent freshness windows')
independent.refresh('stats'); fast_done({cpu=6,network=12})
assert(not independent.state('stats').stale and independent.state('power').value.capacity==80,
    'Fast refresh succeeds independently of the slow collector')
independent.refresh('power'); power_done(nil,'battery unavailable')
assert(independent.state('power').stale and independent.state('power').value.root_free==500)
assert(not independent.state('stats').stale and independent.state('stats').value.cpu==6,
    'Slow collector errors must not block fast status')
independent.refresh('power')
stop_fast_a:stop(); stop_power_a:stop()
assert(not independent_timers[1].stopped and not independent_timers[2].stopped)
stop_fast_b:stop(); stop_power_b:stop()
assert(independent_timers[1].stopped and independent_timers[2].stopped and power_cancels==1)
power_done({capacity=99})
assert(independent.state('power').value.capacity==80,
    'Late slow results after teardown must be ignored')

assert(module.parse_weather('{"current":{"temperature_2m":12.3,"apparent_temperature":11,"weather_code":3,"wind_speed_10m":9}}').temperature == 12.3)
assert(not module.parse_weather('{"current":{"temperature_2m":12}}'))
assert(not module.parse_weather('bad response'))
local prices = module.parse_crypto('#[fg=green]BTC $97.123 ETH $3.456 LTC $123,45')
assert(prices.BTC == '97.123' and prices.LTC == '123,45')
assert(module.parse_crypto('BTC $1 ETH $2').BTC == '1') -- Configured lists may contain any number of tokens.
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
local empty_crypto = assert(module.parse_crypto_sample('crypto-v1\tfresh\t100\t',170))
assert(empty_crypto.source_updated == 100 and empty_crypto.BTC == nil)
assert(not module.parse_crypto_sample('crypto-v1\tstale\t100\tBTC $1 ETH $2 LTC $3',170))
local news_snapshot = table.concat({
    'news-v2\t2\t100\t110',
    'category\tgeneral\tGeneral',
    'category\tlocal-news\tLocal%20News',
    'feed\t0123456789abcdef\tgeneral\tWykop%20%26%20friends\t\t100',
    'item\t0123456789abcdef0123456789abcdef\tgeneral\tWykop\t90\t0\tHello%20%26%20World\tLine%201%20%26%20line%202\thttps%3A%2F%2Fexample.test%2Fstory',
    'item\tfedcba9876543210fedcba9876543210\tremoved-category\tOld%20feed\t80\t1\tArchived\tRetained\t',
}, '\n') .. '\n'
local parsed_news = assert(module.parse_news(news_snapshot))
assert(parsed_news.revision == 2 and parsed_news.unread == 1 and parsed_news.source_updated == 100)
assert(parsed_news.feeds[1].label == 'Wykop & friends')
assert(parsed_news.categories[2].id == 'local-news' and parsed_news.categories[2].label == 'Local News')
assert(parsed_news.items[1].title == 'Hello & World' and parsed_news.items[1].summary == 'Line 1 & line 2')
assert(parsed_news.items[1].url == 'https://example.test/story' and not parsed_news.items[1].read)
assert(parsed_news.items[2].category == 'removed-category', 'archived stories survive category removal')
assert(not module.parse_news('news-v2\\t1\\t1\\t1\\nitem\\tbad\\n'))
local revision_now, revision_done = 50, nil
local revision_service = module.new {
    now = function() return revision_now end,
    timer = function(options) options.stop = function() end; return options end,
}
revision_service.define('news', 1800, function(done) revision_done = done end, 3600)
local revision_state
local revision_handle = revision_service.subscribe('news', function(state) revision_state = state end)
assert(revision_service.publish('news', {revision=2, source_updated=40, unread=0}))
revision_done({revision=1, source_updated=30, unread=3})
assert(revision_state.value.revision == 2 and revision_state.value.unread == 0,
    'late helper snapshots must not roll back newer read-state actions')
revision_handle.stop()
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
