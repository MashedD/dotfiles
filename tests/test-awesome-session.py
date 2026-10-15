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


def selection_owner(display_name, name):
    xlib = ctypes.CDLL("libX11.so.6")
    xlib.XOpenDisplay.argtypes = [ctypes.c_char_p]
    xlib.XOpenDisplay.restype = ctypes.c_void_p
    xlib.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
    xlib.XInternAtom.restype = ctypes.c_ulong
    xlib.XGetSelectionOwner.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
    xlib.XGetSelectionOwner.restype = ctypes.c_ulong
    xlib.XCloseDisplay.argtypes = [ctypes.c_void_p]
    display = xlib.XOpenDisplay(display_name.encode())
    if not display:
        return 0
    try:
        return xlib.XGetSelectionOwner(display, xlib.XInternAtom(display, name.encode(), 0))
    finally:
        xlib.XCloseDisplay(display)


def main():
    if "--inside" not in sys.argv:
        return subprocess.call(["dbus-run-session", "--", sys.executable, __file__, "--inside", *sys.argv[1:]])
    composited = "--composited" in sys.argv
    visual = os.environ.get("AWESOME_TEST_VISUAL") == "1"
    if visual:
        missing = [name for name in ("import", "compare") if not shutil.which(name)]
        if missing:
            raise SystemExit("AWESOME_TEST_VISUAL=1 requires ImageMagick commands: " + ", ".join(missing))
    picom_config = ROOT / "dotfiles/.config/picom/picom.conf"
    configuration = picom_config.read_text()
    for option, value in {"backend": '"glx"', "shadow": "false", "fading": "false",
                          "corner-radius": "0", "blur-background": "false",
                          "blur-background-frame": "false", "frame-opacity": "1.0",
                          "active-opacity": "1.0", "inactive-opacity": "1.0"}.items():
        assert re.search(rf"^\s*{re.escape(option)}\s*=\s*{re.escape(value)}\s*;", configuration, re.M), option
    assert not re.search(r"^\s*blur\s*=", configuration, re.M)
    if composited and not shutil.which("picom"):
        raise SystemExit("Composited tests require Picom; no composited verification was performed")
    processes = []
    with tempfile.TemporaryDirectory(prefix="awesome-smoke-") as directory:
        directory = Path(directory)
        visual_dir = directory / "visual-controls"
        if visual: visual_dir.mkdir()
        logfile = directory / "awesome.log"
        testhome = directory / "home"
        helpers = testhome / ".local/bin"
        helpers.mkdir(parents=True)
        (testhome / ".local/share/wallpapers").mkdir(parents=True)
        (testhome / "Pictures/Wallpapers").mkdir(parents=True)
        (testhome / "Documents").mkdir()
        (testhome / ".local/share/applications").mkdir(parents=True)
        programs = testhome / "Programs"
        programs.mkdir()
        old_trezor = programs / "Trezor-Suite-25.0.0-old.AppImage"
        current_trezor = programs / "Trezor-Suite-99.1.0-current.AppImage"
        for image in (old_trezor, current_trezor):
            image.write_text('#!/bin/sh\nprintf "trezor:%s\\n" "$0" >> "$TEST_ACTIONS"\n')
            image.chmod(0o755)
        os.utime(old_trezor, (1, 1))
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
        crypto_helper.write_text("#!/bin/sh\nprintf '%s\\n' '#[fg=#006400]BTC #[fg=#55ff99,bold]$97.123 #[fg=#006400]ETH #[fg=#55ff99,bold]$3.456 #[fg=#006400]LTC #[fg=#55ff99,bold]$123,45'\n")
        crypto_helper.chmod(0o755)
        codex_helper = helpers / "codex-usage"
        codex_helper.write_text("#!/bin/sh\nprintf '%s\\t%s\\n' 'C 5h #[fg=#55ff99]84%#[fg=#006400]@#[fg=#55ff99]Sat 13:46 7d #[fg=#55ff99]33%#[fg=#006400]@#[fg=#55ff99]Wed 06:41' 'Sat 24.10 13:46 · Tue 27.10 13:46 · Fri 30.10 13:46'\n")
        codex_helper.chmod(0o755)
        shutil.copy2(ROOT / "dotfiles/.local/share/wallpapers/lock-win98-tux.png",
                     testhome / ".local/share/wallpapers/lock-win98-tux.png")
        aurora_fixture = ROOT / "dotfiles/.local/share/wallpapers/aurora-longhorn.png"
        if not aurora_fixture.exists():
            # The generated PNG is optional in a source-only checkout.
            aurora_fixture = ROOT / "dotfiles/.local/share/wallpapers/lock-win98-tux.png"
        shutil.copy2(aurora_fixture, testhome / ".local/share/wallpapers/aurora-longhorn.png")
        shutil.copy2(aurora_fixture, testhome / "Pictures/Wallpapers/pictures-wallpaper.png")
        icon_source = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "icons/hicolor/32x32/apps/vax-tux-start.png"
        icon_target = testhome / ".local/share/icons/hicolor/32x32/apps/vax-tux-start.png"
        icon_target.parent.mkdir(parents=True)
        shutil.copy2(icon_source, icon_target)
        weather_response = directory / "weather.json"
        weather_response.write_text('{"current":{"temperature_2m":12,"apparent_temperature":10,"weather_code":3,"wind_speed_10m":9}}\n')
        bin_dir = directory / "bin"
        bin_dir.mkdir()
        for name, source in {
            "wpctl": '#!/bin/sh\necho "Volume: 0.42"\n',
            "curl": '#!/bin/sh\nwhile IFS= read -r line; do printf "%s\\n" "$line"; done < "$TEST_WEATHER_RESPONSE"\n',
            "pavucontrol": '#!/bin/sh\necho mixer >> "$TEST_ACTIONS"\n',
            "playerctl": '#!/bin/sh\nprintf "playerctl %s\\n" "$*" >> "$TEST_ACTIONS"\n',
            "xdg-open": '#!/bin/sh\nprintf "open %s\\n" "$*" >> "$TEST_ACTIONS"\n',
        }.items():
            executable = bin_dir / name
            executable.write_text(source)
            executable.chmod(0o755)
        volume_helper = helpers / "openbox-volume"
        volume_helper.write_text('#!/bin/sh\necho "$1" >> "$TEST_ACTIONS"\n')
        volume_helper.chmod(0o755)
        actions_file = directory / "actions"
        actions_file.touch()
        section_state_file = testhome / ".local/state/awesome/sidebar-sections"
        default_sidebar_order = "order=calendar,todo,quick-launch,system-status,codex,crypto,weather,now-playing,wallpaper\n"
        section_state_file.parent.mkdir(parents=True)
        section_state_file.write_text("crypto\n")
        env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}", TEST_ACTIONS=str(actions_file), TEST_WEATHER_RESPONSE=str(weather_response), AWESOME_TEST_MODE="1", AWESOME_TEST_WEATHER="1", NO_AT_BRIDGE="1", GIO_USE_VFS="local",
                   HOME=str(testhome), XDG_CONFIG_HOME=str(testhome / ".config"),
                   XDG_DATA_HOME=str(testhome / ".local/share"),
                   XDG_STATE_HOME=str(testhome / ".local/state"), XDG_RUNTIME_DIR=str(directory),
                   AWESOME_TEST_HELPERS=str(ROOT / "tests/helpers"))
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
                if composited:
                    compositor = subprocess.Popen(["picom", "--config", str(picom_config),
                                                   "--backend", "xrender"], env=env, stdout=log, stderr=log)
                    processes.append(compositor)
                    deadline = time.monotonic() + 8
                    while not selection_owner(env["DISPLAY"], "_NET_WM_CM_S0"):
                        if compositor.poll() is not None or time.monotonic() >= deadline:
                            raise AssertionError("Private XRender compositor did not start:\n" + logfile.read_text())
                        time.sleep(0.05)
                wm = subprocess.Popen(["awesome", "-c", str(CONFIG)], env=env,
                                      stdout=log, stderr=log)
                processes.append(wm)

                def lua(code):
                    result = subprocess.run(["awesome-client", code], env=env,
                                            capture_output=True, text=True, timeout=3)
                    assert result.returncode == 0, result.stderr
                    assert "Error" not in result.stdout, result.stdout
                    return result.stdout

                def helper(expression):
                    prefix = 'local h=package.loaded.__awesome_test_ui; if not h then h=dofile(os.getenv("AWESOME_TEST_HELPERS").."/awesome-ui.lua"); package.loaded.__awesome_test_ui=h end; '
                    return lua(prefix + expression)

                def pointer(*args):
                    subprocess.run(["xdotool", *map(str, args)], env=env, check=True, timeout=3)
                    time.sleep(0.08)

                def widget_point(expression, scroll=0, x=150):
                    if scroll:
                        lua(f'screen[1].sidebar_scroll_by({scroll})')
                    position = lua('local s=screen[1]; local target=' + expression + '; local x=' + str(x) + '; '
                        'for y=0,s.sidebar.height-1 do for _,v in ipairs(s.sidebar:find_widgets(x,y)) do if v.widget==target then '
                        'return tostring(s.sidebar.x+math.floor(v.x+v.width/2))..":"..tostring(s.sidebar.y+math.floor(v.y+v.height/2)) end end end; return "missing"')
                    match = re.search(r'(\d+):(\d+)', position)
                    assert match, f"Could not locate widget {expression}: {position}"
                    return tuple(map(int, match.groups()))

                def workspace_bounds(index):
                    bounds = lua('local s=screen[1]; local target=s.tags[' + str(index) + ']; '
                        'for y=0,s.panel.height-1 do for x=65,420 do for _,v in ipairs(s.panel:find_widgets(x,y)) do '
                        'local a=v.widget._workspace_action; if a and a.tag==target then '
                        'return table.concat({math.floor(s.panel.x+v.x),math.floor(s.panel.y+v.y),math.ceil(v.width),math.ceil(v.height)}, ":") '
                        'end end end end; return "missing"')
                    match = re.search(r'(\d+):(\d+):(\d+):(\d+)', bounds)
                    assert match, f"Could not locate workspace {index}: {bounds}"
                    return tuple(map(int, match.groups()))

                def workspace_point(index):
                    x, y, width, height = workspace_bounds(index)
                    return x + width // 2, y + height // 2

                def menu_item_point(menu_expression, index, x=100):
                    position = lua('local m=' + menu_expression + '; local item=m.items[' + str(index) + ']; local x=' + str(x) + '; '
                        'for y=0,m.wibox.height-1 do for _,v in ipairs(m.wibox:find_widgets(x,y)) do '
                        'if v.widget==item._background then return tostring(m.wibox.x+math.floor(v.x+v.width/2))..":"..tostring(m.wibox.y+math.floor(v.y+v.height/2)) end end end; return "missing"')
                    match = re.search(r'(\d+):(\d+)', position)
                    assert match, f"Could not locate menu item {index}: {position}"
                    return tuple(map(int, match.groups()))

                def start_bounds():
                    bounds = lua('local s=screen[1]; local w=s.start_button; for y=0,s.panel.height-1 do for x=0,80 do for _,v in ipairs(s.panel:find_widgets(x,y)) do if v.widget==w then return table.concat({math.floor(s.panel.x+v.x),math.floor(s.panel.y+v.y),math.ceil(v.width),math.ceil(v.height)}, ":") end end end end; return "missing"')
                    match = re.search(r'(\d+):(\d+):(\d+):(\d+)', bounds)
                    assert match, f"Could not locate Start button for visual check: {bounds}"
                    return tuple(map(int, match.groups()))

                def capture_start(name):
                    x, y, width, height = start_bounds()
                    path = visual_dir / f"{name}.png"
                    subprocess.run(["import", "-window", "root", "-crop", f"{width}x{height}+{x}+{y}", "+repage", str(path)],
                                   env=env, check=True, timeout=5)
                    return path

                def capture_workspace(index, name):
                    x, y, width, height = workspace_bounds(index)
                    path = visual_dir / f"{name}.png"
                    subprocess.run(["import", "-window", "root", "-crop", f"{width}x{height}+{x}+{y}", "+repage", str(path)],
                                   env=env, check=True, timeout=5)
                    return path

                def compare_visual(left, right, different):
                    result = subprocess.run(["compare", "-metric", "AE", str(left), str(right), "null:"],
                        env=env, capture_output=True, text=True, timeout=5)
                    assert result.returncode in (0, 1), result.stderr
                    match = re.search(r"[0-9]+(?:\.[0-9]+)?", result.stderr)
                    assert match, f"Could not read ImageMagick difference: {result.stderr}"
                    pixels = float(match.group(0))
                    assert (pixels > 0) == different, f"Unexpected visual diff ({pixels} pixels): {left}, {right}"

                def capture(name):
                    if not os.environ.get("AWESOME_TEST_SCREENSHOTS"):
                        return
                    shots = Path(os.environ["AWESOME_TEST_SCREENSHOTS"])
                    shots.mkdir(parents=True, exist_ok=True)
                    time.sleep(0.15)
                    subprocess.run(["import", "-window", "root", str(shots / f"{name}.png")], env=env, check=True, timeout=5)

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
                    diagnostic = helper('local r=""; for _,c in ipairs(client.get()) do r=r..tostring(c.class)..":"..c.type..":"..c.x..","..c.y..","..c.width..","..c.height..":screen="..c.screen.index..":visible="..tostring(c:isvisible()); for k,v in pairs(c:struts()) do r=r..":"..k.."="..v end; r=r.."\\n" end; return r')
                    raise AssertionError(f"Expected {expected!r}: {code}\n{last}\n{diagnostic}\n{logfile.read_text()}")

                def click_sidebar_title(section_id):
                    lua('screen[1].sidebar_scroll_by(-10000)')
                    position = "missing"
                    for _ in range(20):
                        position = lua(
                            f'local s=screen[1]; local target=s.sidebar_sections["{section_id}"].title_widget; '
                            'local x=math.floor(s.sidebar.width/2); '
                            'for y=0,s.sidebar.height-1 do '
                            'for _,v in ipairs(s.sidebar:find_widgets(x,y)) do '
                            'if v.widget==target then return tostring(s.sidebar.x+x)..":"..tostring(s.sidebar.y+y) end '
                            'end end; return "missing"')
                        if re.search(r'(\d+):(\d+)', position):
                            break
                        lua('screen[1].sidebar_scroll_by(120)')
                    match = re.search(r'(\d+):(\d+)', position)
                    assert match, f"Could not locate sidebar section {section_id}: {position}"
                    x, y = int(match.group(1)), int(match.group(2)) + 2
                    subprocess.run(["xdotool", "mousemove", str(x), str(y), "click", "1"], env=env, check=True)

                def sidebar_title_point(section_id, reset_scroll=False):
                    if reset_scroll:
                        lua('screen[1].sidebar_scroll_by(-10000)')
                    position = lua(
                        f'local s=screen[1]; local section=s.sidebar_sections["{section_id}"]; '
                        'for y=0,s.sidebar.height-1 do '
                        'for _,v in ipairs(s.sidebar:find_widgets(150,y)) do '
                        'if v.widget==section.title_widget then '
                        'return tostring(s.sidebar.x+150)..":"..tostring(s.sidebar.y+y) '
                        'end end end; return "missing"')
                    match = re.search(r'(\d+):(\d+)', position)
                    if not match:
                        return None
                    return tuple(map(int, match.groups()))

                def drag_between(start, end):
                    sx, sy = start[:2]
                    ex, ey = end[:2]
                    subprocess.run(["xdotool", "mousemove", str(sx), str(sy), "mousedown", "1"],
                                   env=env, check=True, timeout=3)
                    try:
                        subprocess.run(["xdotool", "mousemove", "--sync", str(ex), str(ey)],
                                       env=env, check=True, timeout=3)
                        time.sleep(0.12)
                    finally:
                        subprocess.run(["xdotool", "mouseup", "1"], env=env, check=True, timeout=3)

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
                assert 'true' in lua('local s=screen[1]; local b=s.sidebar; return b and b.visible and not s.panel_clock_container.visible and s.sidebar_header and s.sidebar_header.forced_height == 26 and s.sidebar_mode == 3 and b.ontop and b:struts().right == 300 and b.width == 300 and b.border_width == 0 and s.sidebar_cpu and s.sidebar_battery and s.sidebar_volume and s.sidebar_trash_status and s.sidebar_trash_icon and s.sidebar_trash_state and s.sidebar_trash_timer.timeout == 30 and s.sidebar_media_text and s.sidebar_root_text and s.sidebar_weather_text and s.sidebar_crypto_timer.timeout == 60 and s.sidebar_codex_card.forced_height == nil and s.sidebar_codex_timer.timeout == 60 and s.sidebar_audio_header == nil and s.sidebar_wallpaper_preview and s.sidebar_todo_card and #s.sidebar_todo_entries == 5 and s.sidebar_todo_entries[5] == "Fifth item" and s.sidebar_calendar_card and not s.sidebar_date_calendar and s.sidebar_calendar_grid and s.sidebar_calendar_weekday_order == "MTWTFSS" and #s.sidebar_calendar_entries == 7 and s.sidebar_calendar_entries[1].day == "past" and s.sidebar_calendar_entries[2].time == "08:15-09:00" and s.sidebar_calendar_entries[3].text == "visit: Today appointment" and s.sidebar_calendar_entries[6].text == "Third future event" and s.sidebar_todo_timer.timeout == 60 and s.sidebar_calendar_timer.timeout == 60 and s.panel_cpu == nil and s.panel_battery == nil and s.panel_volume == nil and s.workarea.width == s.geometry.width-300 and b.x+b.width == s.geometry.x+s.geometry.width and b.y == s.geometry.y+30 and b.height == s.geometry.height-30')
                assert 'true' in lua('local s=screen[1]; return table.concat(s.sidebar_content_order, ",") == "calendar,todo,quick-launch,system-status,codex,crypto,weather,now-playing,wallpaper"')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_sections.crypto.collapsed')
                click_sidebar_title("crypto")
                wait('return tostring(screen[1].sidebar_sections.crypto.collapsed)', '"false"')
                assert section_state_file.read_text() == default_sidebar_order
                section_state_file.write_text("order=calendar,calendar,unknown\n")
                subprocess.run(["awesome-client", "awesome.restart()"], env=env,
                               capture_output=True, text=True, timeout=5)
                wait('return table.concat(screen[1].sidebar_content_order, ",")',
                     '"calendar,todo,quick-launch,system-status,codex,crypto,weather,now-playing,wallpaper"')
                assert 'true' in lua('local s=screen[1]; for _,section in pairs(s.sidebar_sections) do if section.collapsed then return false end end; return true')
                assert 'true' in lua('local s=screen[1]; if s.sidebar_stats_card.forced_height ~= nil or #s.sidebar_progress_bars ~= 8 then return false end; for _,b in ipairs(s.sidebar_progress_bars) do if b.forced_height ~= 8 then return false end end; return true')
                wait('return screen[1].sidebar_crypto_prices.BTC.text.."|"..screen[1].sidebar_crypto_prices.ETH.text.."|"..screen[1].sidebar_crypto_prices.LTC.text', '"97.123|3.456|123,45"')
                lua('screen[1].sidebar_scroll_by(-10000)')
                for _ in range(40):
                    time.sleep(0.05)
                    crypto_position = lua('local s=screen[1]; local target=s.sidebar_crypto_prices.ETH.widget; local x=math.floor(s.sidebar.width/2); for y=0,s.sidebar.height-1 do for _,v in ipairs(s.sidebar:find_widgets(x,y)) do if v.widget==target then return tostring(s.sidebar.x+x)..":"..tostring(s.sidebar.y+y) end end end; return "missing"')
                    if re.search(r'(\d+):(\d+)', crypto_position):
                        break
                    lua('screen[1].sidebar_scroll_by(80)')
                match = re.search(r'(\d+):(\d+)', crypto_position)
                assert match, f"Could not locate clickable crypto price: {crypto_position}"
                subprocess.run(["xdotool", "mousemove", match.group(1), match.group(2), "click", "1"], env=env, check=True)
                expected_trezor = f"trezor:{current_trezor}"
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    if expected_trezor in actions_file.read_text():
                        break
                    time.sleep(0.1)
                assert expected_trezor in actions_file.read_text(), actions_file.read_text()
                wait('return screen[1].sidebar_codex_5h.summary.markup', '5h  84% left · Sat 13:46')
                wait('return screen[1].sidebar_codex_7d.summary.markup', '7d  33% left · Wed 06:41')
                wait('return screen[1].sidebar_codex_resets.markup', 'Sat 24.10 13:46')
                assert 'true' in lua('local m=screen[1].sidebar_codex_resets.markup; return select(2,m:gsub("\\n", "")) == 2 and m:find("Fri 30.10 13:46", 1, true) ~= nil and not m:find("Free resets", 1, true)')
                assert '9pt' in lua('return screen[1].sidebar_codex_resets.markup')

                # Failure retains real values, marks them stale, and recovers.
                wait('return screen[1].sidebar_weather_text.text', '12°C')
                weather_source = weather_response.read_text()
                weather_response.write_text('malformed\n')
                lua('screen[1].sidebar_data.refresh("weather")')
                wait('return tostring(screen[1].sidebar_data.state("weather").stale)', 'true')
                assert '12°C' in lua('return screen[1].sidebar_weather_text.text')
                weather_response.write_text(weather_source)
                lua('screen[1].sidebar_data.refresh("weather")')
                wait('return tostring(screen[1].sidebar_data.state("weather").stale)', 'false')
                crypto_source = crypto_helper.read_text()
                crypto_helper.write_text('#!/bin/sh\nprintf "malformed\\n"\n')
                lua('screen[1].sidebar_crypto_refresh()')
                wait('return tostring(screen[1].sidebar_data.state("crypto").stale)', 'true')
                assert '97.123' in lua('return screen[1].sidebar_crypto_prices.BTC.text')
                assert 'true' in lua('local s=screen[1]; local body=s.sidebar_sections.crypto.body; return body.children[2].visible and body.children[2].text == "STALE"')
                assert 'true' in lua('local t=screen[1].sidebar_crypto_timer.tooltip; local b=require("beautiful"); t.visible=true; local _,r,g,blue=t.widget.bg:get_rgba(); local color=string.format("#%02x%02x%02x",math.floor(r*255+0.5),math.floor(g*255+0.5),math.floor(blue*255+0.5)); return color==b.tooltip_bg and t.widget.shape_border_width==1 and t.wibox_properties.fg==b.tooltip_fg and t.textbox.markup:find("Last success:",1,true)~=nil')
                capture("stale-tooltip")
                lua('screen[1].sidebar_crypto_timer.tooltip.visible=false')
                crypto_helper.write_text(crypto_source)
                lua('screen[1].sidebar_crypto_refresh()')
                wait('return tostring(screen[1].sidebar_data.state("crypto").stale)', 'false')

                codex_source = codex_helper.read_text()
                codex_helper.write_text('#!/bin/sh\nprintf "C 5h 0%%@Sat 13:46 7d 33%%@Wed 06:41\\tA & B < C\\n"\n')
                lua('screen[1].sidebar_codex_refresh()')
                wait('return tostring(screen[1].sidebar_codex_5h.remaining)', '0')
                assert 'A &amp; B &lt; C' in lua('return screen[1].sidebar_codex_resets.markup')
                codex_helper.write_text('#!/bin/sh\nexit 1\n')
                lua('screen[1].sidebar_codex_refresh()')
                wait('return tostring(screen[1].sidebar_data.state("codex").stale)', 'true')
                assert 'true' in lua('return screen[1].sidebar_codex_5h.remaining == 0')
                codex_helper.write_text(codex_source)
                lua('screen[1].sidebar_codex_refresh()')
                wait('return tostring(screen[1].sidebar_codex_5h.remaining)', '84')
                assert 'true' in lua('local d=screen[1].sidebar_data; local c=d.collectors.crypto; local n=c.requests; local second=d.subscribe("crypto",function(state) _G.__polish_snapshot=state end); local ok=c.requests==n and __polish_snapshot==d.state("crypto"); second:stop(); return ok and c.timer~=nil')
                assert 'true' in lua('local s=screen[1]; local count=0; for _,section in pairs(s.sidebar_sections) do count=count+1; if section.collapsed then return "false" end end; return tostring(count == 9)')
                click_sidebar_title("crypto")
                wait('return tostring(screen[1].sidebar_sections.crypto.collapsed)', '"true"')
                assert 'true' in lua('local section=screen[1].sidebar_sections.crypto; return section.card.forced_height == 40 and not section.body.visible and section.marker.markup:find("▸", 1, true) ~= nil')
                assert section_state_file.read_text() == default_sidebar_order + "crypto\n"
                subprocess.run(["awesome-client", "awesome.restart()"], env=env,
                               capture_output=True, text=True, timeout=5)
                wait('return tostring(screen[1].sidebar_sections.crypto.collapsed)', '"true"')
                assert section_state_file.read_text() == default_sidebar_order + "crypto\n"
                # Keep both drag endpoints visible despite the expanded calendar.
                click_sidebar_title("calendar")
                source = sidebar_title_point("calendar", reset_scroll=True)
                target = sidebar_title_point("quick-launch")
                assert source and target, f"Could not locate visible reorder titles: {source}, {target}"
                drag_between(source, target)
                first_reordered = "todo,calendar,quick-launch,system-status,codex,crypto,weather,now-playing,wallpaper"
                wait('return table.concat(screen[1].sidebar_content_order, ",")', f'"{first_reordered}"')
                click_sidebar_title("calendar")
                assert 'true' in lua('return not screen[1].sidebar_sections.calendar.collapsed')
                first_order_state = f"order={first_reordered}\ncrypto\n"
                assert section_state_file.read_text() == first_order_state
                subprocess.run(["awesome-client", "awesome.restart()"], env=env,
                               capture_output=True, text=True, timeout=5)
                wait('return table.concat(screen[1].sidebar_content_order, ",")', f'"{first_reordered}"')
                wait('return tostring(screen[1].sidebar_sections.crypto.collapsed)', '"true"')
                assert section_state_file.read_text() == first_order_state
                click_sidebar_title("crypto")
                wait('return tostring(screen[1].sidebar_sections.crypto.collapsed)', '"false"')
                default_sidebar_order = f"order={first_reordered}\n"
                assert section_state_file.read_text() == default_sidebar_order

                source = sidebar_title_point("todo", reset_scroll=True)
                assert source, "Could not locate section to edge-scroll"
                edge = lua('local s=screen[1]; return tostring(s.sidebar.x+150)..":"..tostring(s.sidebar.y+s.sidebar_header.forced_height+s.sidebar_clock_card.forced_height+s.sidebar_scroll_view.forced_height-8)')
                edge_match = re.search(r"(\d+):(\d+)", edge)
                assert edge_match, edge
                edge_x, edge_y = map(int, edge_match.groups())
                subprocess.run(["xdotool", "mousemove", str(source[0]), str(source[1]), "mousedown", "1"],
                               env=env, check=True, timeout=3)
                try:
                    subprocess.run(["xdotool", "mousemove", "--sync", str(edge_x), str(edge_y)],
                                   env=env, check=True, timeout=3)
                    time.sleep(2)
                    wait('return tostring(screen[1].sidebar_scroll_position >= screen[1].sidebar_scroll_max()-1)', '"true"')
                    edge_scroll = lua('return tostring(screen[1].sidebar_scroll_position > 0)')
                    assert '"true"' in edge_scroll, edge_scroll
                    drop_y = edge_y + 6
                    subprocess.run(["xdotool", "mousemove", "--sync", str(edge_x), str(drop_y)],
                                   env=env, check=True, timeout=3)
                    time.sleep(0.12)
                finally:
                    subprocess.run(["xdotool", "mouseup", "1"], env=env, check=True, timeout=3)
                second_reordered = "calendar,quick-launch,system-status,codex,crypto,weather,now-playing,wallpaper,todo"
                wait('return table.concat(screen[1].sidebar_content_order, ",")', f'"{second_reordered}"')
                assert section_state_file.read_text() == f"order={second_reordered}\n"
                subprocess.run(["awesome-client", "awesome.restart()"], env=env,
                               capture_output=True, text=True, timeout=5)
                wait('return table.concat(screen[1].sidebar_content_order, ",")', f'"{second_reordered}"')
                assert section_state_file.read_text() == f"order={second_reordered}\n"
                default_sidebar_order = f"order={second_reordered}\n"
                lua('for _,section in pairs(screen[1].sidebar_sections) do if not section.collapsed then for _,button in ipairs(section.marker:buttons()) do if button.button == 1 then button:emit_signal("press"); break end end end end')
                wait('return tostring(not screen[1].sidebar_scrollbar.visible and screen[1].sidebar_scroll_max() == 0)', '"true"')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_scroll_view.forced_height == s.sidebar.height - s.sidebar_header.forced_height - s.sidebar_clock_card.forced_height')
                lua('for _,section in pairs(screen[1].sidebar_sections) do if section.collapsed then for _,button in ipairs(section.marker:buttons()) do if button.button == 1 then button:emit_signal("press"); break end end end end')
                wait('return tostring(screen[1].sidebar_scrollbar.visible and screen[1].sidebar_scroll_max() > 0)', '"true"')
                assert 'true' in lua('local s=screen[1]; local b=s.sidebar_scrollbar_panel; return b.visible and b.y == s.sidebar.y+s.sidebar_header.forced_height+s.sidebar_clock_card.forced_height+s.sidebar_scroll_view.forced_height and b.y+b.height == s.sidebar.y+s.sidebar.height')
                assert section_state_file.read_text() == default_sidebar_order
                codex_5h_bar = lua('return tostring(screen[1].sidebar_codex_5h.remaining)')
                codex_7d_bar = lua('return tostring(screen[1].sidebar_codex_7d.remaining)')
                assert '84' in codex_5h_bar, codex_5h_bar
                assert '33' in codex_7d_bar, codex_7d_bar
                wait('return tostring(screen[1].sidebar_scroll_max() > 0)', '"true"')
                subprocess.run(["xdotool", "mousemove", "1100", "720", "click", "5"], env=env, check=True)
                wheel_state = wait('return tostring(screen[1].sidebar_scroll_position > 0)', '"true"')
                assert 'true' in wheel_state, wheel_state
                assert 'true' in lua('local s=screen[1]; for _,v in ipairs(s.sidebar:find_widgets(150, 27)) do if v.widget == s.sidebar_clock_card and v.y == 26 then return s.sidebar_scroll_position > 0 end end; return false')
                lua('screen[1].sidebar_scroll_by(-10000)')
                wait('return tostring(screen[1].sidebar_scroll_offset() == 0)', '"true"')
                subprocess.run(["xdotool", "mousemove", "1030", "794", "mousedown", "1",
                                "mousemove", "1220", "794", "mouseup", "1"],
                               env=env, check=True, timeout=5)
                wait('return tostring(screen[1].sidebar_scroll_position > 0)', '"true"')
                slider_state = lua('return tostring(screen[1].sidebar_scroll_position > 0)..":"..tostring(not mousegrabber.isrunning())')
                assert 'true:true' in slider_state, slider_state
                lua('screen[1].sidebar_scroll_by(-10000)')
                wait('return tostring(screen[1].sidebar_scroll_offset() == 0)', '"true"')
                subprocess.run(["xdotool", "mousemove", "1130", "140", "click", "1"], env=env, check=True)
                wait('return screen[1].sidebar_clock_mode', 'text')
                lua('screen[1].sidebar_clock_toggle()')
                wait('return screen[1].sidebar_clock_mode', 'analog')
                subprocess.run(["xdotool", "mousemove", "1130", "70", "click", "1"], env=env, check=True)
                assert 'true:true:true' in lua('local s=screen[1]; return tostring(s.sidebar_clock_mode == "analog")..":"..tostring(s.sidebar_date_calendar == nil)..":"..tostring(s.sidebar_calendar_selected_date() == os.date("%Y-%m-%d"))')
                current_month = lua('return screen[1].sidebar_calendar_month()').strip().split('"')[1]
                lua('screen[1].sidebar_calendar_next_action()')
                wait('return tostring(screen[1].sidebar_calendar_month() ~= os.date("%Y-%m"))', '"true"')
                calendar_month_before = lua('return screen[1].sidebar_calendar_month()').strip().split('"')[1]
                calendar_next = widget_point('screen[1].sidebar_calendar_next_button', scroll=-10000, x=270)
                pointer("mousemove", *calendar_next, "click", 1)
                wait('return tostring(screen[1].sidebar_calendar_month() ~= ' + repr(calendar_month_before) + ')', '"true"')
                lua('screen[1].sidebar_calendar_previous_action(); screen[1].sidebar_calendar_previous_action()')
                wait('return screen[1].sidebar_calendar_month()', f'"{current_month}"')
                lua('screen[1].sidebar_calendar_select_date(os.date("%Y-%m-%d"))')
                assert 'true:true' in lua('local s=screen[1]; local n=0; for _,entry in ipairs(s.sidebar_calendar_entries) do if entry.date == s.sidebar_calendar_selected_date() then n=n+1 end end; return tostring(s.sidebar_calendar_day_cells()[s.sidebar_calendar_selected_date()] ~= nil)..":"..tostring(n == 2)')
                lua('local s=screen[1]; local row=s.sidebar_calendar_events_widget:get_children()[1]; for _,button in ipairs(row:buttons()) do if button.button == 1 then button:emit_signal("press"); return true end end; return false')
                expected_calendar = f"open {testhome / 'Documents/calendar.md'}"
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline and expected_calendar not in actions_file.read_text():
                    time.sleep(0.1)
                assert expected_calendar in actions_file.read_text(), actions_file.read_text()
                lua('screen[1].sidebar_scroll_before_todo = screen[1].sidebar_scroll_max()')
                todo_path.write_text("# TODO\n## Sidebar\n- Refreshed item\n")
                lua('screen[1].sidebar_todo_refresh()')
                wait('return tostring(screen[1].sidebar_scroll_max() < screen[1].sidebar_scroll_before_todo)', '"true"')
                todo_refresh_result = lua('return tostring(#screen[1].sidebar_todo_entries)..":"..tostring(screen[1].sidebar_todo_entries[1])')
                assert '1:Refreshed item' in todo_refresh_result, todo_refresh_result
                press('super+shift+s')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_mode == 0 and not s.sidebar.visible and not s.sidebar_scrollbar_panel.visible and s.panel_clock_container.visible and s.sidebar:struts().right == 0 and s.workarea.width == s.geometry.width')
                press('super+shift+s')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_mode == 1 and s.sidebar.visible and s.sidebar_scrollbar_panel.visible and not s.sidebar_scrollbar_panel.ontop and not s.panel_clock_container.visible and not s.sidebar.ontop and s.sidebar:struts().right == 0 and s.workarea.width == s.geometry.width')
                press('super+shift+s')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_mode == 2 and s.sidebar.visible and s.sidebar_scrollbar_panel.visible and s.sidebar_scrollbar_panel.ontop and not s.panel_clock_container.visible and s.sidebar.ontop and s.workarea.width == s.geometry.width')
                press('super+shift+s')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_mode == 3 and s.sidebar.visible and s.sidebar_scrollbar_panel.visible and s.sidebar_scrollbar_panel.ontop and not s.panel_clock_container.visible and s.sidebar.ontop and s.sidebar:struts().right == 300 and s.workarea.width == s.geometry.width - 300')
                press('super+shift+s')
                hidden_sidebar = lua('local s=screen[1]; return tostring(s.sidebar_mode)..":"..tostring(s.sidebar.visible)..":"..tostring(s.panel_clock_container.visible)..":"..tostring(s.sidebar:struts().right)..":"..s.workarea.width..":"..s.geometry.width')
                assert '0:false:true:0:1280:1280' in hidden_sidebar, hidden_sidebar
                press('super+shift+s'); press('super+shift+s'); press('super+shift+s')
                quick_position = widget_point('screen[1].sidebar_quick_launch_buttons.Terminal.widget', x=60)
                qx, qy = quick_position
                pointer("mousemove", qx, qy, "mousedown", 1)
                assert 'true' in lua('return screen[1].sidebar_quick_launch_buttons.Terminal.widget._sidebar_release_binding.state.armed')
                pointer("mousemove", 400, 700, "mouseup", 1)
                assert 'true' in lua('local b=screen[1].sidebar_quick_launch_buttons.Terminal.widget; return not b._sidebar_release_binding.state.armed and #b:buttons()==0')
                wallpaper = subprocess.run(["xprop", "-root", "_XROOTPMAP_ID"], env=env,
                                           capture_output=True, text=True, check=True, timeout=3).stdout
                assert "PIXMAP" in wallpaper, wallpaper
                wait('return screen[1].sidebar_root_text.text', 'Free /')
                assert 'aurora-longhorn.png' in lua('return screen[1].sidebar_wallpaper_name.text')
                next_buttons = lua('local b=screen[1].sidebar_wallpaper_next; return tostring(screen[1].sidebar_wallpaper_count)..":"..tostring(#b:buttons())..":"..tostring(b._sidebar_release_binding~=nil)')
                assert '3:0:true' in next_buttons, next_buttons
                lua('screen[1].sidebar_wallpaper_next_action()')
                wallpaper_name = lua('return tostring(screen[1].sidebar_wallpaper_index)..":"..screen[1].sidebar_wallpaper_name.text')
                assert '2:lock-win98-tux.png' in wallpaper_name, wallpaper_name
                lua('screen[1].sidebar_wallpaper_next_action()')
                wallpaper_name = lua('return tostring(screen[1].sidebar_wallpaper_index)..":"..screen[1].sidebar_wallpaper_name.text')
                assert '3:pictures-wallpaper.png' in wallpaper_name, wallpaper_name
                lua('screen[1].sidebar_wallpaper_previous_action(); screen[1].sidebar_wallpaper_previous_action(); screen[1].sidebar_wallpaper_apply()')
                assert (testhome / ".local/state/awesome/wallpaper").read_text().strip().endswith("aurora-longhorn.png")
                # Release outside cancels; release inside activates precisely once.
                wall_point = widget_point('screen[1].sidebar_wallpaper_next', scroll=10000, x=270)
                wx, wy = wall_point
                pointer("mousemove", wx, wy, "mousedown", 1)
                assert 'true' in lua('return screen[1].sidebar_wallpaper_next._sidebar_release_binding.state.armed')
                pointer("mousemove", 400, 700, "mouseup", 1)
                assert '1:' in lua('return tostring(screen[1].sidebar_wallpaper_index)..":"..tostring(not screen[1].sidebar_wallpaper_next._sidebar_release_binding.state.armed)')
                pointer("mousemove", wx, wy, "click", 1)
                wait('return tostring(screen[1].sidebar_wallpaper_index)', '"2"')
                media_previous = widget_point('screen[1].sidebar_media_buttons.previous', scroll=10000, x=105)
                pointer("mousemove", *media_previous, "click", 1)
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline and "playerctl previous" not in actions_file.read_text():
                    time.sleep(0.05)
                assert "playerctl previous" in actions_file.read_text(), actions_file.read_text()
                wait('return tostring(screen[1].sidebar_volume_text.markup):find("42%", 1, true) and "42%" or "pending"', '"42%"')
                assert '9pt' in lua('return screen[1].sidebar_volume_text.markup')
                assert 'true' in lua('local p=screen[1].panel_clock; local s=screen[1].sidebar_clock; return p.text:match("%d%d:%d%d") ~= nil and p.forced_width == 58 and type(s.draw) == "function" and s.current_time.hour ~= nil and s.current_time.min ~= nil and s.current_time.sec ~= nil and screen[1].sidebar_clock_mode == "analog" and not screen[1].sidebar_digital_time.visible and screen[1].sidebar_clock_card.forced_height == 142 and screen[1].sidebar_date.text:find(os.date("%a"), 1, true) ~= nil')
                lua('screen[1].sidebar_clock_toggle()')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_clock_mode == "text" and s.sidebar_digital_time.visible and not s.sidebar_clock.visible and s.sidebar_clock_card.forced_height == 66 and s.sidebar_digital_time.text:match("%d%d:%d%d:%d%d") ~= nil')
                lua('screen[1].sidebar_clock_toggle()')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_clock_mode == "analog" and not s.sidebar_digital_time.visible and s.sidebar_clock.visible and s.sidebar_clock_card.forced_height == 142')
                lua('for _,b in ipairs(screen[1].sidebar_volume:buttons()) do if b.button == 3 then b:emit_signal("press") end end')
                lua('for _,b in ipairs(screen[1].sidebar_volume:buttons()) do if b.button == 1 then b:emit_signal("press") end end')
                time.sleep(0.3)
                lua('screen[1].sidebar_todo_open(); screen[1].sidebar_calendar_open()')
                wait('local f=io.open(os.getenv("TEST_ACTIONS"),"r"); local v=f and f:read("*a") or ""; if f then f:close() end; return v:find("open "..os.getenv("HOME").."/Documents/todo.md",1,true) and v:find("open "..os.getenv("HOME").."/Documents/calendar.md",1,true) and "opened" or "pending"', 'opened')
                actions = (directory / "actions").read_text().splitlines()
                assert all(action in actions for action in ("mute", "mixer", f"open {testhome}/Documents/todo.md", f"open {testhome}/Documents/calendar.md")), actions
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
                start_normal_crop = capture_start("start-normal") if visual else None
                pointer("mousemove", 30, 15, "mousedown", 1)
                assert 'true' in lua('local s=screen[1]; return s.start_pressed_image and s.start_button._private.image == s.start_pressed_image and not s.start_menu.wibox.visible')
                start_held_crop = capture_start("start-held") if visual else None
                pointer("mouseup", 1)
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"true"')
                assert 'true' in lua('return screen[1].start_button._private.image == screen[1].start_normal_image')
                start_restored_crop = capture_start("start-restored") if visual else None
                if visual:
                    compare_visual(start_normal_crop, start_held_crop, True)
                    compare_visual(start_normal_crop, start_restored_crop, False)
                assert 'true' in lua('local m=screen[1].start_menu; local b=require("beautiful"); return m.x == screen[1].geometry.x and m.y == screen[1].geometry.y + screen[1].panel.height and m.theme.width == 270 and m.theme.height == 28 and m.theme.border_width == 1 and m.theme.bg_normal == b.menu_bg_normal and m.theme.bg_focus == b.menu_bg_focus and m.theme.fg_focus == b.menu_fg_focus')
                lua('screen[1].start_menu:item_enter(1)')
                capture("start-menu")
                press('Escape')
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"false"')
                pointer("mousemove", 30, 15, "mousedown", 1)
                assert 'true' in lua('return screen[1].start_pressed_image and screen[1].start_button._private.image == screen[1].start_pressed_image and not screen[1].start_menu.wibox.visible')
                pointer("mousemove", 900, 700)
                start_cancelled_crop = capture_start("start-cancelled") if visual else None
                pointer("mouseup", 1)
                assert 'true' in lua('return screen[1].start_button._private.image == screen[1].start_normal_image and not screen[1].start_menu.wibox.visible')
                if visual:
                    compare_visual(start_normal_crop, start_cancelled_crop, False)
                    compare_visual(start_normal_crop, capture_start("start-cancelled-restored"), False)
                subprocess.run(["xdotool", "mousemove", "30", "15", "click", "1"], env=env, check=True)
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"true"')
                menu_items = lua('local r=""; for i,item in ipairs(screen[1].start_menu.items) do r=r..i..":"..tostring(item.label and item.label.text)..":"..tostring(item.cmd)..";" end; return r')
                assert '13:Display outputs' in menu_items, menu_items
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
                lua('__awesome_display_menu:delete(5)')
                assert 'true' in lua('return not mousegrabber.isrunning() and __awesome_menu_delete_count == 0')
                pointer("mouseup", 1)
                action_item = menu_item_point('__awesome_display_menu', 5)
                pointer("mousemove", *action_item, "mousedown", 1)
                assert 'true' in lua('return __awesome_display_menu.items[5]._release_binding.state.armed and __awesome_menu_action_count == 0')
                pointer("mousemove", 900, 700)
                assert 'true' in lua('local s=__awesome_display_menu.items[5]._release_binding.state; return s.armed and not s.inside and __awesome_menu_action_count == 0')
                pointer("mousemove", *action_item)
                assert 'true' in lua('local s=__awesome_display_menu.items[5]._release_binding.state; return s.armed and s.inside and __awesome_menu_action_count == 0')
                pointer("mouseup", 1)
                wait('return tostring(__awesome_menu_action_count)', '"1"')
                wait('return tostring(__awesome_display_menu.wibox.visible)', '"false"')
                lua('__awesome_display_menu:show()')
                wait('return tostring(__awesome_display_menu.wibox.visible)', '"true"')
                action_item = menu_item_point('__awesome_display_menu', 5)
                pointer("mousemove", *action_item, "mousedown", 1)
                assert 'true' in lua('return __awesome_display_menu.items[5]._release_binding.state.armed')
                lua('__awesome_display_menu:hide(); __awesome_display_menu:show()')
                assert 'true' in lua('return not mousegrabber.isrunning() and __awesome_menu_action_count == 1')
                pointer("mouseup", 1)
                assert 'true' in lua('return __awesome_display_menu.wibox.visible and __awesome_menu_action_count == 1')
                press('Escape')
                wait('return tostring(__awesome_display_menu.wibox.visible)', '"false"')
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
                tag_point = workspace_point(3)
                workspace_normal_crop = capture_workspace(3, "workspace-normal") if visual else None
                lua('_G.__workspace_normal_bg=screen[1].taglist_release_actions[screen[1].tags[3]].widget:get_children_by_id("background_role")[1].bg')
                pointer("mousemove", *tag_point, "mousedown", 1)
                workspace_pressed = lua('local a=screen[1].taglist_release_actions[screen[1].tags[3]]; return tostring(a.view_binding.state.armed)..":"..tostring(screen[1].selected_tag.index)..":"..tostring(mousegrabber.isrunning())..":"..tostring(a.widget._workspace_pressed)..":"..tostring(a.widget._workspace_animation_alpha>0)..":"..tostring(a.overlay.bg~=nil)')
                assert 'true:1:true:true:true:true' in workspace_pressed, workspace_pressed
                lua('screen[1].tags[3]:view_only()')
                wait('return screen[1].selected_tag.index', '3')
                assert 'true' in lua('local a=screen[1].taglist_release_actions[screen[1].tags[3]]; return a.overlay.bg~=nil and a.widget._workspace_animation_alpha>0')
                lua('screen[1].tags[1]:view_only()')
                wait('return screen[1].selected_tag.index', '1')
                assert 'true' in lua('local a=screen[1].taglist_release_actions[screen[1].tags[3]]; return a.overlay.bg~=nil and a.widget:get_children_by_id("background_role")[1].bg==__workspace_normal_bg')
                workspace_held_crop = capture_workspace(3, "workspace-held") if visual else None
                pointer("mousemove", 500, 700)
                wait('local a=screen[1].taglist_release_actions[screen[1].tags[3]]; return tostring(a.widget._workspace_animation_alpha==0 and a.overlay.bg==nil)', '"true"')
                workspace_cancel_crop = capture_workspace(3, "workspace-canceled") if visual else None
                assert 'true' in lua('return screen[1].selected_tag.index == 1 and mousegrabber.isrunning()')
                pointer("mouseup", 1)
                assert 'true' in lua('return screen[1].selected_tag.index == 1 and not mousegrabber.isrunning()')
                if visual:
                    compare_visual(workspace_normal_crop, workspace_held_crop, True)
                    compare_visual(workspace_normal_crop, workspace_cancel_crop, False)
                pointer("mousemove", *tag_point, "mousedown", 1)
                assert 'true' in lua('local a=screen[1].taglist_release_actions[screen[1].tags[3]]; return a.view_binding.state.armed and a.view_binding.state.inside and screen[1].selected_tag.index==1')
                pointer("mousemove", 500, 700)
                wait('local a=screen[1].taglist_release_actions[screen[1].tags[3]]; return tostring(a.view_binding.state.armed and not a.view_binding.state.inside and a.widget._workspace_animation_alpha==0)', '"true"')
                pointer("mousemove", *tag_point)
                assert 'true' in lua('local a=screen[1].taglist_release_actions[screen[1].tags[3]]; return a.view_binding.state.armed and a.view_binding.state.inside and a.widget._workspace_animation_alpha>0')
                pointer("mouseup", 1)
                wait('return screen[1].selected_tag.index', '3')
                press('super+1')
                wait('return screen[1].selected_tag.index', '1')
                assert 'false' in lua('return tostring(screen[1].start_menu.wibox.visible)')
                # The panel clock/calendar returns when the sidebar is hidden.
                press('super+shift+s')
                subprocess.run(["xdotool", "mousemove", "1258", "15", "click", "1"], env=env, check=True)
                wait('return tostring(screen[1].panel_calendar.visible)', '"true"')
                capture("panel-calendar")
                subprocess.run(["xdotool", "click", "1"], env=env, check=True)
                wait('return tostring(screen[1].panel_calendar.visible)', '"false"')
                lua('_G.__polish_drawins=0; for _,d in ipairs(root.drawins()) do if d.visible then __polish_drawins=__polish_drawins+1 end end; require("menubar").show()')
                wait('local n=0; for _,d in ipairs(root.drawins()) do if d.visible then n=n+1 end end; return tostring(n>__polish_drawins)', '"true"')
                assert 'true' in lua('local b=require("beautiful"); return b.menubar_bg_normal==b.menu_bg_normal and b.menubar_bg_focus==b.menu_bg_focus and b.menubar_fg_normal==b.menu_fg_normal and require("menubar").prompt_args.bg_cursor=="#a8f0bd"')
                capture("applications-menu")
                press('Escape')
                wait('local n=0; for _,d in ipairs(root.drawins()) do if d.visible then n=n+1 end end; return tostring(n==__polish_drawins)', '"true"')
                desktops = subprocess.run(["xprop", "-root", "_NET_NUMBER_OF_DESKTOPS"], env=env,
                                          capture_output=True, text=True, check=True, timeout=3).stdout
                assert desktops.strip().endswith("= 4"), desktops
                for name in ("AwesomeSmokeA", "AwesomeSmokeB"):
                    processes.append(subprocess.Popen(["xmessage", "-name", name, "-geometry", "400x200", name],
                                                       env=env, stdout=log, stderr=log))
                wait('local n=0; for _,c in ipairs(client.get()) do if c.class == "Xmessage" then n=n+1 end end; return n', '2')
                lua('for _,c in ipairs(client.get()) do if c.instance=="AwesomeSmokeB" then __workspace_state_client=c; c:move_to_tag(screen[1].tags[3]) end end')
                wait('return __workspace_state_client.first_tag.index', '3')
                state_point = workspace_point(3)
                pointer("mousemove", *state_point, "mousedown", 1)
                wait('return tostring(__workspace_state_client.first_tag.index==3 and screen[1].taglist_release_actions[screen[1].tags[3]].overlay.bg~=nil)', '"true"')
                lua('__workspace_state_client.urgent=true')
                wait('return tostring(__workspace_state_client.urgent)', '"true"')
                assert 'true' in lua('local a=screen[1].taglist_release_actions[screen[1].tags[3]]; return a.overlay.bg~=nil and a.widget._workspace_animation_alpha>0')
                lua('__workspace_state_client.urgent=false; __workspace_state_client:move_to_tag(screen[1].tags[1])')
                wait('return __workspace_state_client.first_tag.index', '1')
                assert 'true' in lua('local a=screen[1].taglist_release_actions[screen[1].tags[3]]; return a.overlay.bg~=nil and a.widget._workspace_animation_alpha>0')
                pointer("mousemove", 500, 700)
                wait('return tostring(screen[1].taglist_release_actions[screen[1].tags[3]].overlay.bg==nil)', '"true"')
                pointer("mouseup", 1)
                assert 'true' in lua('return screen[1].selected_tag.index==1 and not mousegrabber.isrunning()')
                lua('__workspace_state_client=nil')
                titlebar_state = lua('local r=""; for _,c in ipairs(client.get()) do if c.class == "Xmessage" then local top=c._private and c._private.titlebars and c._private.titlebars.top; r=r..tostring(c.floating)..":"..tostring(top and top.args.size)..":"..tostring(c.y)..";" end end; return r')
                assert titlebar_state.count("true:26:") == 2, (titlebar_state, logfile.read_text())
                # Real pointer gestures: mouse-down never activates; release location matters.
                lua('for _,c in ipairs(client.get()) do if c.instance=="AwesomeSmokeA" then c.minimized=false; client.focus=c; c:raise() end end')
                wait('return client.focus and client.focus.instance', '"AwesomeSmokeA"')
                lua('_G.__gesture_client=client.focus')
                coordinates = lua('local c=__gesture_client; return (c.x+c.width-36)..":"..(c.y+13)..":"..(c.x-20)')
                gx, gy, outside_x = re.search(r'"(\d+):(\d+):(\d+)"', coordinates).groups()
                def pointer(*args):
                    subprocess.run(["xdotool", *map(str, args)], env=env, check=True, timeout=3)
                    time.sleep(0.08)
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
                control_state = helper('local controls=h.titlebar_controls(client.focus); for _,id in ipairs({"titlebar_minimize","titlebar_maximize","titlebar_close"}) do local b=controls[id]; if not b then return id..":missing" end; if b.forced_width~=21 or b.forced_height~=19 or not b.fg then return id..":geometry" end; b:emit_signal("mouse::leave"); local normal=tostring(b.bg); b:emit_signal("mouse::enter"); if tostring(b.bg)==normal then return id..":hover" end; b:emit_signal("mouse::leave"); if tostring(b.bg)~=normal then return id..":restore" end end; _G.__polish_close_button=controls.titlebar_close; return true')
                assert 'true' in control_state, control_state
                lua('__polish_close_button:emit_signal("mouse::enter")')
                capture("titlebar-close-hover")
                lua('__polish_close_button:emit_signal("mouse::leave"); __polish_close_button=nil')
                press('alt+space')
                capture("window-menu")
                press('Escape')
                if os.environ.get("AWESOME_TEST_SCREENSHOTS"):
                    shots = Path(os.environ["AWESOME_TEST_SCREENSHOTS"])
                    shots.mkdir(parents=True, exist_ok=True)
                    lua('screen[1].sidebar.visible=true; screen[1].sidebar.ontop=true; screen[1].panel_clock_container.visible=false; _G.__polish_geometry={}; for i,c in ipairs(client.get()) do __polish_geometry[c]=c:geometry(); c:geometry({x=50+(i-1)*430,y=220+(i-1)*60,width=400,height=200}) end')
                    lua('_G.__polish_folds={}; for id,section in pairs(screen[1].sidebar_sections) do __polish_folds[id]=section.collapsed; if (id=="quick-launch") == section.collapsed then section.toggle_action() end end; screen[1].sidebar_scroll_by(-10000); _G.__polish_trash_fetch=screen[1].sidebar_data.collectors.trash.fetch')
                    for background in ("#ffffff", "#000000"):
                        for state in ("true", "false", "nil"):
                            lua(f'require("gears").wallpaper.set("{background}"); local d=screen[1].sidebar_data; d.collectors.trash.fetch=function(done) done({{full={state}}}) end; d.refresh("trash")')
                            time.sleep(0.15)
                            subprocess.run(["import", "-window", "root", str(shots / f"{background[1:]}-trash-{state}.png")], env=env, check=True, timeout=5)
                    lua('local s=screen[1]; for _,id in ipairs({"system-status","codex","crypto"}) do if s.sidebar_sections[id].collapsed then s.sidebar_sections[id].toggle_action() end end; for _,c in ipairs(client.get()) do if c.instance=="AwesomeSmokeB" then c.minimized=true end end; s.sidebar_scroll_by(300)')
                    time.sleep(0.15)
                    subprocess.run(["import", "-window", "root", str(shots / "readings-minimized.png")], env=env, check=True, timeout=5)
                    lua('screen[1].sidebar.visible=false; screen[1].panel_clock_container.visible=true; for c,g in pairs(__polish_geometry) do c.minimized=false; c:geometry(g) end; __polish_geometry=nil')
                    lua('local s=screen[1]; s.sidebar_data.collectors.trash.fetch=__polish_trash_fetch; s.sidebar_data.refresh("trash"); for id,section in pairs(s.sidebar_sections) do if section.collapsed~=__polish_folds[id] then section.toggle_action() end end; s.sidebar_wallpaper_apply(); __polish_folds=nil; __polish_trash_fetch=nil')
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
                move_tag_point = workspace_point(2)
                subprocess.run(["xdotool", "keydown", "Super_L", "mousemove", *map(str, move_tag_point), "mousedown", "1"], env=env, check=True, timeout=3)
                time.sleep(0.1)
                assert 'true' in lua('local a=screen[1].taglist_release_actions[screen[1].tags[2]]; return a.move_binding.state.armed and not a.view_binding.state.armed and client.focus.first_tag.index == 3 and mousegrabber.isrunning()')
                subprocess.run(["xdotool", "mousemove", "500", "700", "mouseup", "1", "keyup", "Super_L"], env=env, check=True, timeout=3)
                assert 'true' in lua('for _,c in ipairs(client.get()) do if c.instance == "AwesomeSmokeA" then return c.first_tag.index == 3 and not mousegrabber.isrunning() end end; return false')
                subprocess.run(["xdotool", "keydown", "Super_L", "mousemove", *map(str, move_tag_point), "mousedown", "1"], env=env, check=True, timeout=3)
                time.sleep(0.1)
                subprocess.run(["xdotool", "mouseup", "1", "keyup", "Super_L"], env=env, check=True, timeout=3)
                wait('for _,c in ipairs(client.get()) do if c.instance == "AwesomeSmokeA" then return c.first_tag.index end end', '2')
                lua('for _,c in ipairs(client.get()) do if c.instance == "AwesomeSmokeA" then c:move_to_tag(screen[1].tags[3]) end end')
                wait('for _,c in ipairs(client.get()) do if c.instance == "AwesomeSmokeA" then return c.first_tag.index end end', '3')
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
                assert 'true' in lua('local c=client.focus; local s=c.screen; local a=s.geometry; return c.border_width == 0 and c.x == a.x and c.y == a.y and c.width == a.width and c.height == a.height and not s.panel.visible and not s.sidebar.visible and not s.sidebar_scrollbar_panel.visible and s.sidebar_scrollbar.visible and s.sidebar:struts().right == 0 and s.workarea.width == a.width')
                press('alt+F11')
                wait('return client.focus and tostring(client.focus.fullscreen)', '"false"')
                wait('return tostring(screen[1].panel.visible)', '"true"')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_mode == 3 and s.sidebar.visible and s.sidebar_scrollbar_panel.visible == s.sidebar_scrollbar.visible and s.sidebar:struts().right == 300 and s.workarea.width == s.geometry.width-300')
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
                assert 'true' in lua('local m=__awesome_display_menu; local b=require("beautiful"); return m.theme.width == 270 and m.theme.height == 28 and m.theme.border_width == 1 and m.theme.bg_normal==b.menu_bg_normal and m.theme.bg_focus==b.menu_bg_focus and m.theme.fg_focus==b.menu_fg_focus')
                lua('__awesome_display_menu:item_enter(2)')
                capture("display-menu")
                press('Escape')
                wait('return tostring(__awesome_display_menu.wibox.visible)', '"false"')
                press('super+shift+q')
                wait('return tostring(__awesome_quit_confirmation.wibox.visible)', '"true"')
                assert 'true' in lua('local m=__awesome_quit_confirmation; local b=require("beautiful"); return m.theme.bg_normal==b.menu_bg_normal and m.theme.bg_focus==b.menu_bg_focus')
                capture("quit-confirmation")
                press('Escape')
                wait('return tostring(__awesome_quit_confirmation.wibox.visible)', '"false"')
                assert wm.poll() is None
                # Closing never happens on mouse-down; destroyed clients cancel their grab.
                for name in ("AwesomeGestureCancel", "AwesomeGestureRelease"):
                    processes.append(subprocess.Popen(["xmessage", "-name", name, "-geometry", "300x160", name], env=env, stdout=log, stderr=log))
                    wait(f'return client.focus and client.focus.instance', name)
                    coords = lua('_G.__closing_client=client.focus; _G.__closing_group=client.focus._private.titlebar_ui; _G.__closing_binding=client.focus._private.release_controls.titlebar_close; return (client.focus.x+client.focus.width-13)..":"..(client.focus.y+13)')
                    cx, cy = re.search(r'"(\d+):(\d+)"', coords).groups()
                    pointer("mousemove", cx, cy, "mousedown", 1)
                    assert 'true' in lua('return __closing_client.valid and __closing_binding.state.armed')
                    if name == "AwesomeGestureCancel":
                        lua('__closing_client:kill()')
                        wait('return tostring(__closing_group.disposed and not mousegrabber.isrunning())', '"true"')
                    pointer("mouseup", 1)
                    wait('return tostring(__closing_group.disposed)', '"true"')
                    assert 'false' in lua('return tostring(__closing_binding.state.armed)')
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
                # A second real screen subscribes without starting duplicate collectors.
                assert 'true' in lua('local d=screen[1].sidebar_data; _G.__polish_requests=d.collectors.crypto.requests; screen.fake_add(800,0,480,600); return screen[2].sidebar_data==d and d.collectors.crypto.requests==__polish_requests and screen[2].sidebar_crypto_prices.BTC.text==screen[1].sidebar_crypto_prices.BTC.text')
                wait('return tostring(screen[2].sidebar_scrollbar_panel.visible)', '"true"')
                assert 'true' in lua('_G.__removed_start_binding=screen[2].start_release_binding; _G.__removed_start_button=screen[2].start_button; _G.__removed_start_normal=screen[2].start_normal_image; local b=__removed_start_binding; return b.state.press(1) and b.state.armed and __removed_start_button._private.image==screen[2].start_pressed_image')
                assert 'true' in lua('_G.__removed_workspace_action=screen[2].taglist_release_actions[screen[2].tags[2]]; local a=__removed_workspace_action; local b=a.view_binding.state; b.press(1); local pressed=a.widget._workspace_animation_alpha; b.move(false); local leaving=a.widget._workspace_animation_alpha; b.move(true); local reentered=a.widget._workspace_animation_alpha; b.release(1,true); local quick=a.widget._workspace_animation_alpha; return pressed==42 and leaving>0 and leaving<pressed and reentered>leaving and quick>0 and screen[2].selected_tag==a.tag and a.widget._workspace_animation_timer~=nil and a.overlay.bg~=nil')
                lua('screen[2]:emit_signal("removed"); screen[2]:fake_remove()')
                assert 'true' in lua('local a=__removed_workspace_action; return screen.count()==1 and not mousegrabber.isrunning() and screen[2]==nil and __removed_start_binding.state.destroyed and __removed_start_button._private.image==__removed_start_normal and a.view_binding.state.destroyed and a.widget._workspace_animation_alpha==0 and a.widget._workspace_animation_timer==nil and a.overlay.bg==nil')
                assert 'true' in lua('local s=screen[1]; return screen.fake_add(800,0,480,600) and screen[2].sidebar_data==s.sidebar_data')
                wait('return tostring(screen[2].sidebar_scrollbar_panel.visible)', '"true"')
                bar_point = lua('local b=screen[2].sidebar_scrollbar_panel; return (b.x+30)..":"..(b.y+6)')
                bx, by = re.search(r'"(\d+):(\d+)"', bar_point).groups()
                pointer("mousemove", bx, by)
                wait('return screen[2].sidebar_scrollbar._interaction_state', 'hover')
                pointer("mousedown", 1)
                wait('return screen[2].sidebar_scrollbar._interaction_state', 'dragging')
                capture("scrollbar-dragging")
                assert 'true' in lua('_G.__removed_ui=screen[2].sidebar_ui; _G.__removed_components=screen[2].sidebar_components; __removed_ui.tooltips[1].show(screen[2].sidebar); screen[2]:fake_remove(); __removed_ui.destroy(); for _,c in pairs(__removed_components) do c.destroy() end; local d=screen[1].sidebar_data; local n=0; for _ in pairs(d.collectors.crypto.listeners) do n=n+1 end; return screen.count()==1 and n==1 and d.collectors.crypto.timer~=nil and __removed_ui.disposed and not mousegrabber.isrunning() and not __removed_components.scroll.bar_panel.visible')
                pointer("mouseup", 1)
                time.sleep(0.6)
                assert 'true' in helper('return h.component_disposed(__removed_ui,__removed_components)')
                assert 'sidebar collector:' not in logfile.read_text(), logfile.read_text()
                assert 'could not be parsed' not in logfile.read_text(), logfile.read_text()
                lua('awesome.quit()')
                assert wm.wait(timeout=5) == 0
                if composited:
                    assert compositor.poll() is None, "Private compositor exited during verification"
                    print("PASS: private Picom/XRender compositing (production GLX driver behavior not tested)")
                print("PASS: sidebar drag reorder/persistence/edge-scroll, native panel/widgets, Start/calendar/tray, wallpaper, fullscreen, workspaces, menus, reload and lock")
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
