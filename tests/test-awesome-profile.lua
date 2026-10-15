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
local marker={}
ok,err=pcall(p.wrap('object-error',function() error(marker) end,false))
assert(not ok and err==marker)
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
-- Rendering wrappers measure actual paints separately from coalesced requests.
p=fresh();p.phase='measured'
local background={draw=function(_,_,a) now=now+.001;return a,nil,3 end,
    before_draw_children=function() error('draw failed') end,after_draw_children=function() end}
package.loaded['wibox.container.background']=background
p.install_rendering()
a,b,c=background.draw({}, {screen={index=1}},7);assert(a==7 and b==nil and c==3)
ok,err=pcall(background.before_draw_children,{}, {screen={index=1}})
assert(not ok and tostring(err):find('draw failed',1,true))
local scheduled={}
local function drawable()
    local d={widget={fit=function() return 112,112 end,layout=function() return {} end}}
    d._do_redraw=function() d.pending=false;now=now+.002;return 'painted' end
    d.draw=function() if not d.pending then d.pending=true;scheduled[#scheduled+1]=function() return d._do_redraw() end end end
    return {_drawable=d}
end
local s={index=1,panel=drawable(),sidebar=drawable(),sidebar_scrollbar_panel=drawable(),
         sidebar_clock={draw=function() now=now+.001 end}}
screen=setmetatable({}, {__call=function(_,_,previous) if previous==nil then return s end end})
p.bind_rendering()
a,b=s.sidebar._drawable.widget.fit();assert(a==112 and b==112)
assert(type(s.sidebar._drawable.widget.layout())=='table')
s.sidebar._drawable.draw();s.sidebar._drawable.draw()
assert(#scheduled==1 and scheduled[1]()=='painted')
assert(p.buckets['measured:redraw_request.sidebar.screen1'].count==2)
assert(p.buckets['measured:redraw.sidebar.screen1'].count==1)
assert(math.abs(p.buckets['measured:redraw.sidebar.screen1'].total-.002)<1e-8)
assert(#p.intervals==0, 'Nested render scopes must not flood heartbeat overlap tracking')
for i=1,10005 do p.sample('bounded',.1) end
assert(p.buckets['measured:bounded'].count==10005 and #p.buckets['measured:bounded'].values==10000)
assert(math.abs(p.buckets['measured:bounded'].total-1000.5)<1e-6)
print('Awesome private profiler tests passed')
