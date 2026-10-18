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

    def popup_widget_point(expression):
        position = lua('local s=screen[1]; local p=s.sidebar_news_popup; local target=' + expression + '; '
                       'local function find(h) if h:get_widget()==target then local w,hgt=h:get_size(); '
                       'local x,y,ww,hh=h:get_matrix_to_device():transform_rectangle(0,0,w,hgt); '
                       'return table.concat({math.floor(p.x+x+ww/2),math.floor(p.y+y+hh/2),ww,hh},":") end; '
                       'for _,child in ipairs(h:get_children()) do local result=find(child); if result then return result end end end; '
                       'return find(p._drawable._widget_hierarchy) or "missing"')
        match = __import__("re").search(r"(\d+):(\d+):([\d.]+):([\d.]+)", position)
        assert match, f"Could not locate popup widget {expression}: {position}"
        x, y, width, height = match.groups()
        assert float(width) > 0 and float(height) > 0, f"Popup widget has empty geometry: {position}"
        return int(x), int(y)

    try:
        assert 'true' in lua('for _,k in ipairs(root.keys()) do if k.key=="Escape" then return false end end; return true')
        initial = lua('local s=screen[1]; local n=s.sidebar_news; return tostring(n~=nil and n.popup==s.sidebar_news_popup and s.sidebar_news_timer.timeout==1800 and n.filtered_items and #n.filtered_items()==8)')
        assert 'true' in initial, initial
        assert 'true' in lua('local s=screen[1]; return s.sidebar_news.unread_label.markup:find("8 unread",1,true)~=nil and s.sidebar_sections.news and s.sidebar_enabled_sections.news')
        assert 'true' in lua('local r=screen[1].sidebar_news.filter_rows:get_children(); return #r==1 and #r[1]:get_children()==6')
        lua('require("awful").spawn({"xmessage", "-name", "NewsOutsideClickTest", "-geometry", "320x180+100+100", "Outside click target"})')
        wait('for _,c in ipairs(client.get()) do if c.instance=="NewsOutsideClickTest" then return "ready" end end; return "waiting"', '"ready"')
        point = sidebar_news_button_point()
        pointer("mousemove", *point, "click", 1)
        wait('return tostring(screen[1].sidebar_news_popup.visible)', '"true"')
        assert 'true' in lua('local s=screen[1]; local n=s.sidebar_news; local p=n.popup; return n.open_button.get_text()=="Close" and p.ontop and p.width<=520 and p.x+p.width==s.sidebar.x and p.y==s.sidebar.y and p.height==s.sidebar.height and n.scrollbar.forced_width==14 and s.sidebar:struts().right==300 and s.workarea.width==s.geometry.width-300')
        assert 'true' in lua('for _,k in ipairs(root.keys()) do if k.key=="Escape" then return false end end; return true')
        scrollbar_point = popup_widget_point('screen[1].sidebar_news.scrollbar')
        if capture: capture("sidebar-news-popup")

        stage = "category filters and popup scrolling"
        assert 'true' in lua('return screen[1].sidebar_news.category_buttons.community ~= nil')
        lua('local s=screen[1]; s.sidebar_news.category_buttons.community._sidebar_keyboard_action()')
        assert 'true' in lua('return #screen[1].sidebar_news.filtered_items()==0')
        lua('local s=screen[1]; s.sidebar_news.category_buttons.cinema._sidebar_keyboard_action()')
        assert 'true' in lua('return #screen[1].sidebar_news.filtered_items()==1')
        lua('local s=screen[1]; s.sidebar_news.category_buttons.general._sidebar_keyboard_action()')
        assert 'true' in lua('return #screen[1].sidebar_news.filtered_items()==7')
        lua('local s=screen[1]; s.sidebar_news.category_buttons.all._sidebar_keyboard_action()')
        assert 'true' in lua('return #screen[1].sidebar_news.filtered_items()==8')
        scrollbar_point = popup_widget_point('screen[1].sidebar_news.scrollbar')
        pointer("mousemove", *scrollbar_point)
        pointer("mousedown", 1)
        pointer("mousemove", scrollbar_point[0], scrollbar_point[1] + 180)
        pointer("mouseup", 1)
        wait('return tostring(screen[1].sidebar_news.scroll_offset()>0)', '"true"')
        lua('screen[1].sidebar_news.scroll_by(-10000)')
        scroll_point = popup_widget_point('screen[1].sidebar_news.viewport')
        scroll_started = time.monotonic()
        pointer("mousemove", *scroll_point, "click", 5, delay=0)
        wheel_offset = float(__import__("re").search(
            r'"([0-9.]+)"', lua('return tostring(screen[1].sidebar_news.scroll_offset())')).group(1))
        assert wheel_offset >= 77, f"Wheel scroll did not respond immediately: {wheel_offset}"
        assert time.monotonic() - scroll_started < 0.75, "Wheel scroll response took too long"
        pointer("mousemove", *scroll_point, "click", 4)
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
        wait('return tostring(screen[1].sidebar_news_popup.visible)', '"true"')
        assert 'true' in lua('for _,k in ipairs(root.keys()) do if k.key=="Escape" then return false end end; return true')

        stage = "Open toggle and X close control"
        lua('screen[1].sidebar_news.open_button._sidebar_keyboard_action()')
        wait('return tostring(not screen[1].sidebar_news_popup.visible and screen[1].sidebar_news.open_button.get_text()=="Open")', '"true"')
        lua('screen[1].sidebar_news.open_button._sidebar_keyboard_action()')
        wait('return tostring(screen[1].sidebar_news_popup.visible and screen[1].sidebar_news.open_button.get_text()=="Close")', '"true"')
        lua('screen[1].sidebar_news.close_button._sidebar_keyboard_action()')
        wait('return tostring(not screen[1].sidebar_news_popup.visible and screen[1].sidebar_news.open_button.get_text()=="Open")', '"true"')

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

        stage = "large inbox uses a bounded visible hierarchy"
        lua('local s=screen[1]; local original=s.sidebar_data.state("news"); '
            'local value={}; for k,v in pairs(original.value) do value[k]=v end; value.items={}; '
            'local template=original.value.items[1]; for i=1,200 do local item={}; '
            'for k,v in pairs(template) do item[k]=v end; item.id="virtual-"..i; '
            'value.items[i]=item end; s.sidebar_news.render({value=value,updated=os.time()})')
        wait('return tostring(screen[1].sidebar_news.visible_row_count>0 and screen[1].sidebar_news.visible_row_count<20)', '"true"')
        lua('screen[1].sidebar_news.scroll_by(5000)')
        wait('return tostring(screen[1].sidebar_news.scroll_offset()>0 and screen[1].sidebar_news.visible_row_count<20)', '"true"')
        lua('local s=screen[1]; s.sidebar_news.render(s.sidebar_data.state("news"))')

        stage = "outside clicks are harmless; X closes"
        pointer("mousemove", 30, 700, "click", 1)
        wait('return tostring(screen[1].sidebar_news_popup.visible)', '"true"')
        pointer("mousemove", 150, 150, "click", 1)
        wait('return tostring(screen[1].sidebar_news_popup.visible)', '"true"')
        lua('for _,c in ipairs(client.get()) do if c.instance=="NewsOutsideClickTest" then c:kill() end end')
        lua('screen[1].sidebar_news.close_button._sidebar_keyboard_action()')
        wait('return tostring(not screen[1].sidebar_news_popup.visible)', '"true"')
        assert 'true' in lua('return screen[1].sidebar_news.open_button.get_text()=="Open"')
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
    finally:
        try:
            lua('for _,c in ipairs(client.get()) do if c.instance=="NewsOutsideClickTest" then c:kill() end end')
        except Exception:
            pass


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
