"""Focused private-session interaction scenarios for Awesome controls."""

import re
import time


_EDGE_SCROLL_STATE = '''
    local s=screen[1]; local p=mouse.coords(); local w=s.sidebar
    local top=w.y+s.sidebar_header.forced_height+s.sidebar_clock_card.forced_height
    local bottom=top+s.sidebar_scroll_view.forced_height
    return table.concat({
        "grab="..tostring(mousegrabber.isrunning()),
        "button="..tostring(p.buttons[1] == true),
        "pointer_x="..p.x, "pointer_y="..p.y,
        "visible="..tostring(w.visible),
        "x="..w.x, "y="..w.y, "width="..w.width, "height="..w.height,
        "top="..top, "bottom="..bottom,
        "position="..s.sidebar_scroll_position, "maximum="..s.sidebar_scroll_max(),
        "dragging="..tostring(s.sidebar_sections.todo.header.border_color == "#ffffff"),
        "header="..tostring(s.sidebar_sections.todo.header.border_color),
        "order="..table.concat(s.sidebar_content_order, ",")}, "|")
'''


def verify_sidebar_edge_scroll(*, lua, pointer, sidebar_title_point, log_text):
    """Real pointer drag with bounded, observable stages; never retry the drag."""
    stage, edge, initial, last = "locate", None, None, None
    started = time.monotonic()
    failure = None

    def snapshot():
        nonlocal last
        result = lua(_EDGE_SCROLL_STATE)
        match = re.search(r'string "([^"]*)"', result)
        if not match:
            raise AssertionError(f"Invalid edge-scroll snapshot: {result}")
        last = dict(field.split("=", 1) for field in match[1].split("|"))
        return last

    def await_state(name, predicate):
        nonlocal stage
        stage = name
        deadline = time.monotonic() + 8
        while True:
            state = snapshot()
            if predicate(state):
                return state
            if time.monotonic() >= deadline:
                raise AssertionError(f"Timed out waiting for {name}")
            time.sleep(0.05)

    def held(state):
        assert state["grab"] == "true" and state["button"] == "true", "Drag lost its grab/button"
        assert state["visible"] == "true", "Sidebar hidden during drag"
        return True

    try:
        source = sidebar_title_point("todo", reset_scroll=True)
        assert source, "Could not locate section to edge-scroll"
        initial = snapshot()
        assert initial["grab"] == "false", "Unexpected existing grab"
        pointer("mousemove", *source, "mousedown", 1)
        await_state("acquire grab", lambda s: s["grab"] == "true" and s["button"] == "true")
        pointer("mousemove", "--sync", source[0] + 12, source[1])
        state = await_state("cross drag threshold", lambda s: held(s) and s["dragging"] == "true")
        edge = (int(float(state["x"])) + 150, int(float(state["bottom"])) - 8)
        assert int(float(state["maximum"])) > 0, "Fixture must overflow"
        pointer("mousemove", "--sync", *edge)
        await_state("positive scroll progress", lambda s: held(s) and float(s["position"]) > float(initial["position"]))
        await_state("reach scroll bottom", lambda s: held(s) and float(s["position"]) >= float(s["maximum"]) - 1)
        stage = "drop at bottom"
        pointer("mousemove", "--sync", edge[0], edge[1] + 6)
        pointer("mouseup", 1)
        await_state("release grab", lambda s: s["grab"] == "false" and s["button"] == "false")
    except BaseException as error:
        failure = error
        details = [f"Edge-scroll stage={stage}; elapsed={time.monotonic()-started:.3f}s",
                   f"target={edge}; initial={initial}; last={last}"]
        try:
            details.append(f"current={snapshot()}")
        except Exception as diagnostic_error:
            details.append(f"State diagnostic failed: {diagnostic_error}")
        try:
            details.append(log_text())
        except Exception as diagnostic_error:
            details.append(f"Log diagnostic failed: {diagnostic_error}")
        raise AssertionError("\n".join(details) + f"\nOriginal failure: {error}") from error
    finally:
        try:
            pointer("mouseup", 1)
        except Exception as cleanup_error:
            if failure is None:
                raise
            failure.add_note(f"Button release also failed: {cleanup_error}")


