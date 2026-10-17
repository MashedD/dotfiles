#!/usr/bin/env python3
"""Runtime smoke test on a private Xvfb server and private D-Bus bus.

Never starts the real session autostart or changes the live display layout.
"""
import os
import argparse
import ctypes
import re
from pathlib import Path
import shutil
import shlex
import subprocess
import sys
import tempfile
import time
from datetime import date, timedelta

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests/helpers"))
import awesome_controls
import awesome_sidebar
from awesome_lock import PrivateLock
import awesome_titlebars
import awesome_keyboard

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


class SingleScenario(argparse.Action):
    def __call__(self, parser, namespace, value, option_string=None):
        if namespace.scenario is not None:
            parser.error('--scenario may only be specified once')
        namespace.scenario = value


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scenario', choices=('all', 'titlebars', 'workspace-transfer', 'sidebar-documents', 'menu-popups'), action=SingleScenario,
                        help='checks to run (default: all)')
    parser.add_argument('--composited', action='store_true', help='use private Picom/XRender')
    parser.add_argument('--inside', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    args.scenario = args.scenario or 'all'
    return args


def run_timed(name, check):
    print(f'RUN: {name}', flush=True)
    started = time.monotonic()
    check()
    print(f'PASS: {name} ({time.monotonic()-started:.2f}s)', flush=True)


def run_focused(scenario, *, prepare, controls, destruction):
    """Return False to continue the unchanged full-session sequence."""
    if scenario in ('all', 'workspace-transfer', 'sidebar-documents', 'menu-popups'):
        return False
    if scenario != 'titlebars':
        raise ValueError(f'Unknown scenario: {scenario}')
    prepare()
    controls()
    destruction()
    return True


def main():
    args = parse_args()
    if not args.inside:
        return subprocess.call(["dbus-run-session", "--", sys.executable, __file__, "--inside", *sys.argv[1:]])
    started = time.monotonic()
    composited = args.composited
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
        shutil.copy2(ROOT / "dotfiles/.local/bin/desktop-lock", helpers / "desktop-lock")
        crypto_helper = helpers / "crypto-prices"
        crypto_helper.write_text("#!/bin/sh\nprintf 'crypto-v1\\tfresh\\t%s\\t%s\\n' \"$(date +%s)\" '#[fg=#006400]BTC #[fg=#55ff99,bold]$97.123 #[fg=#006400]ETH #[fg=#55ff99,bold]$3.456 #[fg=#006400]LTC #[fg=#55ff99,bold]$123,45'\n")
        crypto_helper.chmod(0o755)
        codex_helper = helpers / "codex-usage"
        codex_helper.write_text("#!/bin/sh\nprintf 'codex-v1\\tfresh\\t%s\\t%s\\t%s\\n' \"$(date +%s)\" 'C 5h #[fg=#55ff99]84%#[fg=#006400]@#[fg=#55ff99]Sat 13:46 7d #[fg=#55ff99]33%#[fg=#006400]@#[fg=#55ff99]Wed 06:41' 'Sat 24.10 13:46 · Tue 27.10 13:46 · Fri 30.10 13:46'\n")
        codex_helper.chmod(0o755)
        aurora_fixture = ROOT / "dotfiles/.local/share/wallpapers/aurora-cabin.png"
        shutil.copy2(aurora_fixture, testhome / ".local/share/wallpapers/aurora-cabin.png")
        shutil.copy2(aurora_fixture, testhome / "Pictures/Wallpapers/pictures-wallpaper.png")
        icon_source = ROOT / "dotfiles/.local/share/icons/hicolor/32x32/apps/tux-start.png"
        icon_target = testhome / ".local/share/icons/hicolor/32x32/apps/tux-start.png"
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
        (testhome / ".config").mkdir(exist_ok=True)
        (testhome / ".config/mimeapps.list").write_text(
            "[Default Applications]\ntext/plain=awesome-test-opener.desktop;\n"
            "text/markdown=awesome-test-opener.desktop;\n")
        (testhome / ".local/share/applications/awesome-test-opener.desktop").write_text(
            "[Desktop Entry]\nType=Application\nName=Awesome test document opener\n"
            f"Exec={bin_dir / 'xdg-open'} %U\nTerminal=false\n"
            "NoDisplay=true\nMimeType=text/plain;text/markdown;\n")
        (testhome / ".local/share/applications/mimeinfo.cache").write_text(
            "[MIME Cache]\ntext/markdown=awesome-test-opener.desktop;\n"
            "text/plain=awesome-test-opener.desktop;\n")
        volume_helper = helpers / "desktop-volume"
        volume_helper.write_text('#!/bin/sh\necho "$1" >> "$TEST_ACTIONS"\n')
        volume_helper.chmod(0o755)
        control_center = testhome / ".local/bin/desktop-control-center"
        control_center.parent.mkdir(parents=True, exist_ok=True)
        control_center.write_text('#!/bin/sh\necho control-center >> "$TEST_ACTIONS"\n')
        control_center.chmod(0o755)
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

                def x11_state(expression):
                    window = re.search(r'\d+', lua('return tostring(' + expression + '.window)')).group(0)
                    extents = subprocess.run(['xprop', '-id', window, '_NET_FRAME_EXTENTS'], env=env,
                                             capture_output=True, text=True, check=True, timeout=3).stdout
                    values = tuple(map(int, re.search(r'=\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+)', extents).groups()))
                    output = subprocess.run(['xdotool', 'getwindowgeometry', '--shell', window], env=env,
                                            capture_output=True, text=True, check=True, timeout=3).stdout
                    geometry = dict(line.split('=', 1) for line in output.splitlines())
                    return dict(extents=values, geometry=tuple(int(geometry[key]) for key in ('X', 'Y', 'WIDTH', 'HEIGHT')))

                def request_x11_state(expression, names, enabled):
                    # Send a real EWMH client request only to this private display.
                    class Data(ctypes.Union):
                        _fields_ = [('l', ctypes.c_long * 5), ('b', ctypes.c_char * 20)]
                    class Message(ctypes.Structure):
                        _fields_ = [('type', ctypes.c_int), ('serial', ctypes.c_ulong),
                                    ('send_event', ctypes.c_int), ('display', ctypes.c_void_p),
                                    ('window', ctypes.c_ulong), ('message_type', ctypes.c_ulong),
                                    ('format', ctypes.c_int), ('data', Data)]
                    class Event(ctypes.Union):
                        _fields_ = [('message', Message), ('pad', ctypes.c_long * 24)]
                    xlib = ctypes.CDLL('libX11.so.6')
                    xlib.XOpenDisplay.argtypes = [ctypes.c_char_p]
                    xlib.XOpenDisplay.restype = ctypes.c_void_p
                    xlib.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
                    xlib.XDefaultRootWindow.restype = ctypes.c_ulong
                    xlib.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
                    xlib.XInternAtom.restype = ctypes.c_ulong
                    xlib.XSendEvent.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_long, ctypes.POINTER(Event)]
                    xlib.XFlush.argtypes = [ctypes.c_void_p]
                    xlib.XCloseDisplay.argtypes = [ctypes.c_void_p]
                    display = xlib.XOpenDisplay(env['DISPLAY'].encode())
                    assert display and 1 <= len(names) <= 2
                    try:
                        event = Event()
                        event.message.type = 33
                        event.message.display = display
                        event.message.window = int(re.search(r'\d+', lua('return tostring(' + expression + '.window)')).group(0))
                        event.message.message_type = xlib.XInternAtom(display, b'_NET_WM_STATE', 0)
                        event.message.format = 32
                        event.message.data.l[0] = 1 if enabled else 0
                        for index, name in enumerate(names, 1):
                            event.message.data.l[index] = xlib.XInternAtom(display, name.encode(), 0)
                        event.message.data.l[3] = 1
                        assert xlib.XSendEvent(display, xlib.XDefaultRootWindow(display), 0,
                                              (1 << 20) | (1 << 19), ctypes.byref(event))
                        xlib.XFlush(display)
                    finally:
                        xlib.XCloseDisplay(display)

                def capture_titlebar(name):
                    geometry=lua('local c=__narrow_c; return (c.width+2*c.border_width).."x"..(26+2*c.border_width).."+"..c.x.."+"..c.y')
                    bounds=re.search(r'(\d+x\d+\+\d+\+\d+)',geometry).group(1)
                    path=visual_dir/(name+'.png')
                    subprocess.run(['import','-window','root','-crop',bounds,str(path)],env=env,check=True,timeout=5)
                    return path

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

                def menu_item_bounds(menu_expression, index, probe_x=100):
                    bounds = lua('local m=' + menu_expression + '; local item=m.items[' + str(index) + ']; local x=' + str(probe_x) + '; '
                        'for y=0,m.wibox.height-1 do for _,v in ipairs(m.wibox:find_widgets(x,y)) do '
                        'if v.widget==item._background then return table.concat({math.floor(m.wibox.x+v.x),math.floor(m.wibox.y+v.y),math.ceil(v.width),math.ceil(v.height)}, ":") end end end; return "missing"')
                    match = re.search(r'(\d+):(\d+):(\d+):(\d+)', bounds)
                    assert match, f"Could not locate menu item {index}: {bounds}"
                    return tuple(map(int, match.groups()))

                def menu_item_point(menu_expression, index, x=100):
                    left, top, width, height = menu_item_bounds(menu_expression, index, x)
                    return left + width // 2, top + height // 2

                def capture_menu_item(menu_expression, index, name):
                    x, y, width, height = menu_item_bounds(menu_expression, index)
                    path = visual_dir / f"{name}.png"
                    subprocess.run(["import", "-window", "root", "-crop", f"{width}x{height}+{x}+{y}", "+repage", str(path)],
                                   env=env, check=True, timeout=5)
                    return path

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
                    try:
                        diagnostic = helper('local r=""; for _,c in ipairs(client.get()) do r=r..tostring(c.class)..":"..c.type..":"..c.x..","..c.y..","..c.width..","..c.height..":screen="..c.screen.index..":visible="..tostring(c:isvisible()); for k,v in pairs(c:struts()) do r=r..":"..k.."="..v end; r=r.."\\n" end; return r')
                    except Exception as error:
                        diagnostic = f"Runtime diagnostic failed: {error}"
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

                def press(keys):
                    subprocess.run(["xdotool", "key", "--clearmodifiers", keys], env=env,
                                   check=True, timeout=3)
                    time.sleep(0.15)

                def spawn(name, geometry):
                    process = subprocess.Popen(['xmessage', '-name', name, '-geometry', geometry, name],
                                               env=env, stdout=log, stderr=log)
                    processes.append(process)
                    return process

                def check_titlebars():
                    run_timed('titlebars.controls', lambda: awesome_titlebars.verify_controls(
                        lua=lua, wait=wait, pointer=pointer, capture=capture, helper=helper,
                        press=press, visual=visual, env=env, capture_titlebar=capture_titlebar,
                        compare_visual=compare_visual, log_text=logfile.read_text))

                def check_titlebar_destruction():
                    run_timed('titlebars.destruction', lambda: awesome_titlebars.verify_destruction(
                        spawn=spawn, wait=wait, lua=lua, pointer=pointer))

                def finish_session(scenario):
                    assert 'sidebar collector:' not in logfile.read_text(), logfile.read_text()
                    assert 'could not be parsed' not in logfile.read_text(), logfile.read_text()
                    lua('awesome.quit()')
                    assert wm.wait(timeout=5) == 0
                    if composited:
                        assert compositor.poll() is None, 'Private compositor exited during verification'
                        print('PASS: private Picom/XRender compositing (production GLX driver behavior not tested)')
                    if scenario == 'all':
                        print('PASS: sidebar drag reorder/persistence/edge-scroll, native panel/widgets, Start/calendar/tray, wallpaper, fullscreen, workspaces, menus, reload and lock')
                    else:
                        print(f'PASS: focused scenario {scenario} (other session scenarios not run)')
                    print(f'PASS: session scenario={scenario} ({time.monotonic()-started:.2f}s)', flush=True)

                if run_focused(args.scenario,
                    prepare=lambda: awesome_titlebars.prepare(lua=lua, wait=wait, press=press, spawn=spawn),
                    controls=check_titlebars, destruction=check_titlebar_destruction):
                    finish_session('titlebars')
                    return 0

                wait('return #screen[1].tags', '4')
                if args.scenario == 'workspace-transfer':
                    spawn('AwesomeSmokeA', '400x200+100+100')
                    wait('for _,c in ipairs(client.get()) do if c.instance=="AwesomeSmokeA" then return "ready" end end; return "waiting"', '"ready"')
                    run_timed('workspace.transfer', lambda: awesome_controls.verify_workspace_transfer(
                        lua=lua, pointer=pointer, wait=wait, workspace_point=workspace_point,
                        log_text=logfile.read_text))
                    finish_session(args.scenario)
                    return 0
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
                assert 'true' in lua('local s=screen[1]; local b=s.sidebar; return b and b.visible and not s.panel_clock_container.visible and s.sidebar_header and s.sidebar_header.forced_height == 26 and s.sidebar_mode == 3 and b.ontop and b:struts().right == 300 and b.width == 300 and b.border_width == 0 and s.sidebar_cpu and s.sidebar_battery and s.sidebar_volume and s.sidebar_trash_status and s.sidebar_trash_icon and s.sidebar_trash_state and s.sidebar_trash_timer.timeout == 30 and s.sidebar_media_text and s.sidebar_root_text and s.sidebar_weather_text and s.sidebar_crypto_timer.timeout == 60 and s.sidebar_codex_card.forced_height == nil and s.sidebar_codex_timer.timeout == 60 and s.sidebar_audio_header == nil and s.sidebar_wallpaper_preview and s.sidebar_todo_card and #s.sidebar_todo_entries == 5 and s.sidebar_todo_entries[5] == "Fifth item" and s.sidebar_calendar_card and not s.sidebar_date_calendar and s.sidebar_calendar_grid and s.sidebar_calendar_weekday_order == "MoTuWeThFrSaSu" and #s.sidebar_calendar_entries == 7 and s.sidebar_calendar_entries[1].day == "past" and s.sidebar_calendar_entries[2].time == "08:15-09:00" and s.sidebar_calendar_entries[3].text == "visit: Today appointment" and s.sidebar_calendar_entries[6].text == "Third future event" and s.sidebar_todo_timer.timeout == 60 and s.sidebar_calendar_timer.timeout == 60 and s.panel_cpu == nil and s.panel_battery == nil and s.panel_volume == nil and s.workarea.width == s.geometry.width-300 and b.x+b.width == s.geometry.x+s.geometry.width and b.y == s.geometry.y+30 and b.height == s.geometry.height-30')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_clock_mode == "text" and s.sidebar_digital_time.visible and not s.sidebar_clock.visible and s.sidebar_clock_card.forced_height == 66')
                menu_audit = lua('local m=__awesome_main_menu; local panel,icon,monitor,display=false,false,false,false; for _,item in ipairs((m and m.items) or {}) do local text=item.label and item.label:get_markup() or ""; text=text:gsub("<[^>]*>",""):gsub("&amp;","&"); if text=="Control Panel" then panel=true; icon=item.icon~=nil elseif text=="Monitor" then monitor=true elseif text=="Display outputs" then display=true end end; return "panel="..tostring(panel)..";icon="..tostring(icon)..";monitor="..tostring(monitor)..";display="..tostring(display)')
                assert all(token in menu_audit for token in ('panel=true', 'icon=true', 'monitor=false', 'display=false')), menu_audit
                quick_launch_audit = lua('local q=screen[1].sidebar_quick_launch_buttons; local c=q["Control Panel"]; return tostring(c~=nil and c.entry.argv[1]==os.getenv("HOME").."/.local/bin/desktop-control-center")..":"..tostring(q.Monitor==nil)..":"..tostring(q.Volume==nil)')
                assert 'true:true:true' in quick_launch_audit, quick_launch_audit
                control_center_position = widget_point('screen[1].sidebar_quick_launch_buttons["Control Panel"].widget', x=240)
                pointer("mousemove", *control_center_position, "click", 1)
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline and "control-center" not in actions_file.read_text():
                    time.sleep(0.05)
                assert "control-center" in actions_file.read_text(), actions_file.read_text()
                if args.scenario == 'sidebar-documents':
                    run_timed('sidebar.documents', lambda: awesome_sidebar.verify_document_launches(
                        lua=lua, wait=wait, pointer=pointer, widget_point=widget_point,
                        actions_file=actions_file, testhome=testhome, log_text=logfile.read_text))
                    finish_session(args.scenario)
                    return 0
                if args.scenario == 'menu-popups':
                    press('super+p')
                    wait('return tostring(__awesome_display_menu.wibox.visible)', '"true"')
                    assert 'true' in lua('local m=__awesome_display_menu; local g=screen[1].geometry; return m.x == g.x + math.floor((g.width-m.wibox.width)/2) and m.y == g.y + math.floor((g.height-m.wibox.height)/2)')
                    press('Escape')
                    wait('return tostring(__awesome_display_menu.wibox.visible)', '"false"')
                    press('super+shift+q')
                    wait('return tostring(__awesome_quit_confirmation.wibox.visible)', '"true"')
                    assert 'true' in lua('local m=__awesome_quit_confirmation; local g=screen[1].geometry; return m.x == g.x + math.floor((g.width-m.wibox.width)/2) and m.y == g.y + math.floor((g.height-m.wibox.height)/2)')
                    press('Escape')
                    wait('return tostring(__awesome_quit_confirmation.wibox.visible)', '"false"')
                    finish_session(args.scenario)
                    return 0
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
                codex_helper.write_text('#!/bin/sh\nprintf "codex-v1\\tfresh\\t%s\\tC 5h 0%%@Sat 13:46 7d 33%%@Wed 06:41\\tA & B < C\\n" "$(date +%s)"\n')
                lua('screen[1].sidebar_codex_refresh()')
                wait('return tostring(screen[1].sidebar_codex_5h.remaining)', '0')
                assert 'A &amp; B &lt; C' in lua('return screen[1].sidebar_codex_resets.markup')
                codex_helper.write_text('#!/bin/sh\nexit 1\n')
                lua('screen[1].sidebar_codex_refresh()')
                wait('return tostring(screen[1].sidebar_data.state("codex").stale)', 'true')
                assert 'true' in lua('local t=screen[1].sidebar_codex_timer.tooltip; t.timer_function(); return t.textbox.markup:find("Last success:",1,true)~=nil and t.textbox.markup:find("Command failed",1,true)~=nil')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_data.state("codex").value.five==0 and s.sidebar_codex_5h.remaining==nil and not s.sidebar_codex_5h.bar.visible and s.sidebar_codex_5h.summary.text:find("unavailable",1,true)~=nil')
                # A successful helper invocation is not proof of fresh source data.
                for output,reason in (('codex-v1\\tstale\\t1\\tC 5h 99%@Sat 13:46 7d 99%@Wed 06:41\\t--','Source stale'),
                                      ('codex-v1\\tfresh\\t1\\tC 5h 99%@Sat 13:46 7d 99%@Wed 06:41\\t--','expired'),
                                      ('C* 5h 99%@Sat 13:46 7d 99%@Wed 06:41\\t--','metadata')):
                    codex_helper.write_text('#!/bin/sh\nprintf \'%b\\n\' '+shlex.quote(output)+'\n')
                    lua('screen[1].sidebar_codex_refresh()')
                    wait('local d=screen[1].sidebar_data; return tostring(not d.collectors.codex.pending and d.state("codex").error~=nil)', '"true"')
                    assert 'true' in lua(f'return screen[1].sidebar_data.state("codex").error:find("{reason}",1,true)~=nil')
                    assert 'true' in lua(f'local t=screen[1].sidebar_codex_timer.tooltip; t.timer_function(); return t.textbox.markup:find("Last success:",1,true)~=nil and t.textbox.markup:find("{reason}",1,true)~=nil')
                    assert 'true' in lua('local s=screen[1]; return s.sidebar_codex_5h.remaining==nil and s.sidebar_codex_7d.remaining==nil and not s.sidebar_codex_5h.bar.visible and not s.sidebar_codex_7d.bar.visible and s.sidebar_data.state("codex").value.five==0 and not s.sidebar_codex_5h.summary.text:find("%",1,true) and not s.sidebar_codex_7d.summary.text:find("%",1,true)')
                codex_helper.write_text('#!/bin/sh\nprintf "codex-v1\\tfresh\\t%s\\tC 5h 0%%@Sat 13:46 7d 33%%@Wed 06:41\\t--\\n" "$(date +%s)"\n')
                lua('screen[1].sidebar_codex_refresh()')
                wait('local s=screen[1]; return tostring(not s.sidebar_data.collectors.codex.pending and s.sidebar_codex_5h.remaining==0)', '"true"')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_codex_5h.bar.visible and s.sidebar_codex_5h.summary.text:find("0% left",1,true)~=nil and not s.sidebar_data.state("codex").stale')
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
                awesome_controls.verify_reorder_drag(start=source,end=target,section='calendar',
                    lua=lua,pointer=pointer,wait=wait)
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

                awesome_controls.verify_sidebar_edge_scroll(
                    lua=lua, pointer=pointer, sidebar_title_point=sidebar_title_point,
                    log_text=logfile.read_text)
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
                digital_time_point = widget_point('screen[1].sidebar_digital_time', x=150)
                pointer("mousemove", *digital_time_point, "click", 1)
                wait('return screen[1].sidebar_clock_mode', 'analog')
                assert 'true:true:true' in lua('local s=screen[1]; return tostring(s.sidebar_clock_mode == "analog")..":"..tostring(s.sidebar_date_calendar == nil)..":"..tostring(s.sidebar_calendar_selected_date() == os.date("%Y-%m-%d"))')
                current_month = lua('return screen[1].sidebar_calendar_month()').strip().split('"')[1]
                lua('screen[1].sidebar_calendar_next_action()')
                wait('return tostring(screen[1].sidebar_calendar_month() ~= os.date("%Y-%m"))', '"true"')
                calendar_month_before = lua('return screen[1].sidebar_calendar_month()').strip().split('"')[1]
                awesome_controls.verify_pointer_recovery(lua=lua, pointer=pointer, wait=wait)
                awesome_controls.verify_geometry_cancellation(
                    lua=lua, pointer=pointer, wait=wait, widget_point=widget_point,
                    expected_month=calendar_month_before)
                lua('screen[1].sidebar_calendar_previous_action(); screen[1].sidebar_calendar_previous_action()')
                wait('return screen[1].sidebar_calendar_month()', f'"{current_month}"')
                lua('screen[1].sidebar_calendar_select_date(os.date("%Y-%m-%d"))')
                assert 'true:true' in lua('local s=screen[1]; local n=0; for _,entry in ipairs(s.sidebar_calendar_entries) do if entry.date == s.sidebar_calendar_selected_date() then n=n+1 end end; return tostring(s.sidebar_calendar_day_cells()[s.sidebar_calendar_selected_date()] ~= nil)..":"..tostring(n == 2)')
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
                control_position = widget_point('screen[1].sidebar_quick_launch_buttons["Control Panel"].widget', x=60)
                pointer("mousemove", *control_position, "click", 1)
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline and "control-center" not in actions_file.read_text():
                    time.sleep(0.05)
                assert "control-center" in actions_file.read_text(), actions_file.read_text()
                wallpaper = subprocess.run(["xprop", "-root", "_XROOTPMAP_ID"], env=env,
                                           capture_output=True, text=True, check=True, timeout=3).stdout
                assert "PIXMAP" in wallpaper, wallpaper
                wait('return screen[1].sidebar_root_text.text', 'Free /')
                assert 'aurora-cabin.png' in lua('return screen[1].sidebar_wallpaper_name.text')
                next_buttons = lua('local b=screen[1].sidebar_wallpaper_next; return tostring(screen[1].sidebar_wallpaper_count)..":"..tostring(#b:buttons())..":"..tostring(b._sidebar_release_binding~=nil)')
                assert '2:0:true' in next_buttons, next_buttons
                lua('screen[1].sidebar_wallpaper_next_action()')
                wallpaper_name = lua('return tostring(screen[1].sidebar_wallpaper_index)..":"..screen[1].sidebar_wallpaper_name.text')
                assert '2:pictures-wallpaper.png' in wallpaper_name, wallpaper_name
                lua('screen[1].sidebar_wallpaper_next_action()')
                wallpaper_name = lua('return tostring(screen[1].sidebar_wallpaper_index)..":"..screen[1].sidebar_wallpaper_name.text')
                assert '1:aurora-cabin.png' in wallpaper_name, wallpaper_name
                lua('screen[1].sidebar_wallpaper_previous_action(); screen[1].sidebar_wallpaper_previous_action(); screen[1].sidebar_wallpaper_apply()')
                assert (testhome / ".local/state/awesome/wallpaper").read_text().strip().endswith("aurora-cabin.png")
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
                pointer("mousemove", 700, 15, "click", 1)
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"false"')
                subprocess.run(["xdotool", "mousemove", "30", "15", "click", "1"], env=env, check=True)
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"true"')
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
                press('Escape')
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"false"')
                press('super')
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"true"')
                lua('__start_run_cmd=screen[1].start_menu.items[2].cmd; __start_mnemonic_action=nil; screen[1].start_menu.items[2].cmd=function() __start_mnemonic_action="run" end')
                press('Down')
                assert 'true' in lua('return screen[1].start_menu.sel==1')
                press('Down')
                assert 'true' in lua('return screen[1].start_menu.sel==2')
                press('Return')
                wait('return tostring(__start_mnemonic_action)', '"run"')
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"false"')
                lua('screen[1].start_menu.items[2].cmd=__start_run_cmd; __start_run_cmd=nil; __start_mnemonic_action=nil')
                press('super')
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"true"')
                mnemonic_state=lua('''
                    local expected={[1]="a",[2]="r",[4]="k",[5]="p",[6]="f",[7]="d",
                        [8]="g",[9]="e",[11]="m",[12]="v",[13]="y",[15]="q",
                        [16]="u",[18]="l",[19]="o",[20]="s",[21]="w"}
                    local seen,count,details={},0,{}
                    for index,item in ipairs(screen[1].start_menu.items) do
                        local key=expected[index]
                        details[#details+1]=index..":"..tostring(item.akey)..":"..tostring(item.label and item.label.markup)
                        if key then
                            if item.akey~=key or not item.label.markup:find("<u>",1,true) then return table.concat(details,"|") end
                            if seen[key] then return table.concat(details,"|duplicate:")..key end
                            seen[key],count=true,count+1
                        elseif item.akey and item.akey~="" then return table.concat(details,"|unexpected:") end
                    end
                    return table.concat(details,"|").."|count="..count
                ''')
                assert 'count=17' in mnemonic_state, mnemonic_state
                lua('__start_quake1_cmd=screen[1].start_menu.items[15].cmd; __start_mnemonic_action=nil; screen[1].start_menu.items[15].cmd=function() __start_mnemonic_action="quake1" end')
                press('q')
                wait('return tostring(__start_mnemonic_action)', '"quake1"')
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"false"')
                lua('screen[1].start_menu.items[15].cmd=__start_quake1_cmd; __start_quake2_cmd=screen[1].start_menu.items[16].cmd')
                subprocess.run(["xdotool", "mousemove", "30", "15", "click", "1"], env=env, check=True)
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"true"')
                lua('__start_mnemonic_action=nil; screen[1].start_menu.items[16].cmd=function() __start_mnemonic_action="quake2" end')
                press('u')
                wait('return tostring(__start_mnemonic_action)', '"quake2"')
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"false"')
                lua('screen[1].start_menu.items[16].cmd=__start_quake2_cmd; __start_quake1_cmd=nil; __start_quake2_cmd=nil; __start_mnemonic_action=nil')
                subprocess.run(["xdotool", "mousemove", "30", "15", "click", "1"], env=env, check=True)
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"true"')
                right_click_point=menu_item_point('screen[1].start_menu', 1)
                pointer("mousemove", *right_click_point, "click", 3)
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"false"')
                subprocess.run(["xdotool", "mousemove", "30", "15", "click", "1"], env=env, check=True)
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"true"')
                awesome_controls.verify_native_menu_release(
                    lua=lua, pointer=pointer, wait=wait, press=press,
                    menu_item_point=menu_item_point, capture_menu_item=capture_menu_item,
                    compare_visual=compare_visual, visual=visual)
                subprocess.run(["xdotool", "mousemove", "900", "700", "click", "1"], env=env, check=True)
                subprocess.run(["xdotool", "mousemove", "30", "15", "click", "1"], env=env, check=True)
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"true"')
                subprocess.run(["xdotool", "mousemove", "900", "700", "click", "1"], env=env, check=True)
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"false"')
                press('super')
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"true"')
                press('super')
                wait('return tostring(screen[1].start_menu.wibox.visible)', '"false"')
                awesome_controls.verify_workspace_pointer(
                    lua=lua, pointer=pointer, wait=wait, press=press,
                    workspace_point=workspace_point, capture_workspace=capture_workspace,
                    compare_visual=compare_visual, visual=visual)
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
                    spawn(name, '400x200')
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
                check_titlebars()
                run_timed('keyboard', lambda: awesome_keyboard.verify(
                    lua=lua,press=press,pointer=pointer,wait=wait,env=env,visual=visual,
                    compare_visual=compare_visual))
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
                run_timed('workspace.transfer', lambda: awesome_controls.verify_workspace_transfer(
                    lua=lua, pointer=pointer, wait=wait, workspace_point=workspace_point,
                    log_text=logfile.read_text))
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
                awesome_controls.verify_fullscreen_decorations(lua=lua, wait=wait, x11_state=x11_state,
                                                              press=press, request_x11_state=request_x11_state)
                press('super+shift+s')
                press('super+shift+s')
                press('super+shift+s')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_mode == 3 and s.sidebar.visible and s.workarea.width == s.geometry.width-300')
                press('alt+F11')
                wait('return client.focus and tostring(client.focus.fullscreen)', '"true"')
                assert 'true' in lua('local c=client.focus; local s=c.screen; local a=s.geometry; return c.border_width == 0 and c.x == a.x and c.y == a.y and c.width == a.width and c.height == a.height and not s.panel.visible and not s.sidebar.visible and not s.sidebar_scrollbar_panel.visible and s.sidebar_scrollbar.visible and s.sidebar:struts().right == 0 and s.workarea.width == a.width')
                awesome_controls.verify_fullscreen_workspaces(lua=lua, wait=wait)
                press('alt+F11')
                wait('return client.focus and tostring(client.focus.fullscreen)', '"false"')
                wait('return tostring(screen[1].panel.visible)', '"true"')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_mode == 3 and s.sidebar.visible and s.sidebar_scrollbar_panel.visible == s.sidebar_scrollbar.visible and s.sidebar:struts().right == 300 and s.workarea.width == s.geometry.width-300')
                press('super+shift+s')
                assert 'true' in lua('local s=screen[1]; return s.sidebar_mode == 0 and not s.sidebar.visible and s.workarea.width == s.geometry.width')
                lua('for _,c in ipairs(client.get()) do if c.instance == "AwesomeSmokeB" then c:move_to_tag(screen[1].selected_tag); c.minimized=false; c.fullscreen=true end end')
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
                assert 'true' in lua('local m=__awesome_display_menu; local g=screen[1].geometry; return m.x == g.x + math.floor((g.width-m.wibox.width)/2) and m.y == g.y + math.floor((g.height-m.wibox.height)/2)')
                assert 'true' in lua('local m=__awesome_display_menu; local b=require("beautiful"); return m.theme.width == 270 and m.theme.height == 28 and m.theme.border_width == 1 and m.theme.bg_normal==b.menu_bg_normal and m.theme.bg_focus==b.menu_bg_focus and m.theme.fg_focus==b.menu_fg_focus')
                lua('__awesome_display_menu:item_enter(2)')
                capture("display-menu")
                press('Escape')
                wait('return tostring(__awesome_display_menu.wibox.visible)', '"false"')
                press('super+shift+q')
                wait('return tostring(__awesome_quit_confirmation.wibox.visible)', '"true"')
                assert 'true' in lua('local m=__awesome_quit_confirmation; local b=require("beautiful"); local g=screen[1].geometry; return m.x == g.x + math.floor((g.width-m.wibox.width)/2) and m.y == g.y + math.floor((g.height-m.wibox.height)/2) and m.theme.bg_normal==b.menu_bg_normal and m.theme.bg_focus==b.menu_bg_focus')
                capture("quit-confirmation")
                press('Escape')
                wait('return tostring(__awesome_quit_confirmation.wibox.visible)', '"false"')
                assert wm.poll() is None
                check_titlebar_destruction()
                # Real Win+L and foreground i3lock, scoped strictly to private Xvfb.
                PrivateLock(env, helpers / "desktop-lock", logfile.read_text).exercise(press)
                press('super+shift+q')
                wait('return tostring(__awesome_quit_confirmation.wibox.visible)', '"true"')
                press('Escape')
                assert wm.poll() is None, 'Escape from quit confirmation must cancel'
                # A second real screen subscribes without starting duplicate collectors.
                assert 'true' in lua('local d=screen[1].sidebar_data; _G.__polish_requests=d.collectors.crypto.requests; screen.fake_add(800,0,480,600); return screen[2].sidebar_data==d and d.collectors.crypto.requests==__polish_requests and screen[2].sidebar_crypto_prices.BTC.text==screen[1].sidebar_crypto_prices.BTC.text')
                wait('return tostring(screen[2].sidebar_scrollbar_panel.visible)', '"true"')
                assert 'true' in lua('_G.__removed_start_binding=screen[2].start_release_binding; _G.__removed_start_button=screen[2].start_button; _G.__removed_start_normal=screen[2].start_normal_image; local b=__removed_start_binding; return b.state.press(1) and b.state.armed and __removed_start_button._private.image==screen[2].start_pressed_image')
                assert 'true' in lua('_G.__removed_workspace_action=screen[2].taglist_release_actions[screen[2].tags[2]]; local a=__removed_workspace_action; local b=a.view_binding.state; b.press(1); local pressed=a.widget._workspace_animation_alpha; b.move(false); local leaving=a.widget._workspace_animation_alpha; b.move(true); local reentered=a.widget._workspace_animation_alpha; b.release(1,true); local quick=a.widget._workspace_animation_alpha; return pressed==34 and leaving>0 and leaving<pressed and reentered>leaving and quick>0 and screen[2].selected_tag==a.tag and a.widget._workspace_animation_timer~=nil and a.overlay.bg~=nil')
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
                assert 'true' in lua('_G.__removed_ui=screen[2].sidebar_ui; _G.__removed_components=screen[2].sidebar_components; __removed_ui.tooltips[1].show(screen[2].sidebar); screen[2]:fake_remove(); __removed_ui.destroy(); for _,c in pairs(__removed_components) do c.destroy() end; local d=screen[1].sidebar_data; local n=0; for _ in pairs(d.collectors.crypto.listeners) do n=n+1 end; return screen.count()==1 and n==1 and d.collectors.crypto.timer~=nil and __removed_ui.disposed and not mousegrabber.isrunning() and not __removed_components.scroll.bar_panel.visible'), lua('local d=screen[1].sidebar_data; local n=0; for _ in pairs(d.collectors.crypto.listeners) do n=n+1 end; return "screens="..screen.count().." listeners="..n.." timer="..tostring(d.collectors.crypto.timer~=nil).." disposed="..tostring(__removed_ui.disposed).." grab="..tostring(mousegrabber.isrunning()).." scrollbar="..tostring(__removed_components.scroll.bar_panel.visible)')
                pointer("mouseup", 1)
                time.sleep(0.6)
                assert 'true' in helper('return h.component_disposed(__removed_ui,__removed_components)')
                finish_session('all')
        finally:
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
