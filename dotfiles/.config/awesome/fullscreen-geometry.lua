-- Fullscreen has its own return state: Awesome 4.3 otherwise shares the
-- native "maximize" history slot for fullscreen and maximization.
local M = {}
function M.new(runtime)
    local saved = setmetatable({}, {__mode='k'})
    local applying = setmetatable({}, {__mode='k'})
    local active = setmetatable({}, {__mode='k'})
    local queued = setmetatable({}, {__mode='k'})
    local fit = setmetatable({}, {__mode='k'})
    local engine = {}
    local function copy(g)
        return {x=g.x, y=g.y, width=g.width, height=g.height}
    end
    local function same(a,b)
        return a.x==b.x and a.y==b.y and a.width==b.width and a.height==b.height
    end
    local function bounded(g,a,border)
        g.width=math.min(g.width,math.max(1,a.width-2*border))
        g.height=math.min(g.height,math.max(1,a.height-2*border))
        g.x=math.max(a.x,math.min(g.x,a.x+a.width-g.width-2*border))
        g.y=math.max(a.y,math.min(g.y,a.y+a.height-g.height-2*border))
        return g
    end
    local function guarded(c, fn)
        if applying[c] then return end
        applying[c]=true
        local result=table.pack(xpcall(fn, debug.traceback))
        applying[c]=nil
        if not result[1] then error(result[2],0) end
        return table.unpack(result,2,result.n)
    end
    local function fullscreen(c)
        runtime.placement.maximize(c, {honor_workarea=false, honor_padding=false,
            ignore_border_width=true, zap_border_width=true, store_geometry=false})
    end
    local function refit(c)
        if c.fullscreen then
            fullscreen(c)
        elseif c.maximized then
            runtime.native(c,'maximized',{store_geometry=false})
        else
            if c.maximized_horizontal then runtime.native(c,'maximized_horizontal',{store_geometry=false}) end
            if c.maximized_vertical then runtime.native(c,'maximized_vertical',{store_geometry=false}) end
        end
    end
    function engine.refit(c)
        if not c.valid then return end
        return guarded(c,function()
            refit(c)
            local previous=fit[c]
            if not c.fullscreen then fit[c]=nil end
            if previous and not c.fullscreen and not c.maximized
                and not c.maximized_horizontal and not c.maximized_vertical then
                local screen=c.screen
                if previous==true or previous.screen~=screen or not same(previous.workarea,screen.workarea) then
                    local a=screen.workarea
                    -- Apply position and size together: resizing an off-screen
                    -- rectangle first can make Awesome choose another monitor.
                    c:geometry(bounded(c:geometry(),a,c.border_width))
                    if c.screen~=screen then c.screen=screen end
                    runtime.placement.no_offscreen(c,{honor_workarea=true,screen=screen})
                end
            end
        end)
    end
    function engine.queue_refit(c)
        if queued[c] then return end
        queued[c]=true
        local ok,err=pcall(runtime.delay,function()
            queued[c]=nil
            if c.valid then engine.refit(c) end
        end)
        if not ok then queued[c]=nil; error(err,0) end
    end
    function engine.handle(c,context,hints)
        if applying[c] then return end
        if context~='fullscreen' then return runtime.native(c,context,hints) end
        return guarded(c,function()
            if c.fullscreen then
                if not active[c] and not (hints and hints.store_geometry==false) then
                    saved[c]={geometry=copy(c:geometry()), border=c.border_width, screen=c.screen,
                        origin=copy(c.screen.geometry),workarea=copy(c.screen.workarea)}
                end
                active[c]=true
                fullscreen(c)
            else
                local previous=saved[c]
                if previous then
                    local target=c.screen
                    local g=copy(previous.geometry)
                    local origin=target.geometry
                    g.x=g.x+origin.x-previous.origin.x
                    g.y=g.y+origin.y-previous.origin.y
                    c.border_width=previous.border
                    if target~=previous.screen or not same(origin,previous.origin) then
                        bounded(g,origin,c.border_width)
                    end
                    c:geometry(g)
                    -- Setting restored coordinates can select a screen. Preserve
                    -- the user's current monitor, then fit after panel struts settle.
                    if c.screen~=target then c.screen=target end
                    refit(c)
                    fit[c]=previous
                    saved[c]=nil
                else
                    refit(c)
                    fit[c]=true -- No guessed normal rectangle or replacement history.
                end
                active[c]=nil
                engine.queue_refit(c)
            end
        end)
    end
    function engine.forget(c)
        saved[c],fit[c],active[c]=nil,nil,nil
    end
    return engine
end
local installed=setmetatable({}, {__mode='k'})
function M.install(client,awful,gears)
    if installed[client] then return installed[client] end
    local engine=M.new {native=awful.ewmh.geometry, placement=awful.placement,
                        delay=gears.timer.delayed_call}
    client.disconnect_signal('request::geometry',awful.ewmh.geometry)
    client.connect_signal('request::geometry',engine.handle)
    client.connect_signal('unmanage',engine.forget)
    installed[client]=engine
    return engine
end
return M