def verify_titlebar_ontop(*, lua, helper, pointer, wait):
    pointer('mousemove', 10, 100)
    position = helper('''
        __ontop_client=client.focus; __ontop_client.ontop=false
        __ontop_widget=h.titlebar_controls(__ontop_client).titlebar_ontop
        assert(__ontop_widget and __ontop_widget.forced_width==21 and __ontop_widget.forced_height==19)
        __ontop_normal=__ontop_widget.bg
        local c=__ontop_client; local _,height=c:titlebar_top()
        local drawable=c._private.titlebars.top.drawable
        for x=0,c.width-1 do for _,v in ipairs(drawable:find_widgets(x,math.floor(height/2))) do
            if v.widget==__ontop_widget then
                return math.floor(c.x+c.border_width+v.x+v.width/2)..":"..math.floor(c.y+c.border_width+height/2)
            end
        end end; return "missing"
    ''')
    point = re.search(r'(\d+):(\d+)', position)
    assert point, position
    point = tuple(map(int, point.groups()))
    try:
        pointer('mousemove', *point, 'mousedown', 1)
        assert 'true' in lua('return not __ontop_client.ontop and __ontop_client._private.release_controls.titlebar_ontop.state.armed')
        pointer('mousemove', 10, 100, 'mouseup', 1)
        assert 'true' in lua('return not __ontop_client.ontop and __ontop_widget.bg==__ontop_normal')
        pointer('mousemove', *point, 'mousedown', 1)
        pointer('mousemove', 10, 100)
        pointer('mousemove', *point, 'mouseup', 1)
        wait('return tostring(__ontop_client.ontop)', '"true"')
        pointer('mousemove', 10, 100)
        assert 'true' in lua('return __ontop_widget.bg~=__ontop_normal and not __ontop_client.sticky')
        # Outside changes must repaint even without a hover or click transition.
        lua('__ontop_client.ontop=false')
        assert 'true' in lua('return __ontop_widget.bg==__ontop_normal')
        lua('__ontop_client.ontop=true')
        assert 'true' in lua('return __ontop_widget.bg~=__ontop_normal')
        pointer('mousemove', *point, 'click', 1)
        wait('return tostring(__ontop_client.ontop)', '"false"')
        pointer('mousemove', 10, 100)
        assert 'true' in lua('return __ontop_widget.bg==__ontop_normal')
        pointer('mousemove', *point, 'click', 3)
        assert 'false' in lua('return tostring(__ontop_client.ontop)')
        # Becoming fullscreen cancels a held press and must not toggle on release.
        pointer('mousemove', *point, 'mousedown', 1)
        lua('__ontop_client.fullscreen=true')
        wait('return tostring(not __ontop_client._private.release_controls.titlebar_ontop.state.armed and not mousegrabber.isrunning())', '"true"')
        pointer('mouseup', 1)
        assert 'false' in lua('return tostring(__ontop_client.ontop)')
        lua('__ontop_client.fullscreen=false')
    finally:
        pointer('mouseup', 1)
        lua('if __ontop_client and __ontop_client.valid then __ontop_client.ontop=false; __ontop_client.fullscreen=false end; __ontop_client=nil; __ontop_widget=nil; __ontop_normal=nil')


