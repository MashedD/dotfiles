"""Focused private-session checks for sidebar document-opening interactions."""

import time


def verify_news(*, lua, wait, pointer, widget_point, press, actions_file, log_text, capture=None):
    """Exercise the offline RSS popup, filters, scrolling, and persistent actions."""
    stage = "news initial state"
    point = None
    story_id = f"{7:032x}"

    def sidebar_news_button_point():
        expression = 'screen[1].sidebar_news.open_button'
        lua('screen[1].sidebar_scroll_by(-10000)')
        for step in range(20):
            try:
                return widget_point(expression, scroll=0 if step == 0 else 100, x=250)
            except AssertionError:
                continue
        raise AssertionError(f"News action button not visible after scrolling: {expression}")

    try:
        initial = lua('local s=screen[1]; local n=s.sidebar_news; return tostring(n~=nil and n.popup==s.sidebar_news_popup and s.sidebar_news_timer.timeout==1800 and n.filtered_items and #n.filtered_items()==8)')
        assert 'true' in initial, initial
        assert 'true' in lua('local s=screen[1]; return s.sidebar_news.unread_label.markup:find("8 unread",1,true)~=nil and s.sidebar_sections.news and s.sidebar_enabled_sections.news')
        assert 'true' in lua('local r=screen[1].sidebar_news.filter_rows:get_children(); return #r==1 and #r[1]:get_children()==6')
        point = sidebar_news_button_point()
        pointer("mousemove", *point, "click", 1)
        wait('return tostring(screen[1].sidebar_news_popup.visible)', '"true"')
        assert 'true' in lua('local s=screen[1]; local p=s.sidebar_news_popup; return p.ontop and p.width<=520 and p.x+p.width<=s.sidebar.x and p.y>=s.geometry.y and p.y+p.height<=s.geometry.y+s.geometry.height and s.sidebar:struts().right==300 and s.workarea.width==s.geometry.width-300')
        if capture: capture("sidebar-news-popup")

        stage = "category filters and popup scrolling"
        assert 'true' in lua('return screen[1].sidebar_news.category_buttons.community ~= nil')
        lua('local s=screen[1]; s.sidebar_news.category_buttons.community._sidebar_keyboard_action()')
        assert 'true' in lua('return #screen[1].sidebar_news.filtered_items()==0')
        lua('local s=screen[1]; s.sidebar_news.category_buttons.cinema._sidebar_keyboard_action()')
        assert 'true' in lua('return #screen[1].sidebar_news.filtered_items()==1')
        lua('local s=screen[1]; s.sidebar_news.category_buttons.general._sidebar_keyboard_action()')
        assert 'true' in lua('return #screen[1].sidebar_news.filtered_items()==7')
        pointer("mousemove", screen_popup_x := int(lua('return tostring(screen[1].sidebar_news_popup.x+100)').strip().split('"')[1]),
                screen_popup_y := int(lua('return tostring(screen[1].sidebar_news_popup.y+screen[1].sidebar_news_popup.height-30)').strip().split('"')[1]), "click", 5)
        wait('return tostring(screen[1].sidebar_news.scroll_offset()>0)', '"true"')
        pointer("mousemove", screen_popup_x, screen_popup_y, "click", 4)
        lua('screen[1].sidebar_news.scroll_by(-10000)')

        stage = "open story and mark it read"
        lua(f'screen[1].sidebar_news.item_controls["{story_id}"].open._sidebar_keyboard_action()')
        wait('return tostring(screen[1].sidebar_news.unread_label.markup:find("7 unread",1,true)~=nil)', '"true"')
        assert 'true' in lua(f'return screen[1].sidebar_news.filtered_items and screen[1].sidebar_news.item_controls["{story_id}"]==nil')
        deadline = __import__("time").monotonic() + 3
        while __import__("time").monotonic() < deadline:
            actions = actions_file.read_text()
            if "firefox --new-tab https://example.test/story/7" in actions and f"desktop-news mark-read {story_id}" in actions:
                break
            __import__("time").sleep(0.05)
        assert "firefox --new-tab https://example.test/story/7" in actions_file.read_text(), actions_file.read_text()
        assert f"desktop-news mark-read {story_id}" in actions_file.read_text(), actions_file.read_text()
        press('Escape')
        wait('return tostring(screen[1].sidebar_news_popup.visible)', '"false"')

        stage = "mark unread, mark all read, and remove"
        point = sidebar_news_button_point()
        pointer("mousemove", *point, "click", 1)
        wait('return tostring(screen[1].sidebar_news_popup.visible)', '"true"')
        lua('screen[1].sidebar_news.all_button._sidebar_keyboard_action()')
        lua(f'screen[1].sidebar_news.item_controls["{story_id}"].toggle._sidebar_keyboard_action()')
        wait('return tostring(screen[1].sidebar_news.unread_label.markup:find("8 unread",1,true)~=nil)', '"true"')
        lua('screen[1].sidebar_news.mark_all_button._sidebar_keyboard_action()')
        wait('return tostring(screen[1].sidebar_news.unread_label.markup:find("0 unread",1,true)~=nil)', '"true"')
        lua(f'screen[1].sidebar_news.item_controls["{story_id}"].remove._sidebar_keyboard_action()')
        wait(f'return tostring(screen[1].sidebar_news.item_controls["{story_id}"]==nil)', '"true"')
        assert f"desktop-news mark-unread {story_id}" in actions_file.read_text(), actions_file.read_text()
        assert "desktop-news mark-all-read" in actions_file.read_text(), actions_file.read_text()
        assert f"desktop-news remove {story_id}" in actions_file.read_text(), actions_file.read_text()

        stage = "outside click dismissal"
        pointer("mousemove", 30, 700, "click", 1)
        wait('return tostring(screen[1].sidebar_news_popup.visible)', '"false"')
    except BaseException as error:
        try:
            state = lua('local s=screen[1]; local p=s.sidebar_news_popup; return table.concat({"visible="..tostring(p.visible), '
                        '"geometry="..p.x..","..p.y..","..p.width..","..p.height, '
                        '"open="..tostring(s.sidebar_news.open_button), "controls="..tostring(s.sidebar_news.item_controls["00000000000000000000000000000007"]), '
                        '"items="..tostring(#s.sidebar_news.filtered_items()), "order="..table.concat(s.sidebar_content_order, ","), '
                        '"enabled="..tostring(s.sidebar_enabled_sections.news), "collapsed="..tostring(s.sidebar_sections.news.collapsed), '
                        '"offset="..tostring(s.sidebar_news.scroll_offset()).."/"..tostring(s.sidebar_scroll_max()), '
                        '"sidebar_offset="..tostring(s.sidebar_scroll_offset()), '
                        '"unread="..tostring(s.sidebar_news.unread_label.markup)}, "|")')
        except Exception as diagnostic_error:
            state = f"News state diagnostic failed: {diagnostic_error}"
        raise AssertionError(f"News stage={stage}; point={point}; state={state}; "
                             f"actions={actions_file.read_text()!r}\nAwesome log:\n{log_text()}\n"
                             f"Original failure: {error}") from error


