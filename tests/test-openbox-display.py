#!/usr/bin/env python3
"""Display-helper regression tests; no real X server or hardware mutations."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HELPER = Path(__file__).resolve().parents[1] / "dotfiles/.local/bin/openbox-display"


class DisplayTests(unittest.TestCase):
    def run_helper(self, mode):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            commands = {
                "xrandr": '''#!/bin/sh
printf '%s\\n' "$*" >> "$TEST_ROOT/calls"
case "$1" in
  --current)
    count=0
    [ ! -f "$TEST_ROOT/count" ] || read -r count < "$TEST_ROOT/count"
    count=$((count + 1))
    printf '%s\\n' "$count" > "$TEST_ROOT/count"
    if [ "$TEST_MODE" = --watch ] && [ "$count" -gt 4 ]; then exit 1; fi
    printf 'eDP connected primary 1920x1080+0+0\\n   1920x1080 60.00*+\\nHDMI-A-1-0 disconnected\\n'
    ;;
  --setprovideroutputsource|--output) exit 0 ;;
  *) exit 99 ;;
esac
''',
                "logger": '#!/bin/sh\nprintf "%s\\n" "$*" >> "$TEST_ROOT/messages"\n',
                "sleep": '#!/bin/sh\nexit 0\n',
            }
            for name, source in commands.items():
                executable = root / name
                executable.write_text(source)
                executable.chmod(0o755)
            env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                       TEST_ROOT=str(root), TEST_MODE=mode,
                       XDG_RUNTIME_DIR=str(root))
            result = subprocess.run(["sh", str(HELPER), mode], env=env,
                                    capture_output=True, text=True, timeout=5)
            return (result, (root / "calls").read_text(),
                    (root / "messages").read_text())

    def test_once_uses_cached_state_and_enables_internal(self):
        result, calls, messages = self.run_helper("--once")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("--query", calls)
        self.assertEqual(calls.count("--current"), 3)
        self.assertIn("--output eDP --primary --auto --pos 0x0", calls)
        self.assertIn("Applied display layout: internal", messages)

    def test_watcher_stops_when_x_server_disappears(self):
        result, calls, messages = self.run_helper("--watch")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertNotIn("--query", calls)
        self.assertIn("stopping display watcher", messages)
        self.assertEqual(calls.count("--output eDP"), 1)


if __name__ == "__main__":
    unittest.main()