def verify_fullscreen_decorations(*, lua, wait, x11_state):
    """Check published frame extents as well as outer and actual client geometry."""
    lua('__frame_client=client.focus; __frame_geometry=__frame_client:geometry()')
    def geometry_matches_saved():
        return 'local c=__frame_client; local g=__frame_geometry; return tostring(c.x==g.x and c.y==g.y and c.width==g.width and c.height==g.height)'
    def fullscreen():
        lua('__frame_client.fullscreen=true')
        wait('local c=__frame_client; local a=c.screen.geometry; local _,top=c:titlebar_top(); local _,bottom=c:titlebar_bottom(); return tostring(c.fullscreen and top==0 and bottom==0 and c.border_width==0 and c.x==a.x and c.y==a.y and c.width==a.width and c.height==a.height)', '"true"')
        state = x11_state('__frame_client')
        assert state['extents'] == (0, 0, 0, 0), state
        expected = lua('local a=__frame_client.screen.geometry; return table.concat({a.x,a.y,a.width,a.height}, ",")')
        assert ','.join(map(str, state['geometry'])) in expected, (state, expected)
    def normal():
        wait('local c=__frame_client; local _,top=c:titlebar_top(); local _,bottom=c:titlebar_bottom(); return tostring(not c.fullscreen and not c.maximized and top==26 and bottom==10 and c.border_width==2)', '"true"')
        wait(geometry_matches_saved(), '"true"')
        state = x11_state('__frame_client')
        assert state['extents'] == (2, 2, 28, 12), state
    try:
        for _ in range(3):
            fullscreen()
            lua('__frame_client.fullscreen=false')
            normal()
        lua('__frame_client.maximized=true')
        wait('local c=__frame_client; local a=c.screen.workarea; return tostring(c.maximized and c.x==a.x and c.y==a.y and c.width==a.width and c.height==a.height)', '"true"')
        fullscreen()
        lua('__frame_client.fullscreen=false')
        wait('local c=__frame_client; local a=c.screen.workarea; local _,top=c:titlebar_top(); local _,bottom=c:titlebar_bottom(); return tostring(c.maximized and top==26 and bottom==0 and c.x==a.x and c.y==a.y and c.width==a.width and c.height==a.height)', '"true"')
        assert x11_state('__frame_client')['extents'][2:] == (26, 0)
    finally:
        # Restore the fixture explicitly: this test covers returning to maximized,
        # not Awesome 4.3's separate nested maximize/fullscreen restore history.
        lua('if __frame_client and __frame_client.valid then __frame_client.fullscreen=false; __frame_client.maximized=false; __frame_client.border_width=2; __frame_client:geometry(__frame_geometry) end; __frame_client=nil; __frame_geometry=nil')


def verify_fullscreen_workspaces(*, lua, wait):
    """An off-workspace fullscreen client must not suppress desktop controls."""
    lua('__fs_client=client.focus; __fs_home=__fs_client.screen.selected_tag; __fs_other=__fs_client.screen.tags[__fs_home.index%4+1]')
    shown = '''local s=__fs_client.screen; return tostring(s.panel.visible and s.sidebar.visible
        and s.sidebar_mode==3 and s.sidebar:struts().right==s.sidebar.width
        and s.workarea.y==s.panel.height and s.workarea.width==s.geometry.width-s.sidebar.width)'''
    hidden = '''local c=__fs_client; local s=c.screen; local a=s.geometry;
        return tostring(c.fullscreen and not s.panel.visible and not s.sidebar.visible
        and not s.sidebar_scrollbar_panel.visible and s.sidebar:struts().right==0
        and c.x==a.x and c.y==a.y and c.width==a.width and c.height==a.height)'''
    try:
        for _ in range(3):
            lua('__fs_other:view_only()')
            wait(shown, '"true"')
            assert 'true' in lua('return __fs_client.fullscreen and not __fs_client:isvisible()')
            lua('__fs_home:view_only()')
            wait(hidden, '"true"')
        lua('__fs_client.minimized=true')
        wait(shown, '"true"')
        lua('__fs_client.minimized=false')
        wait(hidden, '"true"')
        lua('__fs_client.hidden=true')
        wait(shown, '"true"')
        lua('__fs_client.hidden=false')
        wait(hidden, '"true"')
        lua('__fs_client:move_to_tag(__fs_other)')
        wait(shown, '"true"')
        lua('__fs_client.sticky=true')
        wait(hidden, '"true"')
        lua('__fs_client.sticky=false')
        wait(shown, '"true"')
        lua('__fs_client:move_to_tag(__fs_home)')
        wait(hidden, '"true"')
    finally:
        lua('if __fs_client and __fs_client.valid then __fs_client.hidden=false; __fs_client.minimized=false; __fs_client.sticky=false; __fs_client:move_to_tag(__fs_home); __fs_home:view_only(); __fs_client:emit_signal("request::activate", "test", {raise=true}) end; __fs_client=nil; __fs_home=nil; __fs_other=nil')


