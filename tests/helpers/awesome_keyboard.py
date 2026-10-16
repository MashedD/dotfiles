"""Keyboard-only sidebar and native-menu checks on the harness's private display."""
import os
from pathlib import Path
import subprocess
import time
import re
import tempfile
from awesome_windows import FixtureWindow
from awesome_calendar import verify_rollover


def verify(*, lua, press, pointer, wait, env, visual, compare_visual):
    saved={}
    def stub(path,name):
        saved[path]=(path.read_bytes(),path.stat().st_mode) if path.exists() else None
        path.write_text('#!/bin/sh\nprintf "%s\\n" "keyboard:'+name+':$*" >> "$TEST_ACTIONS"\n')
        path.chmod(0o755)
    for name in ('kitty','pcmanfm','pavucontrol','xfce4-appfinder','firefox','systemctl'):
        stub(Path(env['PATH'].split(os.pathsep)[0])/name,name)
    stub(Path(env['HOME'])/'.local/bin/desktop-lock','lock')
    stub(Path(env['HOME'])/'.local/bin/desktop-volume','volume')
    lua('''__keyboard_errors={}; __keyboard_error_handler=function(err) table.insert(__keyboard_errors,tostring(err)) end
        awesome.connect_signal('debug::error',__keyboard_error_handler)
        local s=screen[1]; __keyboard_saved={mode=s.sidebar_mode,offset=s.sidebar_scroll_offset(),
        month=s.sidebar_calendar_month(),date=s.sidebar_calendar_selected_date(),folds={},focus=client.focus}
        for id,section in pairs(s.sidebar_sections) do __keyboard_saved.folds[id]=section.collapsed; if section.collapsed then section.toggle_action() end end
        for _,c in ipairs(client.get()) do if c.instance=='AwesomeSmokeA' then c:emit_signal('request::activate','test',{raise=true}); __keyboard_client=c end end''')
    def active(value=True):
        wait('return tostring(screen[1].sidebar_keyboard.active)', '"'+str(value).lower()+'"')
    def mode(value):
        lua(f'screen[1].sidebar_mode={value}; screen[1].sidebar_update_mode()')
    def select(target):
        code='''local k=screen[1].sidebar_keyboard; local current=k.target(); assert(current)
            local from,to; local entries=k.entries(); for i,t in ipairs(entries) do if t.id==current.id then from=i end; if t.id==%r then to=i end end
            assert(from and to); return tostring((to-from)%%#entries)''' % target
        output=lua(code)
        count=int(re.search(r'string "(\d+)"',output)[1])
        if count:
            subprocess.run(['xdotool','key','--clearmodifiers',*(['Tab']*count)],env=env,check=True,timeout=5)
            time.sleep(.12)
        wait('return screen[1].sidebar_keyboard.target().id','"'+target+'"')
    def rectangle():
        output=lua('''local s=screen[1]; local t=s.sidebar_keyboard.target(); assert(t)
            local widget=t.resolve and t.resolve() or t.widget
            local function find(h)
                if h:get_widget()==widget then local w,v=h:get_size(); local x,y,width,height=h:get_matrix_to_device():transform_rectangle(0,0,w,v)
                    return math.floor(width)..":"..math.floor(height)..":"..math.floor(s.sidebar.x+x)..":"..math.floor(s.sidebar.y+y) end
                for _,child in ipairs(h:get_children()) do local r=find(child); if r then return r end end
            end
            return find(s.sidebar._drawable._widget_hierarchy)''')
        match=re.search(r'(\d+):(\d+):(\d+):(\d+)',output)
        assert match,output
        return tuple(map(int,match.groups()))
    try:
        mode(0);press('super+s');active(False)
        assert 'true' in lua('return not screen[1].sidebar.visible and not keygrabber.isrunning() and not screen[1].start_menu.wibox.visible')
        for value in (1,2,3):
            mode(value)
            lua('__keyboard_strut=screen[1].sidebar:struts().right')
            press('super+s');active()
            assert 'true' in lua(f'return screen[1].sidebar_mode=={value} and screen[1].sidebar.ontop and screen[1].sidebar:struts().right==__keyboard_strut and client.focus==__keyboard_client')
            press('Escape');active(False)
            assert 'true' in lua(f'return screen[1].sidebar.ontop=={str(value!=1).lower()} and not keygrabber.isrunning() and client.focus==__keyboard_client')
        # A foreign native grab must neither be stolen nor resumed over our owner.
        lua('__keyboard_foreign=require("awful").keygrabber.run(function() end); screen[1].sidebar_keyboard.toggle()')
        active(False)
        assert 'true' in lua('return keygrabber.isrunning()')
        lua('require("awful").keygrabber.stop(__keyboard_foreign)')
        press('super+s');active()
        lua('__keyboard_foreign=require("awful").keygrabber.run(function() end)')
        active(False)
        lua('require("awful").keygrabber.stop(__keyboard_foreign); __keyboard_foreign=nil')
        assert 'false' in lua('return tostring(keygrabber.isrunning())')
        lua('mousegrabber.run(function() return true end,"left_ptr"); screen[1].sidebar_keyboard.toggle()')
        active(False)
        assert 'true' in lua('return mousegrabber.isrunning()')
        lua('mousegrabber.stop()')
        # Held entry and activation presses do not toggle repeatedly.
        pointer('keydown','Super_L','keydown','s');active()
        pointer('keydown','s');active()
        pointer('keyup','s','keyup','Super_L')
        press('super+s');active(False)
        press('super+s');active();select('calendar:grid')
        press('Home')
        assert 'true' in lua('return screen[1].sidebar_calendar_selected_date()==os.date("%Y-%m-%d")')
        lua('__keyboard_date=screen[1].sidebar_calendar_selected_date()')
        for key in ('Right','Down','Left','Up','Page_Down','Page_Up','End'):
            lua(f'__keyboard_expected=dofile(awesome.conffile:match("^(.*)/").."/sidebar-calendar.lua").move_date(screen[1].sidebar_calendar_selected_date(),"{key}")')
            press(key)
            assert 'true' in lua('return screen[1].sidebar_calendar_selected_date()==__keyboard_expected and screen[1].sidebar_calendar_month()==__keyboard_expected:sub(1,7)'), (key,lua('return screen[1].sidebar_calendar_selected_date()..":"..screen[1].sidebar_calendar_month()..":"..__keyboard_expected..":"..(screen[1].sidebar_keyboard.target() or {id="stopped"}).id'))
        verify_rollover(lua=lua,env=env,wait=wait)
        active(False);press('super+s');active();select('calendar:grid')
        lua('screen[1].sidebar_calendar_refresh()')
        active();select('calendar:grid')
        lua('screen[1].sidebar_sections.calendar.toggle_action()')
        wait('return screen[1].sidebar_keyboard.target().id','"calendar:header"')
        press('Right');select('calendar:grid')
        press('Right')
        select('calendar:header');press('Left')
        assert 'true' in lua('local k=screen[1].sidebar_keyboard; for _,t in ipairs(k.entries()) do if t.id=="calendar:grid" then return false end end; return k.target().id=="calendar:header"')
        press('Right');select('system-status:volume')
        actions=Path(env['TEST_ACTIONS'])
        before=len(actions.read_text())
        for key in ('Right','Left','space'):
            press(key)
            assert 'true' in lua('return screen[1].sidebar_keyboard.active'), (key,actions.read_text()[before:])
        deadline=time.monotonic()+3
        while time.monotonic()<deadline:
            recorded=[line for line in actions.read_text()[before:].splitlines() if line.startswith('keyboard:volume:')]
            if len(recorded)>=3: break
            time.sleep(.02)
        assert sorted(recorded)==['keyboard:volume:down','keyboard:volume:mute','keyboard:volume:up'], actions.read_text()[before:]
        press('Return');active(False)
        assert 'keyboard:pavucontrol:' in actions.read_text()[before:]
        press('super+s');select('quick-launch:Terminal');press('Return');active(False)
        assert 'keyboard:kitty:' in actions.read_text()
        press('super+s');select('quick-launch:Sleep');press('Return');active(False)
        assert 'keyboard:systemctl:suspend' in actions.read_text()
        press('super+s');select('calendar:grid');press('Return');active(False)
        assert 'calendar.md' in actions.read_text()
        # Modal input never reaches the application; existing WM actions dispatch.
        press('super+s');active()
        for key in ('a','shift+a','ctrl+c','ctrl+v'):
            press(key);active()
            assert 'true' in lua('return __keyboard_client.valid and client.focus==__keyboard_client')
        press('Caps_Lock');press('Tab');press('shift+Tab');active();press('Caps_Lock')
        press('Num_Lock');press('Tab');active();press('Num_Lock')
        press('super+l');active(False)
        assert 'keyboard:lock:' in actions.read_text()
        press('super+s');active();press('XF86AudioPlay');active(False)
        assert 'playerctl play-pause' in actions.read_text()
        if visual:
            press('super+s');active();select('calendar:header')
            time.sleep(.15)
            rect=rectangle()
            press('Escape')
            with tempfile.TemporaryDirectory(prefix='keyboard-visual-',dir=env['XDG_RUNTIME_DIR']) as directory:
                def capture(name):
                    path=Path(directory)/(name+'.png')
                    w,h,x,y=rect
                    subprocess.run(['import','-window','root','-crop',f'{w}x{h}+{x}+{y}',str(path)],env=env,check=True,timeout=5)
                    return path
                baseline=capture('inactive')
                press('super+s');active();select('calendar:header');time.sleep(.15)
                assert rectangle()==rect
                focused=capture('focused');compare_visual(baseline,focused,True)
                press('Escape');time.sleep(.15)
                compare_visual(baseline,capture('restored'),False)
        press('super+s');active();press('alt+Tab');active(False)
        assert 'true' in lua('return client.focus~=__keyboard_client')
        lua('__keyboard_client:emit_signal("request::activate","test",{raise=true})')
        press('super+s');active();lua('require("menubar").show()');active(False)
        press('Escape');wait('return tostring(keygrabber.isrunning())','"false"')
        # A client shortcut receives the actual focused client, after releasing ours.
        fixture=FixtureWindow(env['DISPLAY'],'normal')
        try:
            wait(f'return tostring(client.focus and client.focus.window=={fixture.window})','"true"')
            press('super+s');active();press('alt+F4');active(False)
            fixture.wait_delete()
            assert fixture.delete_requests==1
        finally:
            fixture.close()
        lua('__keyboard_client:emit_signal("request::activate","test",{raise=true})')
        # Native menu grabs replace ours, Escape dismisses without changing focus.
        for chord in ('alt+space','super+p','super+shift+q'):
            press('super+s');active();press(chord);active(False)
            assert 'true' in lua('return keygrabber.isrunning() and client.focus==__keyboard_client')
            press('Escape')
            wait('return tostring(keygrabber.isrunning())','"false"')
        press('super+s');active();press('Super_L');active(False)
        wait('return tostring(screen[1].start_menu.wibox.visible)','"true"')
        press('Down');press('Escape')
        wait('return tostring(screen[1].start_menu.wibox.visible)','"false"')
        press('super+s');active();press('super+shift+s');active(False)
        assert 'true' in lua('return screen[1].sidebar_mode==0 and not screen[1].sidebar.visible')
        mode(3);press('super+s');active();press('super+2');active(False)
        wait('return screen[1].selected_tag.index','2');press('super+1')
        press('super+s');active();lua('__keyboard_client.fullscreen=true');active(False)
        press('super+s');active(False);lua('__keyboard_client.fullscreen=false')
        press('super+s');active();pointer('mousemove',500,700,'click',1);active(False)
        press('super+s');active();select('calendar:header')
        w,h,x,y=rectangle()
        pointer('mousemove',x+w//2,y+h//2,'click',1);active(False)
        # The same click still takes the existing fold path exactly once.
        assert 'true' in lua('return screen[1].sidebar_sections.calendar.collapsed')
        lua('screen[1].sidebar_sections.calendar.toggle_action()')
        press('super+s');active();lua('screen[1].sidebar.visible=false');active(False)
        lua('screen[1].sidebar_update_mode()')
        press('super+s');active()
        lua('screen.fake_add(1280,0,640,800); __keyboard_second=screen[2]; __keyboard_second.sidebar_keyboard.toggle()')
        active(False)
        assert 'true' in lua('return not __keyboard_second.sidebar_keyboard.active and not keygrabber.isrunning()')
        lua('__keyboard_second.sidebar_keyboard.toggle()')
        assert 'true' in lua('return __keyboard_second.sidebar_keyboard.active and not screen[1].sidebar_keyboard.active')
        lua('__keyboard_second_controller=__keyboard_second.sidebar_keyboard; __keyboard_second_ui=__keyboard_second.sidebar_ui; __keyboard_second:emit_signal("removed"); __keyboard_second:fake_remove()')
        assert 'true' in lua('return not __keyboard_second_controller.active and __keyboard_second_ui.disposed and not keygrabber.isrunning()')
        lua('__keyboard_second=nil; __keyboard_second_controller=nil; __keyboard_second_ui=nil')
        assert 'true' in lua('return #__keyboard_errors==0'), lua('return table.concat(__keyboard_errors,"\\n")')
        assert 'false' in lua('return tostring(keygrabber.isrunning())')
    finally:
        pointer('keyup','s','keyup','Super_L','mouseup',1)
        lua('''awesome.disconnect_signal('debug::error',__keyboard_error_handler)
            __keyboard_error_handler=nil; __keyboard_errors=nil
            local s=screen[1]; s.sidebar_keyboard.stop(); local old=__keyboard_saved
            if old then
                for id,collapsed in pairs(old.folds) do local section=s.sidebar_sections[id]; if section.collapsed~=collapsed then section.toggle_action() end end
                local y,m=old.month:match('(%d+)%-(%d+)'); local cy,cm=s.sidebar_calendar_month():match('(%d+)%-(%d+)')
                local delta=(tonumber(y)-tonumber(cy))*12+tonumber(m)-tonumber(cm)
                for i=1,math.abs(delta) do if delta>0 then s.sidebar_calendar_next_action() else s.sidebar_calendar_previous_action() end end
                s.sidebar_calendar_select_date(old.date); s.sidebar_mode=old.mode; s.sidebar_update_mode(); s.sidebar_scroll_by(old.offset-s.sidebar_scroll_offset())
                if old.focus and old.focus.valid then old.focus:emit_signal('request::activate','test',{raise=true}) end
            end
            __keyboard_saved=nil; __keyboard_client=nil; __keyboard_strut=nil; __keyboard_date=nil; __keyboard_expected=nil''')
        for path,old in saved.items():
            if old: path.write_bytes(old[0]);path.chmod(old[1])
            else:path.unlink(missing_ok=True)
