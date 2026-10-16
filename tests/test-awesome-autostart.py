#!/usr/bin/env python3
"""Mock services to verify reload-safe autostart without starting real daemons."""
import configparser
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AutostartTest(unittest.TestCase):
    def test_clipman_xdg_autostart_is_disabled(self):
        entry = ROOT / "dotfiles/.config/autostart/xfce4-clipman-plugin-autostart.desktop"
        parser = configparser.ConfigParser(interpolation=None)
        self.assertTrue(parser.read(entry), f"missing autostart override: {entry}")
        self.assertTrue(parser.getboolean("Desktop Entry", "Hidden", fallback=False))

    def test_services_are_not_duplicated_on_reload(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            bin_dir = home / "bin"
            bin_dir.mkdir()
            for name in ("id", "sleep"):
                (bin_dir / name).symlink_to("/usr/bin/" + name)
            helpers = home / ".local/bin"
            helpers.mkdir(parents=True)
            (home / "Documents/notes/html").mkdir(parents=True)
            log = home / "calls"
            started_by_default = ["xsettingsd", "snixembed", "dunst", "lxqt-policykit-agent",
                                  "xss-lock", "syncthing", "mpd", "python3"]
            not_started_by_default = ["lxpanel", "clipmenud", "clipmenu", "xfce4-clipman",
                                      "xfce4-popup-clipman", "solaar"]
            support_commands = ["dbus-update-activation-environment", "xset", "localedef", "i3lock"]
            command_names = started_by_default + not_started_by_default + support_commands
            for path in [bin_dir / name for name in command_names] + [helpers / name for name in
                         ["desktop-display", "desktop-battery-watch", "desktop-locale-setup"]]:
                path.write_text('#!/bin/sh\nprintf "%s\\n" "${0##*/}" >> "$TEST_LOG"\n')
                path.chmod(0o755)
            pgrep = bin_dir / "pgrep"
            # Simulate one existing process for every successfully checked pattern.
            pgrep.write_text(f'''#!{os.sys.executable}
import fcntl, os, sys
with open(os.environ['TEST_STATE'], 'a+') as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    f.seek(0)
    patterns = f.read().splitlines()
    pattern = sys.argv[-1]
    if pattern in patterns:
        sys.exit(0)
    f.write(pattern + '\\n')
    sys.exit(1)
''')
            pgrep.chmod(0o755)
            env = dict(os.environ, HOME=str(home), PATH=str(bin_dir),
                       TEST_LOG=str(log), TEST_STATE=str(home / "state"))
            env.pop("DESKTOP_CLIPMENU_AUTOSTART", None)
            autostart = ["/bin/sh", str(ROOT / "dotfiles/.config/awesome/autostart")]
            for _ in range(2):
                result = subprocess.run(autostart, env=env, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                # The tray bridge intentionally waits for Awesome's native systray.
                time.sleep(2.2)
            calls = log.read_text().splitlines()
            for name in started_by_default:
                self.assertEqual(calls.count(name), 1, f"duplicate/missing service {name}: {calls}")
            self.assertEqual(calls.count("dbus-update-activation-environment"), 2)
            for name in not_started_by_default + ["openbox"]:
                self.assertNotIn(name, calls, f"unexpected automatic launch: {name}: {calls}")

            env["DESKTOP_CLIPMENU_AUTOSTART"] = "1"
            for _ in range(2):
                result = subprocess.run(autostart, env=env, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
            time.sleep(0.1)
            calls = log.read_text().splitlines()
            self.assertEqual(calls.count("clipmenud"), 1, f"opt-in should start once: {calls}")

            # Opt-in remains harmless if the user has not installed clipmenu.
            (bin_dir / "clipmenu").unlink()
            (home / "state").write_text("")
            log.write_text("")
            result = subprocess.run(autostart, env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("clipmenud", log.read_text().splitlines())


if __name__ == "__main__":
    unittest.main()
