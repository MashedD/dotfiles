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
