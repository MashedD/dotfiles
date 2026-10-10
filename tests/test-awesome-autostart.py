#!/usr/bin/env python3
"""Mock services to verify reload-safe autostart without starting real daemons."""
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AutostartTest(unittest.TestCase):
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
            names = ["xsettingsd", "lxpanel", "snixembed", "dunst", "lxqt-policykit-agent",
                     "clipmenud", "xss-lock", "syncthing", "mpd", "python3",
                     "dbus-update-activation-environment", "xset", "localedef", "i3lock", "clipmenu", "xfce4-clipman", "xfce4-popup-clipman", "solaar"]
            for path in [bin_dir / name for name in names] + [helpers / name for name in
                         ["openbox-display", "openbox-battery-watch", "openbox-locale-setup"]]:
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
            for _ in range(2):
                result = subprocess.run(["/bin/sh", str(ROOT / "dotfiles/.config/awesome/autostart")],
                                        env=env, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                # The tray bridge intentionally waits for Awesome's native systray.
                time.sleep(2.2)
            calls = log.read_text().splitlines()
            for name in names[:10]:
                expected = 0 if name == "lxpanel" else 1
                self.assertEqual(calls.count(name), expected, f"duplicate/missing service {name}: {calls}")
            self.assertEqual(calls.count("dbus-update-activation-environment"), 2)
            self.assertNotIn("lxpanel", calls)
            self.assertNotIn("solaar", calls)
            self.assertNotIn("openbox", calls)
            clipboard = ROOT / "dotfiles/.local/bin/openbox-clipboard"
            subprocess.run(["/bin/sh", str(clipboard)], env=env, check=True, timeout=3)
            (bin_dir / "clipmenu").unlink()
            (bin_dir / "clipmenud").unlink()
            for _ in range(2):
                subprocess.run(["/bin/sh", str(ROOT / "dotfiles/.config/awesome/autostart")],
                               env=env, capture_output=True, check=True, timeout=10)
            missing = subprocess.run(["/bin/sh", str(clipboard)], env=env, capture_output=True, timeout=3)
            self.assertEqual(missing.returncode, 1)
            calls = log.read_text().splitlines()
            self.assertEqual(calls.count("clipmenu"), 1)
            self.assertEqual(calls.count("xfce4-clipman"), 0)
            self.assertEqual(calls.count("xfce4-popup-clipman"), 0)


if __name__ == "__main__":
    unittest.main()
