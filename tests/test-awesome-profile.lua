-- lua tests/test-awesome-profile.lua: fake clock/spawns, no desktop calls.
local now, timer_callback = 0, nil
package.loaded.lgi = {GLib={get_monotonic_time=function() return now*1000000 end}}
package.loaded.gears = {timer=function(options)
    timer_callback=options.callback
    return {stop=function() timer_callback=nil end}
end}
local launches=0
package.loaded.awful = {spawn={easy_async=function(argv, callback)
    launches=launches+1; callback('value','detail','exit',0); return 123
end}}
local function fresh() return dofile('tests/helpers/awesome-profile.lua') end
local p=fresh()
local fn=p.wrap('return', function(a) now=now+0.002; return a,nil,3 end)
local a,b,c=fn(1); assert(a==1 and b==nil and c==3)
local ok,err=pcall(p.wrap('error', function() error('fixture failure') end))
assert(not ok and tostring(err):find('fixture failure',1,true))
p.count('startup-only')
p.phase='warmup'; p.count('warmup-only')
p.begin(); p.count('measured-only')
local calls=0
local fetch=p.fetch('fixture', function(done) now=now+0.003; done('parsed',nil); return 9 end)
assert(fetch(function(value, error) assert(value=='parsed' and error==nil); calls=calls+1 end)==9)
assert(calls==1)
local late
p.fetch('async', function(done) late=done end)(function() calls=calls+1 end)
now=now+0.05; late(nil,'failed'); assert(calls==2)
-- Duplicate completion remains visible to the original consumer, not hidden by profiling.
late(nil,'failed'); assert(calls==3)
assert(p.buckets['measured:latency.async'].count==1)
p.install_spawn()
assert(package.loaded.awful.spawn.easy_async({'timeout','--kill-after=2s','20s','/private/wpctl'},
    function(out,stderr,reason,code) assert(out=='value' and stderr=='detail' and reason=='exit' and code==0) end)==123)
assert(launches==1 and p.buckets['measured:spawn.wpctl'].count==1)
now=now+0.2; timer_callback()
local output=p.finish()
assert(output:find('startup:startup-only',1,true))
assert(output:find('warmup:warmup-only',1,true))
assert(output:find('measured:measured-only',1,true))
assert(not output:find('value',1,true) and not output:find('detail',1,true))
assert(timer_callback==nil)
-- Fetch completion crossing the measurement boundary is not charged to measured latency.
p=fresh(); p.fetch('crossing',function(done) late=done end)(function() end)
p.begin(); late('value'); assert(p.buckets['measured:latency.crossing']==nil)
print('Awesome private profiler tests passed')
