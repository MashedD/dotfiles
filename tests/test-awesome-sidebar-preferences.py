#!/usr/bin/env python3
"""Exercise Awesome's user sidebar-preferences reader with isolated XDG paths."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PREFERENCES = ROOT / "dotfiles/.config/awesome/sidebar-preferences.lua"


class SidebarPreferenceReaderTests(unittest.TestCase):
    def test_custom_locations_multiple_wallpaper_directories_and_defaults(self):
        with tempfile.TemporaryDirectory(prefix="awesome-sidebar-preferences-") as temp:
            home = Path(temp)
            config_home = home / ".config"
            settings = config_home / "desktop-control-center/sidebar-preferences"
            settings.parent.mkdir(parents=True)
            settings.write_text(
                "version=1\nweather_label=Barcelona, Spain\nlatitude=41.4034\nlongitude=2.174\n"
                "todo_path=~/Notes/todo.md\ncalendar_path=notes/calendar.md\n"
                "wallpaper_dirs=~/Pictures/One\nwallpaper_dirs=/mnt/Wallpapers\n",
                encoding="utf-8",
            )
            script = f'''local p=dofile({str(PREFERENCES)!r}).load()
assert(p.weather_label == "Barcelona, Spain")
assert(p.latitude == 41.4034 and p.longitude == 2.174)
assert(p.todo_path == {str(home / "Notes/todo.md")!r})
assert(p.calendar_path == {str(home / "notes/calendar.md")!r})
assert(#p.wallpaper_dirs == 2 and p.wallpaper_dirs[1] == {str(home / "Pictures/One")!r}
    and p.wallpaper_dirs[2] == "/mnt/Wallpapers")
'''
            environment = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(config_home),
                               XDG_DATA_HOME=str(home / ".local/share"))
            subprocess.run(["lua", "-e", script], cwd=ROOT, env=environment,
                           check=True, timeout=10)
            settings.write_text("latitude=1000\nwallpaper_dirs=\n", encoding="utf-8")
            defaults = f'''local p=dofile({str(PREFERENCES)!r}).load()
assert(p.weather_label == "Bydgoszcz, Poland" and p.latitude == 53.1235 and p.longitude == 17.9871)
assert(#p.wallpaper_dirs == 0 and p.todo_path == {str(home / "Documents/todo.md")!r})
'''
            subprocess.run(["lua", "-e", defaults], cwd=ROOT, env=environment,
                           check=True, timeout=10)


if __name__ == "__main__":
    unittest.main()