def verify_document_launches(*, lua, wait, pointer, widget_point, actions_file,
                             testhome, log_text):
    """Click one calendar event and one TODO row; diagnose failures at each stage."""
    stage = "verify desktop handler"
    point = None

    def click_and_wait(expected, name, target):
        nonlocal stage, point
        stage = f"click {name}"
        point = target()
        pointer("mousemove", *point, "click", 1)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            actions = actions_file.read_text()
            if expected in actions:
                return
            time.sleep(0.05)
        raise AssertionError(f"No launcher action for {name}: expected={expected!r}; actions={actions_file.read_text()!r}")

    try:
        assert 'true' in lua('local app=require("lgi").Gio.AppInfo.get_default_for_type("text/plain",false); '
                             'return tostring(app and app:get_id()=="awesome-test-opener.desktop")')
        stage = "prepare calendar event"
        lua('screen[1].sidebar_calendar_select_date(os.date("%Y-%m-%d"))')
        wait('return tostring(#screen[1].sidebar_calendar_entries >= 2)', '"true"')
        calendar_path = str(testhome / "Documents/calendar.md")
        click_and_wait(f"open {calendar_path}", "calendar event",
                       lambda: widget_point('screen[1].sidebar_calendar_events_widget:get_children()[1]', x=150))

        stage = "prepare TODO row"
        lua('screen[1].sidebar_todo_refresh()')
        wait('return tostring(#screen[1].sidebar_todo_entries >= 1)', '"true"')
        todo_path = str(testhome / "Documents/todo.md")
        click_and_wait(f"open {todo_path}", "TODO row",
                       lambda: widget_point('screen[1].sidebar_sections.todo.body:get_children()[1]:get_children()[1]',
                                            scroll=-10000, x=150))
    except BaseException as error:
        try:
            state = lua('local s=screen[1]; return table.concat({"calendar="..tostring(#s.sidebar_calendar_entries), '
                        '"todo="..tostring(#s.sidebar_todo_entries), "scroll="..tostring(s.sidebar_scroll_position), '
                        '"grab="..tostring(mousegrabber.isrunning()), "pointer="..tostring(mouse.coords().x)..","..tostring(mouse.coords().y)}, "|")')
        except Exception as diagnostic_error:
            state = f"State diagnostic failed: {diagnostic_error}"
        raise AssertionError(f"Sidebar document stage={stage}; point={point}; state={state}; "
                             f"actions={actions_file.read_text()!r}\nAwesome log:\n{log_text()}\n"
                             f"Original failure: {error}") from error
    finally:
        pointer("mouseup", 1)
