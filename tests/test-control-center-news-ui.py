#!/usr/bin/env python3
"""Exercise the News editor on private Xvfb with isolated XDG paths."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CONTROL_CENTER = ROOT / "dotfiles/.local/bin/desktop-control-center"


@unittest.skipUnless(shutil.which("xvfb-run"), "xvfb-run is required for GTK UI checks")
class NewsEditorUITests(unittest.TestCase):
    def test_empty_startup_edit_save_reload_and_category_delete_guard(self):
        with tempfile.TemporaryDirectory(prefix="control-center-news-test-") as temp:
            root = Path(temp)
            environment = dict(os.environ)
            environment.update({
                "HOME": str(root),
                "XDG_CONFIG_HOME": str(root / ".config"),
                "XDG_STATE_HOME": str(root / ".local/state"),
                "PYTHONDONTWRITEBYTECODE": "1",
            })
            program = r'''
import json
from pathlib import Path
from types import SimpleNamespace
path = Path(CONTROL_CENTER).resolve()
namespace = {"__name__": "control_center_test", "__file__": str(path)}
exec(compile(path.read_text(encoding="utf-8"), str(path), "exec"), namespace)
module = SimpleNamespace(**namespace)
module.Gtk.init([])
window = module.ControlCenter()
assert window.notebook.get_n_pages() == 4
assert window.sidebar_widgets["news"].get_active()
assert window.news_config == {"version": 1, "categories": [], "feeds": []}
window.sidebar_widgets["news"].set_active(False)
window.sidebar_preference_widgets["weather_label"].set_text("Toruń & region")
window.sidebar_preference_widgets["latitude"].set_text("53.0138")
window.sidebar_preference_widgets["longitude"].set_text("18.5984")
window.sidebar_preference_widgets["todo_path"].set_text("~/Documents/todo=work.md")
window.sidebar_preference_widgets["calendar_path"].set_text("~/Notes/calendar.md")
window.wallpaper_directory_rows[0]["entry"].set_text("~/Pictures/Custom A")
window._remove_wallpaper_directory(None, window.wallpaper_directory_rows[1])
window._add_wallpaper_directory_row("/mnt/Wallpapers")
assert window._save_sidebar_settings()
preferences = module.parse_sidebar_preferences(
    module.SIDEBAR_PREFERENCES_PATH.read_text(encoding="utf-8"),
    module.default_sidebar_preferences(module.HOME, module.DATA_HOME))
assert preferences["weather_label"] == "Toruń & region"
assert preferences["todo_path"] == "~/Documents/todo=work.md"
assert preferences["wallpaper_dirs"] == ["~/Pictures/Custom A", "/mnt/Wallpapers"]
window.sidebar_preference_widgets["latitude"].set_text("999")
assert not window._save_sidebar_settings()
window._reload_sidebar_settings()
assert window.sidebar_preference_widgets["weather_label"].get_text() == "Toruń & region"
assert len(window.wallpaper_directory_rows) == 2
window.notebook.set_current_page(1)
window._revert()
window.notebook.set_current_page(2)
state = module.SIDEBAR_SECTIONS_PATH.read_text(encoding="utf-8")
assert state.startswith("version=2\n") and "news" not in state.split("enabled=", 1)[1].splitlines()[0]
window._reload_sidebar_settings()
assert not window.sidebar_widgets["news"].get_active()
window._add_news_category(label="Local News")
category = window.news_category_rows[0]
window._add_news_feed(feed={"id": "0123456789abcdef", "category": category["id"],
    "label": "Fixture", "url": "https://example.test/rss", "enabled": True})
window._remove_news_category(None, category)
assert "Reassign or remove" in window.status.get_text()
assert len(window.news_category_rows) == 1
assert window._save_news_settings()
saved = json.loads(module.NEWS_CONFIG_PATH.read_text(encoding="utf-8"))
assert saved["categories"][0]["label"] == "Local News"
assert saved["feeds"][0]["category"] == category["id"]
window.news_feed_rows[0]["url"].set_text("file:///etc/passwd")
assert not window._save_news_settings()
assert json.loads(module.NEWS_CONFIG_PATH.read_text(encoding="utf-8")) == saved
window._reload_news_settings()
assert len(window.news_category_rows) == 1 and len(window.news_feed_rows) == 1
window._remove_news_feed(None, window.news_feed_rows[0])
window._remove_news_category(None, window.news_category_rows[0])
assert window._save_news_settings()
assert json.loads(module.NEWS_CONFIG_PATH.read_text(encoding="utf-8")) == {
    "version": 1, "categories": [], "feeds": []}
'''.replace("CONTROL_CENTER", repr(str(CONTROL_CENTER)))
            result = subprocess.run(
                ["xvfb-run", "-a", sys.executable, "-c", program], cwd=ROOT,
                env=environment, text=True, capture_output=True, timeout=30,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
