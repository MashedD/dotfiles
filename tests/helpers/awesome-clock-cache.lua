-- Private prototype. Production drawing remains unchanged unless the audit gate passes.
local M = {}
local scales=setmetatable({}, {__mode='k'})
function M.device_scale(cairo)
    if scales[cairo]==nil then
        -- lgi 0.9.2 omits these Cairo 1.14 methods. Bind them locally, without
        -- modifying the shared Cairo namespace or any global rendering settings.
        local ok,value=pcall(function()
            local core=require('lgi.core')
            local types=require('lgi.ffi').types
            return {
                core.callable.new {addr=cairo._module.cairo_surface_get_device_scale,ret=types.void,cairo.Surface,
                                   {types.double,dir='out'},{types.double,dir='out'}},
                core.callable.new {addr=cairo._module.cairo_surface_set_device_scale,ret=types.void,cairo.Surface,
                                   types.double,types.double},
            }
        end)
        scales[cairo]=ok and value or false
    end
    local value=scales[cairo]
    if value then return value[1],value[2] end
end
function M.new(cairo, face, options)
    options = options or {}
    local surface, key, bytes, disposed
    local cache = {builds=0, releases=0, bytes=0, peak_bytes=0, hits=0, fallbacks=0}
    local function release()
        if surface then
            pcall(surface.finish, surface)
            cache.releases=cache.releases+1
            if options.event then options.event('release',bytes,0) end
        end
        surface,key,bytes=nil,nil,nil
        cache.bytes=0
    end
    cache.clear=release
    function cache.destroy() disposed=true;release() end
    function cache.paint(context, cr, width, height)
        if disposed then return false end
        if width<=0 or height<=0 then release(); return false end
        local target=cr:get_target()
        local got,sx,sy=pcall(function() return target:get_device_scale() end)
        if not got then
            local get=M.device_scale(cairo)
            if not get then release();cache.fallbacks=cache.fallbacks+1;face(cr,width,height);return true end
            sx,sy=get(target)
        end
        local matrix=cr:get_matrix()
        -- A raster face cannot preserve fractional/rotated target rasterization.
        -- Leave those cases on the original direct drawing path.
        local function integer(value) return math.abs(value-math.floor(value+.5))<1e-8 end
        if sx<=0 or sy<=0 or matrix.xx~=1 or matrix.yy~=1 or matrix.xy~=0 or matrix.yx~=0
            or not integer(matrix.x0*sx) or not integer(matrix.y0*sy) then
            release();cache.fallbacks=cache.fallbacks+1;face(cr,width,height);return true
        end
        local font=cr:get_font_options()
        local ok_variations,variations=pcall(function() return font:get_variations() end)
        local current=table.concat({width,height,context and context.dpi or 96,sx,sy,
            tostring(font:get_antialias()),tostring(font:get_subpixel_order()),
            tostring(font:get_hint_style()),tostring(font:get_hint_metrics()),ok_variations and tostring(variations) or ''},':')
        if current~=key then
            release()
            local now=options.now or os.clock
            local started=options.event and now()
            local made
            local ok,created=pcall(function()
                local result=cairo.ImageSurface.create(cairo.Format.ARGB32,math.ceil(width*sx),math.ceil(height*sy))
                made=result
                local status=result.status
                if status~=nil and status~='SUCCESS' and status~=(cairo.Status and cairo.Status.SUCCESS) then
                    error('Face surface allocation failed',0)
                end
                local scaled=pcall(function() result:set_device_scale(sx,sy) end)
                if not scaled then
                    local _,set=M.device_scale(cairo)
                    if not set then error('Device scale unavailable',0) end
                    set(result,sx,sy)
                end
                local paint=cairo.Context(result)
                paint:set_font_options(font)
                face(paint,width,height)
                return result
            end)
            if not ok or not created then
                if made then pcall(function() made:finish() end) end
                cache.fallbacks=cache.fallbacks+1;face(cr,width,height);return true
            end
            surface,key=created,current
            bytes=surface:get_stride()*surface:get_height()
            cache.builds=cache.builds+1;cache.bytes=bytes;cache.peak_bytes=math.max(cache.peak_bytes,bytes)
            if options.event then options.event('build',bytes,now()-started) end
        else cache.hits=cache.hits+1 end
        cr:save()
        cr:set_source_surface(surface,0,0);cr:paint()
        cr:restore()
        -- Static painting set this in the original path; hands depend on it.
        cr:set_line_cap(cairo.LineCap.ROUND)
        return true
    end
    return cache
end
return M
