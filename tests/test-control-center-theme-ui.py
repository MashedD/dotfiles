"""Theme selector UI round trips on Xvfb; all service operations are stubbed."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CONTROL_CENTER = ROOT / 'dotfiles/.local/bin/desktop-control-center'


class ThemeUITests(unittest.TestCase):
    def test_select_apply_revert_and_switch_back(self):
        with tempfile.TemporaryDirectory(prefix='theme-selector-ui-') as temp:
            home = Path(temp)
            env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'),
                       XDG_DATA_HOME=str(home / '.local/share'),
                       XDG_STATE_HOME=str(home / '.local/state'), PYTHONDONTWRITEBYTECODE='1',
                       NO_AT_BRIDGE='1')
            program = r'''
from pathlib import Path
from unittest.mock import Mock
namespace = {"__name__": "theme_ui_test", "__file__": CONTROL_CENTER}
exec(compile(Path(CONTROL_CENTER).read_text(), CONTROL_CENTER, "exec"), namespace)
Gtk = namespace["Gtk"]
Gtk.init([])
for version in (3, 4):
    asset = namespace["DATA_HOME"] / f"desktop-themes/night-circuit/gtk-{version}.0.css"
    asset.parent.mkdir(parents=True, exist_ok=True)
    asset.write_text("/* fixture */")
for name in ("aurora-cabin", "night-circuit"):
    asset = namespace["DATA_HOME"] / f"wallpapers/{name}.png"
    asset.parent.mkdir(parents=True, exist_ok=True)
    asset.write_bytes(b"fixture")
backend = namespace["apply_profile"]
prefs = Mock()
prefs.snapshot.return_value = {}
def apply(profile, settings, **paths):
    backend(profile, settings, **paths, restart=Mock(), preferences=prefs)
namespace["apply_profile"] = apply
window = namespace["ControlCenter"]()
window.show_all()
window.notebook.set_current_page(1)
restarts = []
window._request_awesome_restart = lambda message: restarts.append(message)
assert window.desktop_theme.get_active_id() == "aero"
window.desktop_theme.set_active_id("night-circuit")
assert window.widgets["Net/ThemeName"].get_active_id() == "Adwaita-dark"
assert not window.widgets["Gtk/EnableAnimations"].get_active()
assert "Desktop/Profile" not in window._collect_settings()
window._apply()
assert window.desktop_profile == "night-circuit"
assert len(restarts) == 1
assert (namespace["STATE_HOME"] / "awesome/theme").read_text() == "night-circuit\n"
assert "@import" in (namespace["CONFIG_HOME"] / "gtk-3.0/gtk.css").read_text()
window.desktop_theme.set_active_id("aero")
window._revert()
assert window.desktop_theme.get_active_id() == "night-circuit"
assert window.widgets["Net/ThemeName"].get_active_id() == "Adwaita-dark"
window.desktop_theme.set_active_id("aero")
assert window.widgets["Net/ThemeName"].get_active_id() == "Adwaita"
assert window.widgets["Gtk/EnableAnimations"].get_active()
window._apply()
assert window.desktop_profile == "aero"
assert len(restarts) == 2
assert "@import" not in (namespace["CONFIG_HOME"] / "gtk-3.0/gtk.css").read_text()
window.widgets["Gtk/FontName"].set_font_name("DejaVu Sans 11")
window._apply()
assert len(restarts) == 2  # Ordinary GTK edits do not restart Awesome.
assert "DejaVu Sans 11" in namespace["GTK_SETTINGS_PATH"].read_text()
window.destroy()
'''
            result = subprocess.run(['xvfb-run', '-a', sys.executable, '-c',
                                     f'CONTROL_CENTER={str(CONTROL_CENTER)!r}\n' + program],
                                    env=env, text=True, capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
