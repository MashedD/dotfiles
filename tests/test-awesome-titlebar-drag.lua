local module = dofile('dotfiles/.config/awesome/titlebar-drag.lua')
local screen = {geometry = {x=0,y=0,width=1024,height=768},
    workarea = {x=0,y=30,width=1024,height=738}}
assert(module.edge_action({x=1,y=1},screen.geometry,16)=='maximize','top wins at corners')
assert(module.edge_action({x=500,y=15},screen.geometry,16)=='maximize')
assert(module.edge_action({x=15,y=300},screen.geometry,16)=='left')
assert(module.edge_action({x=1008,y=300},screen.geometry,16)=='right')
assert(module.edge_action({x=500,y=300},screen.geometry,16)==nil)
local restored=module.restore_geometry({x=0,y=30,width=1024,height=738},
    {x=20,y=60,width=400,height=300},{x=800,y=50},{x=500,y=120})
assert(restored.x==187.5 and restored.y==100 and restored.width==400 and restored.height==300)
local clamped=module.restore_geometry({x=0,y=30,width=1024,height=738},
    {x=20,y=60,width=400,height=300},{x=1200,y=50},{x=500,y=120})
assert(clamped.x==100 and clamped.y==100)

local function fixture(options)
    options=options or {}
    local pointer={x=options.x or 800,y=options.y or 100}
    local mouse={screen=screen,coords=function() return {x=pointer.x,y=pointer.y} end}
    local client={valid=true,floating=options.floating~=false,fullscreen=options.fullscreen or false,
        maximized=options.maximized or false,screen=screen,
        maximized_geometry={x=0,y=30,width=1024,height=738},
        normal_geometry={x=100,y=100,width=400,height=300}}
    function client:geometry() return self.maximized and self.maximized_geometry or self.normal_geometry end
    local captured, native_moves, snaps
    local callbacks={move={},leave={}}
    local resize=setmetatable({
        add_move_callback=function(callback) callbacks.move[#callbacks.move+1]=callback end,
        add_leave_callback=function(callback) callbacks.leave[#callbacks.leave+1]=callback end,
    },{__call=function(_,c,context,args) captured={client=c,context=context,args=args} end})
    local runtime={mouse=mouse,threshold=4,
        placement={centered=function() return {x=pointer.x,y=pointer.y} end,
            under_mouse=function() end},resize=resize,snap_distance=8,
        native_move=function() native_moves=(native_moves or 0)+1 end,
        snap=function(c,right) snaps={client=c,right=right} end}
    return {controller=module.new(runtime),client=client,pointer=pointer,
        capture=function() return captured end,native_moves=function() return native_moves or 0 end,
        snaps=function() return snaps end,callbacks=callbacks}
end

local click=fixture{maximized=true}
assert(click.controller.move(click.client))
local op=click.capture();assert(op.context=='mouse.move' and op.args.snap==false)
assert(op.args.move_callback(click.client,click.client:geometry())==click.client.maximized_geometry)
assert(click.client.maximized and op.args.leave_callback(click.client,nil)==nil,
    'click must not unmaximize or snap')

local drag=fixture{maximized=true}
assert(drag.controller.move(drag.client));op=drag.capture()
drag.pointer.x,drag.pointer.y=500,120
local moved=op.args.move_callback(drag.client,drag.client:geometry())
assert(not drag.client.maximized and op.args.snap~=false)
assert(moved.x==187.5 and moved.y==50 and moved.width==400 and moved.height==300,
    'restored titlebar anchor follows pointer proportionally')
assert(op.args.offset.x== -112.5 and op.args.offset.y==80)
-- A top-edge release maximizes instead of accepting Awesome's half-height preview.
drag.pointer.x,drag.pointer.y=500,4
assert(op.args.leave_callback(drag.client,{x=0,y=0,width=512,height=369})==nil)
assert(drag.client.maximized)

local ordinary_click=fixture{maximized=false}
assert(ordinary_click.controller.move(ordinary_click.client) and ordinary_click.native_moves()==1)
local original=ordinary_click.client:geometry()
assert(ordinary_click.callbacks.leave[1](ordinary_click.client,nil)==original,
    'ordinary click preserves its geometry and does not edge-snap')

local ordinary_top=fixture{maximized=false}
ordinary_top.controller.move(ordinary_top.client)
ordinary_top.pointer.x,ordinary_top.pointer.y=500,4
ordinary_top.callbacks.move[1](ordinary_top.client,ordinary_top.client:geometry())
assert(ordinary_top.callbacks.leave[1](ordinary_top.client,{x=0,y=0,width=512,height=369})==nil)
assert(ordinary_top.client.maximized,'ordinary titlebar top-drop maximizes')

local side=fixture{maximized=true}
side.controller.move(side.client);op=side.capture()
side.pointer.x,side.pointer.y=3,300
op.args.move_callback(side.client,side.client:geometry())
assert(op.args.snap==8,'preserve Awesome default client-snap distance')
assert(op.args.leave_callback(side.client,{x=0,y=30,width=500,height=700})==nil)
assert(side.snaps() and side.snaps().right==false)

local corner=fixture{maximized=true}
corner.controller.move(corner.client);op=corner.capture()
corner.pointer.x,corner.pointer.y=2,2
op.args.move_callback(corner.client,corner.client:geometry())
op.args.leave_callback(corner.client,{})
assert(corner.client.maximized and not corner.snaps(),'top has priority over corner side snap')

local tiled=fixture{floating=false}
assert(not tiled.controller.move(tiled.client) and tiled.native_moves()==1 and not tiled.capture())
local fullscreen=fixture{fullscreen=true}
assert(not fullscreen.controller.move(fullscreen.client) and not fullscreen.capture())
print('Awesome titlebar drag tests passed')
