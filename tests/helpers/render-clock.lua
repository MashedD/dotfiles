-- Real Cairo comparison fixtures; paths and private prototype supplied by Python.
local cairo=require('lgi').cairo
package.loaded.awful={}
package.loaded.gears={}
package.loaded.wibox={widget={base={make_widget=function() return {} end}}}
local baseline=assert(loadfile(arg[1]))()._test_clock()
local candidate=assert(loadfile(arg[2]))()._test_clock()
local function draw(clock,path,w,h,dpi,scale,light,stamp,fractional)
    clock.current_time=stamp
    local surface=cairo.ImageSurface.create(cairo.Format.ARGB32,w*scale,h*scale)
    local _,set=dofile(arg[4]).device_scale(cairo)
    assert(set,'Native device-scale API unavailable')
    set(surface,scale,scale)
    local cr=cairo.Context(surface)
    cr:set_source_rgb(light and 1 or .01,light and 1 or .08,light and 1 or .04);cr:paint()
    if fractional then cr:translate(.25,.25) end
    clock.draw(clock,{dpi=dpi},cr,w,h)
    surface:write_to_png(path);surface:finish()
end
local count=0
for _,size in ipairs({{112,112},{112,104},{128,128},{112,128}}) do
 for _,context in ipairs({{96,1},{144,2}}) do
  for _,light in ipairs({false,true}) do
   for _,stamp in ipairs({{hour=0,min=0,sec=0},{hour=10,min=10,sec=30},{hour=23,min=59,sec=59}}) do
    count=count+1
    local prefix=arg[3]..'/'..count
    draw(baseline,prefix..'-A.png',size[1],size[2],context[1],context[2],light,stamp,false)
    draw(candidate,prefix..'-B.png',size[1],size[2],context[1],context[2],light,stamp,false)
   end
  end
 end
end
-- Unsupported raster transforms remain on the exact direct path.
count=count+1
local stamp={hour=12,min=30,sec=15}
draw(baseline,arg[3]..'/'..count..'-A.png',112,112,96,1,false,stamp,true)
draw(candidate,arg[3]..'/'..count..'-B.png',112,112,96,1,false,stamp,true)
local cache=candidate._face_cache
assert(cache.builds>0 and cache.fallbacks>0 and cache.bytes==0)
cache.destroy();assert(cache.bytes==0 and cache.releases==cache.builds)
print('Clock Cairo fixtures: '..count..' comparisons; peak face bytes='..cache.peak_bytes)