def verify_pointer_recovery(*, lua, pointer, wait):
    """Temporary controls retain detached nodes to exercise live-tree validation."""
    lua('''
        local wibox = require("wibox")
        local gears = require("gears")
        local i = dofile(gears.filesystem.get_configuration_dir() .. "interaction.lua")
        local f = {count=0, pressed=false, interaction=i, group=i.lifetime()}
        f.button = wibox.container.background(wibox.widget.textbox("Pointer fixture"), "#ffffff")
        f.layout = wibox.layout.fixed.vertical()
        f.button.forced_height = 50
        f.layout:add(f.button)
        f.window = wibox {x=450, y=350, width=160, height=50, visible=true, ontop=true}
        f.window.widget = f.layout
        f.binding = i.bind_button(f.button, {
            valid=function() return f.window.visible end,
            activate=function() f.count=f.count+1 end,
            paint=function(pressed) f.pressed=pressed end,
        }, f.group)
        __pointer_fixture = f
    ''')
    try:
        wait('return tostring(#__pointer_fixture.window:find_widgets(80,25)>0)', '"true"')
        for index, mutation in enumerate([
            '__pointer_fixture.layout:reset()',
            '__pointer_fixture.window.widget=require("wibox").widget.textbox("replacement")',
            'mousegrabber.stop()',
        ]):
            pointer("mousemove", 530, 375, "mousedown", 1)
            assert 'true' in lua('local f=__pointer_fixture; return f.binding.state.armed and f.pressed and mousegrabber.isrunning()')
            lua(mutation)
            wait('local f=__pointer_fixture; return tostring(not f.binding.state.armed and not f.pressed and not mousegrabber.isrunning())', '"true"')
            assert 'true' in lua(f'return __pointer_fixture.window.visible and __pointer_fixture.count=={index}')
            pointer("mouseup", 1)
            lua('local f=__pointer_fixture; f.layout:reset(); f.layout:add(f.button); f.window.widget=f.layout')
            wait('local f=__pointer_fixture; for _,v in ipairs(f.window:find_widgets(80,25)) do if v.widget==f.button then return "ready" end end; return "waiting"', '"ready"')
            pointer("mousemove", 530, 375, "click", 1)
            wait(f'return tostring(__pointer_fixture.count)', f'"{index+1}"')
    finally:
        pointer("mouseup", 1)
        lua('local f=__pointer_fixture; f.group.destroy(); f.window.visible=false; f.window.widget=nil; __pointer_fixture=nil')


