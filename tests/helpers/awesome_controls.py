"""Focused private-session interaction scenarios for Awesome controls."""


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
