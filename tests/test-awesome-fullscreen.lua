-- Pure geometry/dispatcher tests; no Awesome, X11, or persistent state.
local M=dofile('dotfiles/.config/awesome/fullscreen-geometry.lua')
local function clone(g) return {x=g.x,y=g.y,width=g.width,height=g.height} end
local function fixture()
    local screen={geometry={x=0,y=0,width=1280,height=800},workarea={x=0,y=30,width=980,height=770}}
    local c={valid=true,screen=screen,border_width=2,fullscreen=false,maximized=false,
             maximized_horizontal=false,maximized_vertical=false,g={x=100,y=100,width=400,height=300}}
    function c:geometry(g) if g then self.g=clone(g) end; return clone(self.g) end
    local queue,calls,history={}, {},{}
    local engine, fail, reenter
    local placement={}
    function placement.maximize(client,args)
        calls[#calls+1]={context='placement',args=args}
        assert(args.store_geometry==false and not args.honor_workarea and not args.honor_padding)
        if reenter then engine.handle(client,'maximized',{}) end
        if fail then error('placement failed') end
        client.border_width=0; client:geometry(client.screen.geometry)
    end
    function placement.no_offscreen(client,args)
        assert(args.honor_workarea)
        local a,g=client.screen.workarea,client:geometry()
        g.x=math.max(a.x,math.min(g.x,a.x+a.width-g.width-2*client.border_width))
        g.y=math.max(a.y,math.min(g.y,a.y+a.height-g.height-2*client.border_width))
        client:geometry(g)
    end
    local function native(client,context,args)
        calls[#calls+1]={context=context,args=args}
        if context=='maximized' then
            if client.maximized then
                if args.store_geometry~=false then history.g=clone(client.g);history.border=client.border_width end
                client.border_width=0;client:geometry(client.screen.workarea)
            else
                assert(history.g,'native maximize history missing')
                client.border_width=history.border;client:geometry(history.g)
            end
        end
        return 'native-result'
    end
    local runtime={placement=placement,native=native,delay=function(fn) queue[#queue+1]=fn end}
    engine=M.new(runtime)
    return {c=c,engine=engine,calls=calls,queue=queue,history=history,runtime=runtime,
        fail=function(value) fail=value end,reenter=function(value) reenter=value end,
        flush=function() while #queue>0 do table.remove(queue,1)() end end}
end
local f=fixture();local c,e=f.c,f.engine
assert(e.handle(c,'other',{custom=true})=='native-result')
assert(f.calls[1].context=='other' and f.calls[1].args.custom)
c.maximized=true;e.handle(c,'maximized',{})
local normal=clone(f.history.g)
c.fullscreen=true;e.handle(c,'fullscreen',{})
e.handle(c,'fullscreen',{}) -- Duplicate initial request must not overwrite.
e.handle(c,'fullscreen',{store_geometry=false})
assert(f.history.g.width==normal.width and f.history.border==2)
c.fullscreen=false;e.handle(c,'fullscreen',{})
assert(c.maximized and c.g.width==980 and c.border_width==0)
c.maximized=false;e.handle(c,'maximized',{})
f.flush();assert(c.g.x==normal.x and c.g.height==normal.height and c.border_width==2)
-- Refit coalescing never maximizes a normal window or rewrites history.
f=fixture();c,e=f.c,f.engine
e.queue_refit(c);e.queue_refit(c);assert(#f.queue==1)
f.flush();assert(#f.calls==0)
c.fullscreen=true;e.handle(c,'fullscreen',{})
e.queue_refit(c);c.fullscreen=false;e.handle(c,'fullscreen',{})
f.flush();assert(c.g.width==400 and c.g.height==300 and c.border_width==2)
-- Monitor moves translate coordinates and shrink/clamp only if necessary.
f=fixture();c,e=f.c,f.engine
c.fullscreen=true;e.handle(c,'fullscreen',{})
c.screen={geometry={x=1280,y=0,width=640,height=480},workarea={x=1280,y=30,width=340,height=450}}
e.handle(c,'fullscreen',{store_geometry=false})
c.fullscreen=false;e.handle(c,'fullscreen',{});f.flush()
assert(c.g.x>=1280 and c.g.y>=30 and c.g.width<=336 and c.g.height<=446)
-- Missing state fits current state without inventing a normal rectangle/history.
f=fixture();c,e=f.c,f.engine
c.fullscreen=true;e.handle(c,'fullscreen',{store_geometry=false})
e.handle(c,'fullscreen',{}) -- A late duplicate cannot fabricate missing history.
c.fullscreen=false;e.handle(c,'fullscreen',{});f.flush()
assert(f.history.g==nil and c.g.width<=c.screen.workarea.width)
-- Reentrant native requests are ignored only during the fullscreen operation.
f=fixture();c,e=f.c,f.engine;f.reenter(true)
c.fullscreen=true;e.handle(c,'fullscreen',{})
assert(#f.calls==1)
c.fullscreen=false;e.handle(c,'fullscreen',{});f.flush()
assert(c.g.width==400)
assert(e.handle(c,'other',{})=='native-result')
-- Exceptions always release the guard and retain the previous return snapshot.
f=fixture();c,e=f.c,f.engine;f.fail(true)
c.fullscreen=true;assert(not pcall(e.handle,c,'fullscreen',{}))
f.fail(false);e.handle(c,'fullscreen',{store_geometry=false})
c.fullscreen=false;e.handle(c,'fullscreen',{});f.flush();assert(c.g.width==400)
-- Exit/refit exceptions also release the guard and keep return state retryable.
f=fixture();c,e=f.c,f.engine
c.maximized=true;e.handle(c,'maximized',{})
c.fullscreen=true;e.handle(c,'fullscreen',{})
local native=f.runtime.native
f.runtime.native=function() error('native refit failed') end
c.fullscreen=false;assert(not pcall(e.handle,c,'fullscreen',{}))
f.runtime.native=native;e.handle(c,'fullscreen',{})
c.maximized=false;e.handle(c,'maximized',{});f.flush()
assert(c.g.width==400 and c.g.height==300 and c.border_width==2)
-- Destruction makes pending refits harmless; forgotten state cannot be restored.
f=fixture();c,e=f.c,f.engine
e.queue_refit(c);c.valid=false;e.forget(c);f.flush();assert(#f.calls==0)
-- Axis refits preserve flags and delegate native history with storage disabled.
f=fixture();c,e=f.c,f.engine;c.maximized_horizontal=true;c.maximized_vertical=true
e.refit(c)
assert(#f.calls==2 and f.calls[1].context=='maximized_horizontal' and f.calls[2].context=='maximized_vertical')
assert(f.calls[1].args.store_geometry==false and c.maximized==false)
-- Scheduling failures release the queue marker; flags are not touched by the module.
f=fixture();c,e=f.c,f.engine
local delay=f.runtime.delay
f.runtime.delay=function() error('delay failed') end
assert(not pcall(e.queue_refit,c))
f.runtime.delay=delay;e.queue_refit(c);assert(#f.queue==1);f.flush()
c.ontop=true;c.sticky=true;c.fullscreen=true;e.handle(c,'fullscreen',{})
c.fullscreen=false;e.handle(c,'fullscreen',{});f.flush()
assert(c.ontop and c.sticky)
-- Installation replaces only the native geometry callback, once.
local connects,disconnects={},{}
local client={connect_signal=function(name,fn) connects[#connects+1]={name,fn} end,
              disconnect_signal=function(name,fn) disconnects[#disconnects+1]={name,fn} end}
local awful={ewmh={geometry=f.runtime.native},placement=f.runtime.placement}
local first=M.install(client,awful,{timer={delayed_call=f.runtime.delay}})
assert(M.install(client,awful,{timer={delayed_call=f.runtime.delay}})==first)
assert(#disconnects==1 and disconnects[1][1]=='request::geometry' and disconnects[1][2]==awful.ewmh.geometry)
assert(#connects==2 and connects[1][1]=='request::geometry' and connects[2][1]=='unmanage')
print('Awesome fullscreen geometry tests passed')
