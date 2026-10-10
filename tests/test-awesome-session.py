#!/usr/bin/env python3
"""Runtime smoke test on a private Xvfb server and private D-Bus bus.

Never starts the real session autostart or changes the live display layout.
"""
import os
import ctypes
import re
import signal
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import date, timedelta

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "dotfiles/.config/awesome/rc.lua"


def main():
    if "--inside" not in sys.argv:
        return subprocess.call(["dbus-run-session", "--", sys.executable, __file__, "--inside"])
    processes = []
    with tempfile.TemporaryDirectory(prefix="awesome-smoke-") as directory:
        directory = Path(directory)
        logfile = directory / "awesome.log"
        testhome = directory / "home"
        helpers = testhome / ".local/bin"
        helpers.mkdir(parents=True)
        (testhome / ".local/share/wallpapers").mkdir(parents=True)
        (testhome / "Documents").mkdir()
        todo_path = testhome / "Documents/todo.md"
        todo_path.write_text(
            "# TODO\n## Sidebar\n- First item\n- Second item\n- Third item\n"
            "- Fourth item\n- Fifth item\n- Ignore this sixth item\n## Other\n- Outside section\n")
        today = date.today()
        (testhome / "Documents/calendar.md").write_text(
            f"{today - timedelta(days=1)} 17:30 Yesterday event\n"
            f"{today} 08:15-09:00 Today event\n"
            f"{today} visit: 12:30, Today appointment\n"
            f"{today + timedelta(days=1)} 07:30 First future event\n"
            f"{today + timedelta(days=1)} 12:00 Second future event\n"
            f"{today + timedelta(days=2)} 19:00 Third future event\n"
            f"{today + timedelta(days=3)} 09:00 Omit fourth future event\n")
        shutil.copy2(ROOT / "dotfiles/.local/bin/openbox-lock", helpers / "openbox-lock")
        crypto_helper = helpers / "crypto-prices"
        crypto_helper.write_text("#!/bin/sh\nprintf '%s\\n' '#[fg=#006400]BTC #[fg=#00ff41,bold]$97.123 #[fg=#006400]ETH #[fg=#00ff41,bold]$3.456 #[fg=#006400]LTC #[fg=#00ff41,bold]$123,45'\n")
        crypto_helper.chmod(0o755)
        codex_helper = helpers / "codex-usage"
        codex_helper.write_text("#!/bin/sh\nprintf '%s\\t%s\\n' 'C 5h #[fg=#00ff41]84%#[fg=#006400]@#[fg=#00ff41]Sat 13:46 7d #[fg=#00ff41]33%#[fg=#006400]@#[fg=#00ff41]Wed 06:41' 'Sat 24.10 13:46 · Tue 27.10 13:46 · Fri 30.10 13:46'\n")
        codex_helper.chmod(0o755)
        shutil.copy2(ROOT / "dotfiles/.local/share/wallpapers/lock-win98-tux.png",
                     testhome / ".local/share/wallpapers/lock-win98-tux.png")
        shutil.copy2(ROOT / "dotfiles/.local/share/wallpapers/aurora-longhorn.png",
                     testhome / ".local/share/wallpapers/aurora-longhorn.png")
        icon_source = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "icons/hicolor/32x32/apps/vax-tux-start.png"
        icon_target = testhome / ".local/share/icons/hicolor/32x32/apps/vax-tux-start.png"
        icon_target.parent.mkdir(parents=True)
        shutil.copy2(icon_source, icon_target)
        bin_dir = directory / "bin"
        bin_dir.mkdir()
        for name, source in {
            "wpctl": '#!/bin/sh\necho "Volume: 0.42"\n',
            "pavucontrol": '#!/bin/sh\necho mixer >> "$TEST_ACTIONS"\n',
        }.items():
            executable = bin_dir / name
            executable.write_text(source)
            executable.chmod(0o755)
        volume_helper = helpers / "openbox-volume"
        volume_helper.write_text('#!/bin/sh\necho "$1" >> "$TEST_ACTIONS"\n')
        volume_helper.chmod(0o755)
        env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}", TEST_ACTIONS=str(directory / "actions"), AWESOME_TEST_MODE="1", NO_AT_BRIDGE="1", GIO_USE_VFS="local",
                   HOME=str(testhome), XDG_CONFIG_HOME=str(testhome / ".config"),
                   XDG_DATA_HOME=str(testhome / ".local/share"),
                   XDG_STATE_HOME=str(testhome / ".local/state"), XDG_RUNTIME_DIR=str(directory))
        lock_pids = []
        env.pop("XAUTHORITY", None)
        server = subprocess.Popen(["Xvfb", "-displayfd", "1", "-screen", "0", "1280x800x24",
                                   "-nolisten", "tcp", "-ac"], stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, text=True)
        processes.append(server)
        try:
            number = server.stdout.readline().strip()
            assert number.isdigit(), "Xvfb failed to allocate a display"
            env["DISPLAY"] = ":" + number
            with logfile.open("w") as log:
                wm = subprocess.Popen(["awesome", "-c", str(CONFIG)], env=env,
                                      stdout=log, stderr=log)
                processes.append(wm)

                def lua(code):
                    result = subprocess.run(["awesome-client", code], env=env,
                                            capture_output=True, text=True, timeout=3)
                    assert result.returncode == 0, result.stderr
                    assert "Error" not in result.stdout, result.stdout
                    return result.stdout

                def wait(code, expected):
                    deadline = time.monotonic() + 8
                    last = ""
                    while time.monotonic() < deadline:
                        try:
                            last = lua(code)
                            if expected in last:
                                return last
                        except (AssertionError, subprocess.TimeoutExpired):
                            pass
                        time.sleep(0.1)
                    diagnostic = lua('local r=""; for _,c in ipairs(client.get()) do r=r..tostring(c.class)..":"..c.type..":"..c.x..","..c.y..","..c.width..","..c.height..":screen="..c.screen.index..":visible="..tostring(c:isvisible()); for k,v in pairs(c:struts()) do r=r..":"..k.."="..v end; r=r.."\\n" end; return r')
                    raise AssertionError(f"Expected {expected!r}: {code}\n{last}\n{diagnostic}\n{logfile.read_text()}")

                def press(keys):
                    subprocess.run(["xdotool", "key", "--clearmodifiers", keys], env=env,
                                   check=True, timeout=3)
                    time.sleep(0.15)

                wait('return #screen[1].tags', '4')
                assert 'floating' in lua('return require("awful").layout.getname(require("awful").layout.get(screen[1]))')
                press('super+space')
                assert 'tile' in lua('return require("awful").layout.getname(require("awful").layout.get(screen[1]))')
                press('super+2')
                assert 'floating' in lua('return require("awful").layout.getname(require("awful").layout.get(screen[1]))')
                press('super+space')
                assert 'tile' in lua('return require("awful").layout.getname(require("awful").layout.get(screen[1]))')
                press('super+1')
                assert 'tile' in lua('return require("awful").layout.getname(require("awful").layout.get(screen[1]))')
                press('super+space')
                press('super+2')
                assert 'tile' in lua('return require("awful").layout.getname(require("awful").layout.get(screen[1]))')
                press('super+space')
                press('super+1')
                assert 'floating' in lua('return require("awful").layout.getname(require("awful").layout.get(screen[1]))')
                wait('return screen[1].workarea.y', '30')
                assert 'true' in lua('local p=screen[1].panel; return p.visible and p.height == 30 and p.position == "top"')
                assert 'true' in lua('local s=screen[1]; local b=s.sidebar; return b and b.visible and s.sidebar_header and s.sidebar_header.forced_height == 26 and s.sidebar_mode == 3 and b.ontop and b:struts().right == 300 and b.width == 300 and b.border_width == 0 and s.sidebar_cpu and s.sidebar_battery and s.sidebar_volume and s.sidebar_quake2_button and s.sidebar_sleep_button and s.sidebar_trash_icon and s.sidebar_trash_state and s.sidebar_trash_timer.timeout == 30 and s.sidebar_media_text and s.sidebar_root_text and s.sidebar_weather_text and s.sidebar_crypto_card.forced_height == 62 and s.sidebar_crypto_timer.timeout == 60 and s.sidebar_codex_card.forced_height == 132 and s.sidebar_codex_timer.timeout == 60 and s.sidebar_audio_header == nil and s.sidebar_wallpaper_preview and s.sidebar_todo_card and #s.sidebar_todo_entries == 5 and s.sidebar_todo_entries[5] == "Fifth item" and s.sidebar_calendar_card and #s.sidebar_calendar_entries == 6 and s.sidebar_calendar_entries[1].day == "past" and s.sidebar_calendar_entries[2].time == "08:15-09:00" and s.sidebar_calendar_entries[3].text == "visit: Today appointment" and s.sidebar_calendar_entries[6].text == "Third future event" and s.sidebar_todo_timer.timeout == 60 and s.sidebar_calendar_timer.timeout == 60 and s.panel_cpu == nil and s.panel_battery == nil and s.panel_volume == nil and s.workarea.width == s.geometry.width-300 and b.x+b.width == s.geometry.x+s.geometry.width and b.y == s.geometry.y+30 and b.height == s.geometry.height-30')
                assert 'true' in lua('local s=screen[1]; local expected=s.sidebar_mouse_battery.visible and 205 or 187; if s.sidebar_stats_card.forced_height ~= expected or #s.sidebar_progress_bars ~= 8 then return false end; for _,b in ipairs(s.sidebar_progress_bars) do if b.forced_height ~= 7 then return false end end; return true')
                wait('return screen[1].sidebar_crypto_prices.BTC.text.."|"..screen[1].sidebar_crypto_prices.ETH.text.."|"..screen[1].sidebar_crypto_prices.LTC.text', '"97.123|3.456|123,45"')
                wait('return screen[1].sidebar_codex_5h.summary.markup', '5h  84% left · Sat 13:46')
                wait('return screen[1].sidebar_codex_7d.summary.markup', '7d  33% left · Wed 06:41')
                wait('return screen[1].sidebar_codex_resets.markup', 'Sat 24.10 13:46')
                assert 'true' in lua('local m=screen[1].sidebar_codex_resets.markup; return select(2,m:gsub("\\n", "")) == 2 and m:find("Fri 30.10 13:46", 1, true) ~= nil and not m:find("Free resets", 1, true)')
                assert '8pt' in lua('return screen[1].sidebar_codex_resets.markup')
                codex_5h_bar = lua('return tostring(screen[1].sidebar_codex_5h.remaining)')
                codex_7d_bar = lua('return tostring(screen[1].sidebar_codex_7d.remaining)')
                assert '84' in codex_5h_bar, codex_5h_bar
                assert '33' in codex_7d_bar, codex_7d_bar
                wait('return tostring(screen[1].sidebar_scroll_max() > 0)', '"true"')
                subprocess.run(["xdotool", "mousemove", "1100", "720", "click", "5"], env=env, check=True)
                wheel_state = lua('return tostring(screen[1].sidebar_scroll_position > 0)')
                assert 'true' in wheel_state, wheel_state
                lua('screen[1].sidebar_scroll_by(-10000)')
                wait('return tostring(screen[1].sidebar_scroll_offset() == 0)', '"true"')
                subprocess.run(["xdotool", "mousemove", "1030", "794", "mousedown", "1",
                                "mousemove", "1220", "794", "mouseup", "1"],
                               env=env, check=True, timeout=5)
                slider_state = lua('return tostring(screen[1].sidebar_scroll_position > 0)..":"..tostring(not mousegrabber.isrunning())')
                assert 'true:true' in slider_state, slider_state
                lua('screen[1].sidebar_scroll_by(-10000)')
                subprocess.run(["xdotool", "mousemove", "1130", "140", "click", "1"], env=env, check=True)
                wait('return screen[1].sidebar_clock_mode', 'text')
                lua('screen[1].sidebar_clock_toggle()')
                wait('return screen[1].sidebar_clock_mode', 'analog')
                lua('screen[1].sidebar_scroll_before_todo = screen[1].sidebar_scroll_max()')
                todo_path.write_text("# TODO\n## Sidebar\n- Refreshed item\n")
                lua('screen[1].sidebar_todo_refresh()')
                wait('return tostring(screen[1].sidebar_scroll_max() < screen[1].sidebar_scroll_before_todo)', '"true"')
                todo_refresh_result = lua('return tostring(#screen[1].sidebar_todo_entries)..":"..tostring(screen[1].sidebar_todo_entries[1])')
                assert '1:Refreshed item' in todo_refresh_result, todo_refresh_result
                press('super+shift+s')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_mode == 0 and not s.sidebar.visible and s.sidebar:struts().right == 0 and s.workarea.width == s.geometry.width')
                press('super+shift+s')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_mode == 1 and s.sidebar.visible and not s.sidebar.ontop and s.sidebar:struts().right == 0 and s.workarea.width == s.geometry.width')
                press('super+shift+s')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_mode == 2 and s.sidebar.visible and s.sidebar.ontop and s.workarea.width == s.geometry.width')
                press('super+shift+s')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_mode == 3 and s.sidebar.visible and s.sidebar.ontop and s.sidebar:struts().right == 300 and s.workarea.width == s.geometry.width - 300')
                press('super+shift+s')
                hidden_sidebar = lua('local s=screen[1]; return tostring(s.sidebar_mode)..":"..tostring(s.sidebar.visible)..":"..tostring(s.sidebar:struts().right)..":"..s.workarea.width..":"..s.geometry.width')
                assert '0:false:0:1280:1280' in hidden_sidebar, hidden_sidebar
                wallpaper = subprocess.run(["xprop", "-root", "_XROOTPMAP_ID"], env=env,
                                           capture_output=True, text=True, check=True, timeout=3).stdout
                assert "PIXMAP" in wallpaper, wallpaper
                wait('return screen[1].sidebar_root_text.text', 'Free /')
                assert 'aurora-longhorn.png' in lua('return screen[1].sidebar_wallpaper_name.text')
                next_buttons = lua('return tostring(screen[1].sidebar_wallpaper_count)..":"..#screen[1].sidebar_wallpaper_next:buttons()')
                assert '2:4' in next_buttons, next_buttons
                lua('screen[1].sidebar_wallpaper_next_action()')
                wallpaper_name = lua('return tostring(screen[1].sidebar_wallpaper_index)..":"..screen[1].sidebar_wallpaper_name.text')
                assert '2:lock-win98-tux.png' in wallpaper_name, wallpaper_name
                lua('screen[1].sidebar_wallpaper_previous_action(); screen[1].sidebar_wallpaper_apply()')
                assert (testhome / ".local/state/awesome/wallpaper").read_text().strip().endswith("aurora-longhorn.png")
                wait('return tostring(screen[1].sidebar_volume_text.markup):find("42%", 1, true) and "42%" or "pending"', '"42%"')
                assert '8pt' in lua('return screen[1].sidebar_volume_text.markup')
                assert 'true' in lua('local p=screen[1].panel_clock; local s=screen[1].sidebar_clock; return p.text:match("%d%d:%d%d") ~= nil and p.forced_width == 58 and type(s.draw) == "function" and s.current_time.hour ~= nil and s.current_time.min ~= nil and s.current_time.sec ~= nil and screen[1].sidebar_clock_mode == "analog" and not screen[1].sidebar_digital_time.visible and screen[1].sidebar_clock_card.forced_height == 142 and screen[1].sidebar_date.text:find(os.date("%a"), 1, true) ~= nil')
                lua('screen[1].sidebar_clock_toggle()')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_clock_mode == "text" and s.sidebar_digital_time.visible and not s.sidebar_clock.visible and s.sidebar_clock_card.forced_height == 66 and s.sidebar_digital_time.text:match("%d%d:%d%d:%d%d") ~= nil')
                lua('screen[1].sidebar_clock_toggle()')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_clock_mode == "analog" and not s.sidebar_digital_time.visible and s.sidebar_clock.visible and s.sidebar_clock_card.forced_height == 142')
                lua('for _,b in ipairs(screen[1].sidebar_volume:buttons()) do if b.button == 3 then b:emit_signal("press") end end')
                lua('for _,b in ipairs(screen[1].sidebar_volume:buttons()) do if b.button == 1 then b:emit_signal("press") end end')
                time.sleep(0.3)
                actions = (directory / "actions").read_text().splitlines()
                assert all(action in actions for action in ("mute", "mixer")), actions
                assert "up" not in actions and "down" not in actions, actions
                xlib = ctypes.CDLL("libX11.so.6")
                xlib.XOpenDisplay.argtypes = [ctypes.c_char_p]
                xlib.XOpenDisplay.restype = ctypes.c_void_p
                xlib.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
                xlib.XInternAtom.restype = ctypes.c_ulong
                xlib.XGetSelectionOwner.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
                xlib.XGetSelectionOwner.restype = ctypes.c_ulong
                xlib.XCloseDisplay.argtypes = [ctypes.c_void_p]
                display = xlib.XOpenDisplay(env["DISPLAY"].encode())
                assert display
                try:
                    selection = xlib.XInternAtom(display, b"_NET_SYSTEM_TRAY_S0", 0)
                    assert xlib.XGetSelectionOwner(display, selection), 'Native tray has no XEmbed owner'
                finally:
                    xlib.XCloseDisplay(display)
                subprocess.run(["xdotool", "mousemove", "30", "15", "click", "1"], env=env, check=True)
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"true"')
                assert 'true' in lua('local m=screen[1].start_menu; return m.x == screen[1].geometry.x + 2 and m.y == screen[1].geometry.y + screen[1].panel.height and m.theme.width == 270 and m.theme.height == 28 and m.theme.border_width == 1 and m.theme.bg_normal ~= "#c0c0c0"')
                press('Escape')
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"false"')
                subprocess.run(["xdotool", "mousemove", "900", "700", "click", "1"], env=env, check=True)
                subprocess.run(["xdotool", "mousemove", "30", "15", "click", "1"], env=env, check=True)
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"true"')
                subprocess.run(["xdotool", "mousemove", "900", "700", "click", "1"], env=env, check=True)
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"false"')
                press('super')
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"true"')
                press('super')
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"false"')
                press('super+2')
                wait('return screen[1].selected_tag.index', '2')
                assert 'false' in lua('return tostring(screen[1].start_menu.wibox.visible)')
                press('super+1')
                wait('return screen[1].selected_tag.index', '1')
                assert 'false' in lua('return tostring(screen[1].start_menu.wibox.visible)')
                subprocess.run(["xdotool", "mousemove", "1258", "15", "click", "1"], env=env, check=True)
                wait('return tostring(screen[1].panel_calendar.visible)', '"true"')
                subprocess.run(["xdotool", "click", "1"], env=env, check=True)
                wait('return tostring(screen[1].panel_calendar.visible)', '"false"')
                desktops = subprocess.run(["xprop", "-root", "_NET_NUMBER_OF_DESKTOPS"], env=env,
                                          capture_output=True, text=True, check=True, timeout=3).stdout
                assert desktops.strip().endswith("= 4"), desktops
                for name in ("AwesomeSmokeA", "AwesomeSmokeB"):
                    processes.append(subprocess.Popen(["xmessage", "-name", name, "-geometry", "400x200", name],
                                                       env=env, stdout=log, stderr=log))
                wait('local n=0; for _,c in ipairs(client.get()) do if c.class == "Xmessage" then n=n+1 end end; return n', '2')
                titlebar_state = lua('local r=""; for _,c in ipairs(client.get()) do if c.class == "Xmessage" then local top=c._private and c._private.titlebars and c._private.titlebars.top; r=r..tostring(c.floating)..":"..tostring(top and top.args.size)..":"..tostring(c.y)..";" end end; return r')
                assert titlebar_state.count("true:26:") == 2, (titlebar_state, logfile.read_text())
                original_geometry = lua('local c; for _,x in ipairs(client.get()) do if x.instance == "AwesomeSmokeA" then c=x; break end end; return c.x..","..c.y..","..c.width..","..c.height')
                press('super+space')
                assert 'tile' in lua('return require("awful").layout.getname(require("awful").layout.get(screen[1]))')
                assert 'false' in lua('for _,c in ipairs(client.get()) do if c.instance == "AwesomeSmokeA" then return tostring(c.floating) end end')
                press('super+space')
                assert 'floating' in lua('return require("awful").layout.getname(require("awful").layout.get(screen[1]))')
                restored_geometry = lua('local c; for _,x in ipairs(client.get()) do if x.instance == "AwesomeSmokeA" then c=x; break end end; return c.x..","..c.y..","..c.width..","..c.height')
                assert original_geometry == restored_geometry, (original_geometry, restored_geometry)
                drag_coords = lua('local c; for _,x in ipairs(client.get()) do if x.instance == "AwesomeSmokeA" then c=x; break end end; return (c.x+80)..","..(c.y+80)')
                x, y = re.search(r'"(\d+),(\d+)"', drag_coords).groups()
                subprocess.run(["xdotool", "keydown", "Super_L", "mousemove", x, y, "mousedown", "1",
                                "mousemove_relative", "--sync", "15", "0", "keyup", "Super_L", "mouseup", "1"],
                               env=env, check=True, timeout=5)
                time.sleep(0.15)
                assert 'false' in lua('return tostring(screen[1].start_menu.wibox.visible)')
                subprocess.run(["xdotool", "mousemove", "30", "15", "click", "1"], env=env, check=True)
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"true"')
                outside_coords = lua('local c; for _,x in ipairs(client.get()) do if x.class == "Xmessage" then c=x; break end end; return (c.x+40)..","..(c.y+50)')
                x, y = re.search(r'"(\d+),(\d+)"', outside_coords).groups()
                subprocess.run(["xdotool", "mousemove", x, y, "click", "1"], env=env, check=True)
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"false"')
                lua('for _,c in ipairs(client.get()) do if c.instance == "AwesomeSmokeA" then c.minimized=false; client.focus=c; c:raise() end end')
                wait('return client.focus and client.focus.instance', '"AwesomeSmokeA"')
                minimize_coords = lua('local c; for _,x in ipairs(client.get()) do if x.instance == "AwesomeSmokeA" then c=x end end; return (c.x+c.width-54)..","..(c.y+13)')
                x, y = re.search(r'"(\d+),(\d+)"', minimize_coords).groups()
                subprocess.run(["xdotool", "mousemove", x, y, "click", "1"], env=env, check=True)
                wait('for _,c in ipairs(client.get()) do if c.instance == "AwesomeSmokeA" then return tostring(c.minimized) end end', '"true"')
                lua('for _,c in ipairs(client.get()) do if c.instance == "AwesomeSmokeA" then c.minimized=false; client.focus=c; c:raise() end end')
                wait('for _,c in ipairs(client.get()) do if c.instance == "AwesomeSmokeA" then return tostring(c.minimized) end end', '"false"')
                subprocess.run(["xdotool", "mousemove", "84", "15", "click", "5"], env=env, check=True)
                wait('return screen[1].selected_tag.name', '"2"')
                subprocess.run(["xdotool", "click", "4"], env=env, check=True)
                wait('return screen[1].selected_tag.name', '"1"')
                press('super+2')
                wait('return screen[1].selected_tag.name', '"2"')
                press('super+1')
                wait('return screen[1].selected_tag.name', '"1"')
                lua('for _,c in ipairs(client.get()) do if c.instance == "AwesomeSmokeA" then c:emit_signal("request::activate", "test", {raise=true}) end end')
                press('super+shift+3')
                wait('return client.focus and client.focus.first_tag.name', '"3"')
                wait('return screen[1].selected_tag.name', '"3"')
                size_before = lua('local c=client.focus; return c.width..","..c.height')
                old_width, old_height = map(int, re.search(r'"(\d+),(\d+)"', size_before).groups())
                coords = lua('local c=client.focus; return (c.x+c.width-5)..","..(c.y+c.height-4)')
                x, y = re.search(r'"(\d+),(\d+)"', coords).groups()
                subprocess.run(["xdotool", "mousemove", x, y, "mousedown", "1"], env=env, check=True)
                time.sleep(0.15)
                subprocess.run(["xdotool", "mousemove_relative", "--", "80", "50"], env=env, check=True)
                time.sleep(0.15)
                subprocess.run(["xdotool", "mouseup", "1"], env=env, check=True)
                assert 'true' in lua(f'local c=client.focus; return c.width > {old_width} and c.height > {old_height}')
                coords = lua('local c=client.focus; return (c.x + math.floor(c.width/2))..","..(c.y + 12)')
                x, y = re.search(r'"(\d+),(\d+)"', coords).groups()
                subprocess.run(["xdotool", "mousemove", x, y, "click", "--repeat", "2", "--delay", "100", "1"],
                               env=env, check=True, timeout=3)
                wait('return client.focus and tostring(client.focus.maximized)', '"true"')
                maximum = lua('local c=client.focus; local _,bottom=c:titlebar_bottom(); local a=c.screen.workarea; return c.border_width == 0 and bottom == 0 and c.x == a.x and c.y == a.y and c.width == a.width and c.height == a.height')
                assert 'true' in maximum, lua('local c=client.focus; local _,b=c:titlebar_bottom(); local a=c.screen.workarea; return "border="..c.border_width.." bottom="..b.." c="..c.x..","..c.y..","..c.width..","..c.height.." area="..a.x..","..a.y..","..a.width..","..a.height')
                lua('client.focus.maximized=false')
                assert 'true' in lua('local c=client.focus; local _,b=c:titlebar_bottom(); return c.border_width == 2 and b == 10')
                press('super+shift+s')
                press('super+shift+s')
                press('super+shift+s')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_mode == 3 and s.sidebar.visible and s.workarea.width == s.geometry.width-300')
                press('alt+F11')
                wait('return client.focus and tostring(client.focus.fullscreen)', '"true"')
                assert 'true' in lua('local c=client.focus; local s=c.screen; local a=s.geometry; return c.border_width == 0 and c.x == a.x and c.y == a.y and c.width == a.width and c.height == a.height and not s.panel.visible and not s.sidebar.visible and s.sidebar:struts().right == 0 and s.workarea.width == a.width')
                press('alt+F11')
                wait('return client.focus and tostring(client.focus.fullscreen)', '"false"')
                wait('return tostring(screen[1].panel.visible)', '"true"')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_mode == 3 and s.sidebar.visible and s.sidebar:struts().right == 300 and s.workarea.width == s.geometry.width-300')
                press('super+shift+s')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_mode == 0 and not s.sidebar.visible and s.workarea.width == s.geometry.width')
                lua('for _,c in ipairs(client.get()) do if c.instance == "AwesomeSmokeB" then c.fullscreen=true end end')
                wait('return tostring(screen[1].panel.visible)', '"false"')
                lua('for _,c in ipairs(client.get()) do if c.instance == "AwesomeSmokeB" then c:kill() end end')
                wait('return tostring(screen[1].panel.visible)', '"true"')
                assert 'false' in lua('return tostring(screen[1].start_menu.wibox.visible)')
                press('super+Left')
                assert 'true' in lua('local c=client.focus; return c.x == screen[1].workarea.x and c.y >= 30 and c.width <= 640')
                press('super+d')
                wait('for _,c in ipairs(client.get()) do if c.instance == "AwesomeSmokeA" then return tostring(c.minimized) end end', '"true"')
                press('super+d')
                wait('for _,c in ipairs(client.get()) do if c.instance == "AwesomeSmokeA" then return tostring(c.minimized) end end', '"false"')
                lua('for _,c in ipairs(client.get()) do if c.instance == "AwesomeSmokeA" then c:emit_signal("request::activate", "test", {raise=true}) end end')
                press('alt+F4')
                wait('local n=0; for _,c in ipairs(client.get()) do if c.class == "Xmessage" then n=n+1 end end; return n', '0')
                press('super+ctrl+r')
                time.sleep(0.5)
                wait('return #screen[1].tags', '4')
                assert 'true' in lua('return require("awful").layout.get(screen[1]) == require("awful").layout.suit.floating')
                assert "awesome config:" not in logfile.read_text(), logfile.read_text()
                wait('return screen[1].workarea.y', '30')
                assert wm.poll() is None, logfile.read_text()
                press('super+p')
                wait('return tostring(__awesome_display_menu.wibox.visible)', '"true"')
                assert 'true' in lua('local m=__awesome_display_menu; return m.theme.width == 270 and m.theme.height == 28 and m.theme.border_width == 1 and m.theme.bg_normal ~= "#c0c0c0"')
                press('Escape')
                wait('return tostring(__awesome_display_menu.wibox.visible)', '"false"')
                press('super+shift+q')
                wait('return tostring(__awesome_quit_confirmation.wibox.visible)', '"true"')
                press('Escape')
                wait('return tostring(__awesome_quit_confirmation.wibox.visible)', '"false"')
                assert wm.poll() is None
                # Exercise the actual Win+L binding and foreground i3lock, only on Xvfb.
                press('super+l')
                deadline = time.monotonic() + 8
                while time.monotonic() < deadline and not lock_pids:
                    candidates = subprocess.run(["pgrep", "-x", "i3lock"], capture_output=True, text=True).stdout.split()
                    for pid in candidates:
                        try:
                            environment = Path(f"/proc/{pid}/environ").read_bytes().split(b'\0')
                            if ("DISPLAY=" + env["DISPLAY"]).encode() in environment:
                                lock_pids.append(int(pid))
                        except (PermissionError, FileNotFoundError):
                            pass
                    time.sleep(0.1)
                assert lock_pids, 'Win+L did not start i3lock on the private display'
                time.sleep(0.3)
                windows = subprocess.run(["xdotool", "search", "--class", "i3lock"], env=env,
                                         capture_output=True, text=True, timeout=3)
                assert windows.returncode == 0 and windows.stdout.strip(), 'i3lock did not map a lock window'
                # A simultaneous xss-lock/Win+L invocation must not launch a second locker.
                duplicate = subprocess.run(["sh", str(helpers / "openbox-lock")], env=env, timeout=3)
                assert duplicate.returncode == 0
                for pid in lock_pids:
                    try:
                        os.kill(pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                lock_pids.clear()
                time.sleep(0.5)
                press('super+shift+q')
                wait('return tostring(__awesome_quit_confirmation.wibox.visible)', '"true"')
                press('Escape')
                assert wm.poll() is None, 'Escape from quit confirmation must cancel'
                lua('awesome.quit()')
                assert wm.wait(timeout=5) == 0
                print("PASS: native panel/sidebar widgets, Start/calendar/tray, wallpaper, corner resize, borderless maximize/fullscreen, workspaces, Win+P outputs menu, confirmed Win+Shift+Q, reload and Win+L/i3lock")
        finally:
            for pid in lock_pids:
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
            for process in reversed(processes):
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
