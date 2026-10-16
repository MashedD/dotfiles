"""Focused private-session checks for sidebar document-opening interactions."""

import time


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