def verify_native_menu_release(*, lua, pointer, wait, press, menu_item_point,
                               capture_menu_item, compare_visual, visual):
    lua('__awesome_menu_delete_count=0; __awesome_menu_action_count=0; __awesome_display_menu:add({"Delete while held", function() __awesome_menu_delete_count=__awesome_menu_delete_count+1 end}); __awesome_display_menu:add({"Release action", function() __awesome_menu_action_count=__awesome_menu_action_count+1 end})')
    display_item = menu_item_point('screen[1].start_menu', 13)
    pointer("mousemove", *display_item, "mousedown", 1)
    assert 'true' in lua('return screen[1].start_menu.items[13]._release_binding.state.armed and not __awesome_display_menu.wibox.visible')
    pointer("mousemove", 900, 700, "mouseup", 1)
    assert 'true' in lua('return screen[1].start_menu.wibox.visible and not __awesome_display_menu.wibox.visible and not mousegrabber.isrunning()')
    pointer("mousemove", *display_item, "mousedown", 1)
    assert 'true' in lua('return screen[1].start_menu.wibox.visible and not __awesome_display_menu.wibox.visible')
    pointer("mouseup", 1)
    wait('return tostring(__awesome_display_menu.wibox.visible)', '"true"')
    assert 'false' in lua('return tostring(screen[1].start_menu.wibox.visible)')

    disposable_item = menu_item_point('__awesome_display_menu', 5)
    pointer("mousemove", *disposable_item, "mousedown", 1)
    assert 'true' in lua('return __awesome_display_menu.items[5]._release_binding.state.armed')
    lua('__deleted_menu_item=__awesome_display_menu.items[5]; __awesome_display_menu:delete(5)')
    assert 'true' in lua('return not mousegrabber.isrunning() and __awesome_menu_delete_count == 0 and __deleted_menu_item._release_overlay.bg==nil and __deleted_menu_item._release_binding.state.destroyed')
    pointer("mouseup", 1)

    action_item = menu_item_point('__awesome_display_menu', 5)
    lua('__awesome_display_menu:item_enter(5, {mouse=true})')
    pointer("mousemove", 900, 700)
    normal = capture_menu_item('__awesome_display_menu', 5, "menu-normal") if visual else None
    pointer("mousemove", *action_item, "mousedown", 1)
    assert 'true' in lua('local i=__awesome_display_menu.items[5]; return i._release_binding.state.armed and i._release_overlay.bg~=nil and __awesome_menu_action_count == 0')
    held = capture_menu_item('__awesome_display_menu', 5, "menu-held") if visual else None
    pointer("mousemove", 900, 700)
    assert 'true' in lua('local i=__awesome_display_menu.items[5]; local s=i._release_binding.state; return s.armed and not s.inside and i._release_overlay.bg==nil and __awesome_menu_action_count == 0')
    canceled = capture_menu_item('__awesome_display_menu', 5, "menu-canceled") if visual else None
    if visual:
        compare_visual(normal, held, True)
        compare_visual(normal, canceled, False)
    pointer("mousemove", *action_item)
    assert 'true' in lua('local i=__awesome_display_menu.items[5]; local s=i._release_binding.state; return s.armed and s.inside and i._release_overlay.bg~=nil and __awesome_menu_action_count == 0')
    pointer("mouseup", 1)
    wait('return tostring(__awesome_menu_action_count)', '"1"')
    wait('return tostring(__awesome_display_menu.wibox.visible)', '"false"')

    lua('__awesome_display_menu:show()')
    wait('return tostring(__awesome_display_menu.wibox.visible)', '"true"')
    action_item = menu_item_point('__awesome_display_menu', 5)
    pointer("mousemove", *action_item, "mousedown", 1)
    assert 'true' in lua('return __awesome_display_menu.items[5]._release_binding.state.armed')
    lua('__awesome_display_menu:hide(); __awesome_display_menu:show()')
    assert 'true' in lua('return not mousegrabber.isrunning() and __awesome_menu_action_count == 1 and __awesome_display_menu.items[5]._release_overlay.bg==nil')
    pointer("mouseup", 1)
    assert 'true' in lua('return __awesome_display_menu.wibox.visible and __awesome_menu_action_count == 1')
    press('Escape')
    wait('return tostring(__awesome_display_menu.wibox.visible)', '"false"')

    lua('__awesome_display_menu:show(); __awesome_display_menu:item_enter(5)')
    press('Return')
    wait('return tostring(__awesome_menu_action_count)', '"2"')
    wait('return tostring(__awesome_display_menu.wibox.visible)', '"false"')
    lua('__awesome_menu_action_count=1')


