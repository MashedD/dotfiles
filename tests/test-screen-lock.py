#!/usr/bin/env python3
"""Verify secure image cleanup, lock fallback, inherited sleep FD and deduplication."""
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

HELPER = Path(__file__).resolve().parents[1] / "dotfiles/.local/bin/openbox-lock"


class LockTest(unittest.TestCase):
    def test_foreground_lock_and_color_fallback(self):
        for conversion_ok in (True, False):
            with self.subTest(conversion_ok=conversion_ok), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                bin_dir = root / "bin"
                bin_dir.mkdir()
                assets = root / ".local/share/wallpapers"
                assets.mkdir(parents=True)
                (assets / "aurora-longhorn.png").write_bytes(b"mock image")
                commands = {
                    "xdpyinfo": '#!/bin/sh\necho "  dimensions:  1280x800 pixels"\n',
                    "magick": ('#!/bin/sh\nprintf "%s\\n" "$@" > "$TEST_MAGICK_LOG"\nfor last; do :; done\necho mock > "$last"\n'
                               if conversion_ok else '#!/bin/sh\nprintf "%s\\n" "$@" > "$TEST_MAGICK_LOG"\nexit 1\n'),
                    "i3lock": '''#!/bin/sh
printf '%s\\n' "$*" >> "$TEST_LOG"
[ -e "/proc/$$/fd/$XSS_SLEEP_LOCK_FD" ] && echo inherited > "$TEST_FD_LOG"
sleep 1
''',
                }
                for name, source in commands.items():
                    executable = bin_dir / name
                    executable.write_text(source)
                    executable.chmod(0o755)
                with (root / "sleep-fd").open("w") as descriptor:
                    env = dict(os.environ, HOME=str(root), XDG_RUNTIME_DIR=str(root),
                               XDG_STATE_HOME=str(root / ".local/state"),
                               PATH=f"{bin_dir}:{os.environ['PATH']}", TEST_LOG=str(root / "calls"),
                               TEST_MAGICK_LOG=str(root / "magick-args"),
                               TEST_FD_LOG=str(root / "fd-result"), XSS_SLEEP_LOCK_FD=str(descriptor.fileno()))
                    first = subprocess.Popen(["sh", str(HELPER)], env=env, pass_fds=(descriptor.fileno(),))
                    try:
                        deadline = time.monotonic() + 3
                        while not (root / "calls").exists() and time.monotonic() < deadline:
                            time.sleep(0.02)
                        self.assertTrue((root / "calls").exists())
                        self.assertIsNone(first.poll(), "locker was backgrounded")
                        second = subprocess.run(["sh", str(HELPER)], env=env, timeout=2)
                        self.assertEqual(second.returncode, 0)
                        self.assertEqual(first.wait(timeout=3), 0)
                        calls = (root / "calls").read_text().splitlines()
                        self.assertEqual(len(calls), 1)
                        self.assertIn("--nofork", calls[0])
                        self.assertIn("-i " if conversion_ok else "--color=008080", calls[0])
                        magick_args = (root / "magick-args").read_text().splitlines()
                        self.assertEqual(magick_args[0], str(assets / "aurora-longhorn.png"))
                        self.assertEqual((root / "fd-result").read_text().strip(), "inherited")
                        self.assertEqual(list(root.glob("i3lock-bg.*.png")), [])
                    finally:
                        if first.poll() is None:
                            first.terminate()
                            first.wait(timeout=3)


if __name__ == "__main__":
    unittest.main()
