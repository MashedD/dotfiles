"""Titlebar checks shared by the full and focused private sessions."""
import re
import time

import awesome_controls
from awesome_windows import FixtureWindow


def prepare(*, lua, wait, press, spawn):
    wait('return #screen[1].tags', '4')
    wait('return screen[1].workarea.y', '30')
    lua('screen[1].tags[1]:view_only(); require("awful").layout.set(require("awful").layout.suit.floating,screen[1])')
    for _ in range(4):
        if '"0"' in lua('return tostring(screen[1].sidebar_mode)'):
            break
        press('super+shift+s')
    wait('return tostring(screen[1].sidebar_mode)', '"0"')
    for name in ('AwesomeSmokeA', 'AwesomeSmokeB'):
        spawn(name, '400x200')
    wait('local n=0; for _,c in ipairs(client.get()) do if c.class=="Xmessage" then n=n+1 end end; return n', '2')
    lua('for _,c in ipairs(client.get()) do if c.instance=="AwesomeSmokeA" then c:geometry({x=80,y=180,width=400,height=200}) elseif c.instance=="AwesomeSmokeB" then c:geometry({x=510,y=240,width=400,height=200}) end end')
    wait('return tostring(not mousegrabber.isrunning() and not screen[1].start_menu.wibox.visible)', '"true"')