def verify_workspace_pointer(*, lua, pointer, wait, press, workspace_point,
                             capture_workspace, compare_visual, visual):
    press('super+2')
    wait('return screen[1].selected_tag.index', '2')
    assert 'false' in lua('return tostring(screen[1].start_menu.wibox.visible)')
    press('super+1')
    wait('return screen[1].selected_tag.index', '1')
    point = workspace_point(3)
    normal = capture_workspace(3, "workspace-normal") if visual else None
    lua('_G.__workspace_normal_bg=screen[1].taglist_release_actions[screen[1].tags[3]].widget:get_children_by_id("background_role")[1].bg')
    pointer("mousemove", *point, "mousedown", 1)
    pressed = lua('local a=screen[1].taglist_release_actions[screen[1].tags[3]]; return tostring(a.view_binding.state.armed)..":"..tostring(screen[1].selected_tag.index)..":"..tostring(mousegrabber.isrunning())..":"..tostring(a.widget._workspace_pressed)..":"..tostring(a.widget._workspace_animation_alpha>0)..":"..tostring(a.overlay.bg~=nil)')
    assert 'true:1:true:true:true:true' in pressed, pressed
    lua('screen[1].tags[3]:view_only()')
    wait('return screen[1].selected_tag.index', '3')
    assert 'true' in lua('local a=screen[1].taglist_release_actions[screen[1].tags[3]]; return a.overlay.bg~=nil and a.widget._workspace_animation_alpha>0')
    lua('screen[1].tags[1]:view_only()')
    wait('return screen[1].selected_tag.index', '1')
    assert 'true' in lua('local a=screen[1].taglist_release_actions[screen[1].tags[3]]; return a.overlay.bg~=nil and a.widget:get_children_by_id("background_role")[1].bg==__workspace_normal_bg')
    held = capture_workspace(3, "workspace-held") if visual else None
    pointer("mousemove", 500, 700)
    wait('local a=screen[1].taglist_release_actions[screen[1].tags[3]]; return tostring(a.widget._workspace_animation_alpha==0 and a.overlay.bg==nil)', '"true"')
    canceled = capture_workspace(3, "workspace-canceled") if visual else None
    assert 'true' in lua('return screen[1].selected_tag.index == 1 and mousegrabber.isrunning()')
    pointer("mouseup", 1)
    assert 'true' in lua('return screen[1].selected_tag.index == 1 and not mousegrabber.isrunning()')
    if visual:
        compare_visual(normal, held, True)
        compare_visual(normal, canceled, False)

    pointer("mousemove", *point, "mousedown", 1)
    assert 'true' in lua('local a=screen[1].taglist_release_actions[screen[1].tags[3]]; return a.view_binding.state.armed and a.view_binding.state.inside and screen[1].selected_tag.index==1')
    pointer("mousemove", 500, 700)
    wait('local a=screen[1].taglist_release_actions[screen[1].tags[3]]; return tostring(a.view_binding.state.armed and not a.view_binding.state.inside and a.widget._workspace_animation_alpha==0)', '"true"')
    pointer("mousemove", *point)
    assert 'true' in lua('local a=screen[1].taglist_release_actions[screen[1].tags[3]]; return a.view_binding.state.armed and a.view_binding.state.inside and a.widget._workspace_animation_alpha>0')
    pointer("mouseup", 1)
    wait('return screen[1].selected_tag.index', '3')
    press('super+1')
    wait('return screen[1].selected_tag.index', '1')


def verify_geometry_cancellation(*, lua, pointer, wait, widget_point, expected_month):
    calendar_next = widget_point('screen[1].sidebar_calendar_next_button', scroll=-10000, x=270)
    sidebar_x = int(lua('return tostring(screen[1].sidebar.x)').strip().split('"')[1])
    pointer("mousemove", *calendar_next, "mousedown", 1)
    assert 'true' in lua('return screen[1].sidebar_calendar_next_button._sidebar_release_binding.state.armed')
    lua(f'screen[1].sidebar.x={sidebar_x-8}')
    wait('local b=screen[1].sidebar_calendar_next_button._sidebar_release_binding; return tostring(not b.state.armed and not mousegrabber.isrunning())', '"true"')
    pointer("mouseup", 1)
    lua(f'screen[1].sidebar.x={sidebar_x}')

    calendar_next = widget_point('screen[1].sidebar_calendar_next_button', x=270)
    sidebar_width = int(lua('return tostring(screen[1].sidebar.width)').strip().split('"')[1])
    pointer("mousemove", *calendar_next, "mousedown", 1)
    assert 'true' in lua('return screen[1].sidebar_calendar_next_button._sidebar_release_binding.state.armed')
    lua(f'screen[1].sidebar.width={sidebar_width+20}')
    wait('local b=screen[1].sidebar_calendar_next_button._sidebar_release_binding; return tostring(not b.state.armed and not mousegrabber.isrunning())', '"true"')
    pointer("mouseup", 1)
    lua(f'screen[1].sidebar.width={sidebar_width}')

    calendar_next = widget_point('screen[1].sidebar_calendar_next_button', x=270)
    pointer("mousemove", *calendar_next, "mousedown", 1)
    assert 'true' in lua('return screen[1].sidebar_calendar_next_button._sidebar_release_binding.state.armed')
    lua('screen[1].sidebar.visible=false')
    wait('local b=screen[1].sidebar_calendar_next_button._sidebar_release_binding; return tostring(not b.state.armed and not mousegrabber.isrunning())', '"true"')
    pointer("mouseup", 1)
    assert 'true' in lua('return screen[1].sidebar_calendar_month()==' + repr(expected_month))
    lua('screen[1].sidebar.visible=true')
    calendar_next = widget_point('screen[1].sidebar_calendar_next_button', x=270)
    pointer("mousemove", *calendar_next, "click", 1)
    wait('return tostring(screen[1].sidebar_calendar_month() ~= ' + repr(expected_month) + ')', '"true"')
