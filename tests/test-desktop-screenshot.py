#!/usr/bin/env python3
"""Exercise region screenshots with mocked capture and clipboard commands."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "dotfiles/.local/bin/desktop-screenshot"
PNG = b"\x89PNG\r\nfixture"


class DesktopScreenshotTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.bin = self.home / "bin"
        self.bin.mkdir()
        self.destination = self.home / "screenshots"
        self.maim_args = self.home / "maim-args"
        self.xclip_args = self.home / "xclip-args"
        self.clipboard = self.home / "clipboard.png"
        self.command("maim", '''import os, sys
from pathlib import Path
Path(os.environ["MAIM_ARGS"]).write_text(json_args(sys.argv[1:]))
if os.environ.get("MAIM_FAIL") == "1":
    raise SystemExit(1)
sys.stdout.buffer.write(b"\\x89PNG\\r\\nfixture")
''')
        self.command("xclip", '''import os, sys
from pathlib import Path
Path(os.environ["XCLIP_ARGS"]).write_text(json_args(sys.argv[1:]))
Path(os.environ["CLIPBOARD"]).write_bytes(sys.stdin.buffer.read())
''')
        env_path = f"{self.bin}:{os.environ['PATH']}"
        self.env = dict(os.environ, HOME=str(self.home), PATH=env_path,
                        DESKTOP_SCREENSHOT_DIR=str(self.destination),
                        MAIM_ARGS=str(self.maim_args), XCLIP_ARGS=str(self.xclip_args),
                        CLIPBOARD=str(self.clipboard))

    def command(self, name, body):
        path = self.bin / name
        path.write_text("#!/usr/bin/env python3\nimport json\ndef json_args(args): return json.dumps(args)\n" + body)
        path.chmod(0o755)

    def invoke(self):
        return subprocess.run([str(HELPER), "region"], env=self.env,
                              text=True, capture_output=True, timeout=10)

    def test_region_uses_noopengl_and_publishes_screenshot(self):
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.maim_args.read_text()), ["-s", "--noopengl"])
        self.assertEqual(json.loads(self.xclip_args.read_text()),
                         ["-selection", "clipboard", "-t", "image/png"])
        self.assertEqual(self.clipboard.read_bytes(), PNG)
        screenshot = Path(result.stdout.strip())
        self.assertEqual(screenshot.parent, self.destination)
        self.assertEqual(screenshot.read_bytes(), PNG)
        self.assertEqual(list(self.destination.iterdir()), [screenshot])

    def test_cancelled_region_cleans_up_without_publishing(self):
        self.env["MAIM_FAIL"] = "1"
        result = self.invoke()
        self.assertEqual(result.returncode, 1)
        self.assertIn("cancelled or failed", result.stderr)
        self.assertFalse(self.xclip_args.exists())
        self.assertEqual(list(self.destination.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