def verify_controls(*, lua, wait, pointer, capture, helper, press, visual, env,
                    capture_titlebar, compare_visual, log_text):
    titlebar_state = lua('local r=""; for _,c in ipairs(client.get()) do if c.class == "Xmessage" then local top=c._private and c._private.titlebars and c._private.titlebars.top; r=r..tostring(c.floating)..":"..tostring(top and top.args.size)..":"..tostring(c.y)..";" end end; return r')
    assert titlebar_state.count("true:26:") == 2, (titlebar_state, log_text())
    # Real pointer gestures: mouse-down never activates; release location matters.
    lua('for _,c in ipairs(client.get()) do if c.instance=="AwesomeSmokeA" then c.minimized=false; client.focus=c; c:raise() end end')
    wait('return client.focus and client.focus.instance', '"AwesomeSmokeA"')
    lua('_G.__gesture_client=client.focus')
    coordinates = lua('local c=__gesture_client; return (c.x+c.width-36)..":"..(c.y+13)..":"..(c.x-20)')
    gx, gy, outside_x = re.search(r'"(\d+):(\d+):(\d+)"', coordinates).groups()
    pointer("mousemove", gx, gy, "mousedown", 1)
    assert 'false' in lua('return tostring(__gesture_client.maximized)')
    capture("titlebar-pressed")
    pointer("mousemove", outside_x, gy, "mouseup", 1)
    assert 'false' in lua('return tostring(__gesture_client.maximized)')
    pointer("mousemove", gx, gy, "click", 3)
    assert 'false' in lua('return tostring(__gesture_client.maximized)')
    pointer("mousedown", 1, "mousemove", outside_x, gy, "mousemove", gx, gy, "mouseup", 1)
    wait('return tostring(__gesture_client.maximized)', '"true"')
    lua('__gesture_client.maximized=false')
    wait('return tostring(__gesture_client.maximized)', '"false"')

    # Maximized titlebar clicks preserve maximize; a real drag restores beneath
    # the pointer, then uses top/side workarea snapping on release.
    time.sleep(0.55)  # let the intentional double-click interval expire
    lua('__gesture_client:geometry({x=120,y=190,width=400,height=200}); __restore_geometry=__gesture_client:geometry(); __gesture_client.maximized=true')
    max_state=lua('local c=__gesture_client; local g=c:geometry(); return g.x..":"..g.y..":"..g.width..":"..g.height')
    mx,my,mw,mh=map(int,re.search(r'"(-?\d+):(-?\d+):(\d+):(\d+)"',max_state).groups())
    click_x,clic_y=mx+int(mw*0.72),my+13
    pointer('mousemove',click_x,clic_y,'click',1)
    wait('return tostring(__gesture_client.maximized)','"true"')
    time.sleep(0.55)  # a click remains a click, not the start of a double-click
    saved=lua('local c=__gesture_client; local g=c:geometry(); return g.x..":"..g.y..":"..g.width..":"..g.height')
    sx,sy,sw,sh=map(int,re.search(r'"(-?\d+):(-?\d+):(\d+):(\d+)"',saved).groups())
    ratio=max(0,min(1,(click_x-sx)/sw)); title_offset=clic_y-sy
    target_x,target_y=500,250
    pointer('mousemove',click_x,clic_y);pointer('mousedown',1)
    pointer('mousemove',target_x,target_y);pointer('mouseup',1)
    wait('return tostring(not mousegrabber.isrunning() and not __gesture_client.maximized)','"true"')
    moved=lua('local c=__gesture_client; local g=c:geometry(); return g.x..":"..g.y..":"..g.width..":"..g.height')
    moved_x,moved_y,_,_=map(int,re.search(r'"(-?\d+):(-?\d+):(\d+):(\d+)"',moved).groups())
    restored_width=float(lua('return __restore_geometry.width').strip().split()[-1].strip('"'))
    assert abs(moved_x-(target_x-ratio*restored_width))<=3, (moved,ratio,restored_width)
    assert abs(moved_y-(target_y-title_offset))<=3, (moved,title_offset)
    time.sleep(0.55)  # reset titlebar's double-click detector before edge drags

    def drag_edge(start_x,start_y,end_x,end_y):
        pointer('mousemove',start_x,start_y);pointer('mousedown',1)
        pointer('mousemove',end_x,end_y);pointer('mouseup',1)
        wait('return tostring(not mousegrabber.isrunning())','"true"')
        time.sleep(0.55)

    # Top center and top corners maximize; corners do not quarter-snap.
    lua('__gesture_client.maximized=true')
    top=lua('local c=__gesture_client; local g=c:geometry(); return math.floor(g.x+g.width/2)..":"..math.floor(g.y+13)')
    tx,ty=map(int,re.search(r'"(-?\d+):(-?\d+)"',top).groups())
    drag_edge(tx,ty,tx,2)
    wait('return tostring(__gesture_client.maximized)','"true"')
    lua('__gesture_client.maximized=false; __gesture_client:geometry({x=180,y=210,width=400,height=200})')
    corner=lua('local c=__gesture_client; return (c.x+120)..":"..(c.y+13)')
    cx,cy=map(int,re.search(r'"(-?\d+):(-?\d+)"',corner).groups())
    drag_edge(cx,cy,2,2)
    wait('return tostring(__gesture_client.maximized)','"true"')

    # Ordinary floating-window titlebar drags use Awesome's native mover, with
    # the same full maximize result at the top edge.
    lua('__gesture_client.maximized=false; __gesture_client:geometry({x=180,y=210,width=400,height=200})')
    point=lua('local c=__gesture_client; return (c.x+120)..":"..(c.y+13)')
    px,py=map(int,re.search(r'"(-?\d+):(-?\d+)"',point).groups())
    drag_edge(px,py,640,2)
    wait('return tostring(__gesture_client.maximized)','"true"')

    # Left/right releases fill their respective halves of the workarea.
    lua('__gesture_client.maximized=false; __gesture_client:geometry({x=180,y=210,width=400,height=200})')
    for edge_x,right in ((2,False),(-2,True)):
        if right:
            edge_x=int(float(lua('return screen[1].geometry.x+screen[1].geometry.width-2').strip().split()[-1].strip('"')))
        point=lua('local c=__gesture_client; return (c.x+120)..":"..(c.y+13)')
        px,py=map(int,re.search(r'"(-?\d+):(-?\d+)"',point).groups())
        drag_edge(px,py,edge_x,300)
        geometry=lua('local c=__gesture_client; local g=c:geometry(); return g.x..":"..g.y..":"..g.width..":"..g.height')
        x,y,width,height=map(int,re.search(r'"(-?\d+):(-?\d+):(\d+):(\d+)"',geometry).groups())
        area=lua('local a=screen[1].workarea; return a.x..":"..a.y..":"..a.width..":"..a.height')
        ax,ay,aw,ah=map(int,re.search(r'"(-?\d+):(-?\d+):(\d+):(\d+)"',area).groups())
        expected_x=ax+(aw//2 if right else 0)
        assert abs(x-expected_x)<=2 and abs(y-ay)<=2, (right,geometry,area)
        assert width > aw//2-10 and width <= aw//2, (right,geometry,area)
        assert height >= ah-10, (right,geometry,area)
        lua('__gesture_client:geometry({x=180,y=210,width=400,height=200})')

    lua('__gesture_client.maximized=false; __gesture_client:geometry({x=80,y=180,width=400,height=200})')
    coordinates=lua('local c=__gesture_client; return (c.x+c.width-36)..":"..(c.y+13)')
    gx,gy=re.search(r'"(-?\d+):(-?\d+)"',coordinates).groups()
    pointer("mousemove", gx, gy, "mousedown", 1)
    lua('__gesture_client.fullscreen=true')
    wait('return tostring(not __gesture_client._private.release_controls.titlebar_maximize.state.armed and not mousegrabber.isrunning())', '"true"')
    pointer("mouseup", 1)
    lua('__gesture_client.fullscreen=false')
    # Delayed tooltips neither appear immediately nor steal focus.
    pointer("mousemove", 10, 600)
    lua('_G.__gesture_tip=__gesture_client._private.titlebar_ui.tooltips[1]; __gesture_tip.hide(); __gesture_tip.show(__gesture_client)')
    time.sleep(0.15)
    assert 'false' in lua('return tostring(__gesture_tip.visible)')
    wait('return tostring(__gesture_tip.visible)', '"true"')
    assert 'true' in lua('return client.focus==__gesture_client')
    lua('__gesture_tip.hide(); __gesture_tip=nil')
    lua('__narrow_previous=client.focus')
    try:
        for kind in ('normal','dialog'):
            fixture=FixtureWindow(env['DISPLAY'],kind)
            try:
                awesome_controls.verify_narrow_titlebar(fixture=fixture,kind=kind,lua=lua,helper=helper,
                    pointer=pointer,wait=wait,press=press,visual=visual,
                    capture_titlebar=capture_titlebar,compare_visual=compare_visual)
            finally:
                fixture.close()
    finally:
        lua('if __narrow_previous and __narrow_previous.valid then __narrow_previous:emit_signal("request::activate","test",{raise=true}) end; __narrow_previous=nil')
    awesome_controls.verify_titlebar_ontop(lua=lua, helper=helper, pointer=pointer, wait=wait)
    control_state = helper('local controls=h.titlebar_controls(client.focus); for _,id in ipairs({"titlebar_ontop","titlebar_minimize","titlebar_maximize","titlebar_close"}) do local b=controls[id]; if not b then return id..":missing" end; if b.forced_width~=21 or b.forced_height~=19 or not b.fg then return id..":geometry" end; b:emit_signal("mouse::leave"); local normal=tostring(b.bg); b:emit_signal("mouse::enter"); if tostring(b.bg)==normal then return id..":hover" end; b:emit_signal("mouse::leave"); if tostring(b.bg)~=normal then return id..":restore" end end; _G.__polish_close_button=controls.titlebar_close; return true')
    assert 'true' in control_state, control_state
    lua('__polish_close_button:emit_signal("mouse::enter")')
    capture("titlebar-close-hover")
    lua('__polish_close_button:emit_signal("mouse::leave"); __polish_close_button=nil')
    press('alt+space')
    capture("window-menu")
    press('Escape')


def verify_destruction(*, spawn, wait, lua, pointer):
    # Closing never happens on mouse-down; destroyed clients cancel their grab.
    for name in ("AwesomeGestureCancel", "AwesomeGestureRelease", "AwesomeOntopCancel", "AwesomeFramePending"):
        spawn(name, '300x160')
        wait('return client.focus and client.focus.instance', name)
        control = 'titlebar_ontop' if name == 'AwesomeOntopCancel' else 'titlebar_close'
        offset = 82 if name == 'AwesomeOntopCancel' else 13
        coords = lua(f'_G.__closing_client=client.focus; _G.__closing_group=client.focus._private.titlebar_ui; _G.__closing_binding=client.focus._private.release_controls.{control}; return (client.focus.x+client.focus.width-{offset})..":"..(client.focus.y+13)')
        cx, cy = re.search(r'"(\d+):(\d+)"', coords).groups()
        pointer("mousemove", cx, cy, "mousedown", 1)
        assert 'true' in lua('return __closing_client.valid and __closing_binding.state.armed')
        if name in ("AwesomeGestureCancel", "AwesomeOntopCancel", "AwesomeFramePending"):
            if name == 'AwesomeFramePending':
                lua('__closing_client.fullscreen=true; __closing_client:kill()')
            else:
                lua('__closing_client:kill()')
            wait('return tostring(__closing_group.disposed and not mousegrabber.isrunning())', '"true"')
        pointer("mouseup", 1)
        wait('return tostring(__closing_group.disposed)', '"true"')
        assert 'false' in lua('return tostring(__closing_binding.state.armed)')
