-- Fake Cairo cache/lifetime tests; no lgi, display, or wall-clock sleeps.
local M=dofile('tests/helpers/awesome-clock-cache.lua')
local faces,finishes,paints,allocations=0,0,0,0
local scale,font_option=1,'default'
local matrix={xx=1,yy=1,xy=0,yx=0,x0=0,y0=0}
local font={get_antialias=function() return font_option end,get_subpixel_order=function() return 0 end,
    get_hint_style=function() return 0 end,get_hint_metrics=function() return 0 end,get_variations=function() return nil end}
local function context(target)
    return {get_target=function() return target end,get_matrix=function() return matrix end,
        get_font_options=function() return font end,set_font_options=function() end,
        save=function() end,restore=function() end,set_source_surface=function() end,
        paint=function() paints=paints+1 end,set_line_cap=function() end}
end
local cairo={Format={ARGB32=0},LineCap={ROUND=1},ImageSurface={}}
cairo.ImageSurface.create=function(_,w,h)
    allocations=allocations+1
    return {set_device_scale=function() end,get_stride=function() return w*4 end,get_height=function() return h end,
        finish=function() finishes=finishes+1 end}
end
cairo.Context=context
local cr=context({get_device_scale=function() return scale,scale end})
local events={}
local cache=M.new(cairo,function() faces=faces+1 end,{now=function() return 0 end,
    event=function(kind,bytes) events[#events+1]={kind,bytes} end})
assert(cache.paint({dpi=96},cr,112,112))
assert(cache.builds==1 and cache.bytes==112*112*4 and faces==1)
cache.paint({dpi=96},cr,112,112);assert(faces==1 and cache.hits==1)
cache.paint({dpi=96},cr,128,112);assert(faces==2 and finishes==1)
cache.paint({dpi=144},cr,128,112);assert(faces==3 and finishes==2)
scale=2;cache.paint({dpi=144},cr,128,112);assert(cache.bytes==256*224*4)
font_option='gray';cache.paint({dpi=144},cr,128,112);assert(cache.builds==5)
local second=M.new(cairo,function() faces=faces+1 end)
second.paint({dpi=144},cr,128,112)
assert(second.bytes==cache.bytes and second.builds==1)
cache.destroy();assert(cache.bytes==0 and second.bytes>0)
local old=allocations
assert(not cache.paint({dpi=96},cr,112,112) and allocations==old)
cache.destroy();assert(cache.releases==cache.builds)
assert(not second.paint({},cr,0,112) and second.bytes==0)
matrix.x0=.25;second.paint({},cr,112,112);assert(second.fallbacks==1 and second.bytes==0)
matrix.x0=0;matrix.xy=.1;second.paint({},cr,112,112);assert(second.fallbacks==2)
matrix.xy=0
local create=cairo.ImageSurface.create
cairo.ImageSurface.create=function() error('allocation unavailable') end
assert(second.paint({},cr,112,112) and second.fallbacks==3 and second.bytes==0)
cairo.ImageSurface.create=create
second.paint({},cr,112,112);second.clear();second.clear()
assert(second.bytes==0 and second.releases==second.builds)
assert(#events>=2 and events[1][1]=='build')
cairo.ImageSurface.create=function(...)
    local result=create(...);result.status='NO_MEMORY';return result
end
assert(second.paint({},cr,112,112) and second.bytes==0 and second.fallbacks==4)
cairo.ImageSurface.create=create
local unavailable=context({get_device_scale=function() error('unbound device scale') end})
assert(second.paint({},unavailable,112,112) and second.bytes==0 and second.fallbacks==5)
print('Awesome private clock cache tests passed')
