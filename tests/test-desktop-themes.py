"""Desktop profile transactions and Lua selection; no real services are touched."""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'dotfiles/.local/lib'))
sys.dont_write_bytecode = True
from desktop_control_center import themes, settings


class Preferences:
    def __init__(self):
        self.values = {'color-scheme': "'default'", 'gtk-theme': "'Adwaita'"}
        self.fail = False

    def snapshot(self):
        return dict(self.values)

    def apply(self, profile, _settings, _previous):
        self.values['color-scheme'] = profile
        if self.fail:
            raise RuntimeError('preference failure')

    def restore(self, previous):
        self.values = previous


class DesktopThemeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='desktop-theme-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config, self.data, self.state = [self.root / name for name in ('config', 'data assets', 'state')]
        self.prefs, self.restart = Preferences(), Mock()
        for version in (3, 4):
            css = self.data / f'desktop-themes/night-circuit/gtk-{version}.0.css'
            css.parent.mkdir(parents=True, exist_ok=True)
            css.write_text('/* bundled theme */')
            path = self.config / f'gtk-{version}.0/gtk.css'
            path.parent.mkdir(parents=True)
            path.write_text('/* personal */\n.my-widget { color: red; }\n')
        for name in ('aurora-cabin', 'night-circuit'):
            path = self.data / f'wallpapers/{name}.png'
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'fixture')
        self.source = self.root / 'stowed-xsettings.conf'
        self.source.write_text('# preserve\nNet/ThemeName "Adwaita"\n')
        xsettings = self.config / 'xsettingsd/xsettingsd.conf'
        xsettings.parent.mkdir()
        xsettings.symlink_to(self.source)
        (self.config / 'gtk-4.0/settings.ini').write_text('[Settings]\ncustom-option=keep\n[Other]\nkeep=yes\n')

    def apply(self, profile, values=None):
        themes.apply_profile(profile, values or themes.profile_settings(profile, settings.DEFAULTS),
                             config_home=self.config, data_home=self.data, state_home=self.state,
                             restart=self.restart, preferences=self.prefs)

    def snapshot(self):
        return {str(p.relative_to(self.root)): p.read_bytes()
                for p in self.root.rglob('*') if p.is_file()}

    def test_round_trip_restores_both_wallpapers_and_preserves_custom_css(self):
        old = self.root / 'personal wallpaper.png'
        old.write_bytes(b'old')
        custom_night = self.root / 'custom night.png'
        custom_night.write_bytes(b'night')
        wallpaper = self.state / 'awesome/wallpaper'
        wallpaper.parent.mkdir(parents=True)
        wallpaper.write_text(str(old) + '\n')
        self.apply('night-circuit')
        self.assertEqual(themes.read_profile(self.state), 'night-circuit')
        self.assertIn('night-circuit.png', wallpaper.read_text())
        css = self.config / 'gtk-3.0/gtk.css'
        self.assertIn('data%20assets', css.read_text())
        self.assertEqual(css.read_text().count(themes.BEGIN), 1)
        self.assertTrue(css.read_text().endswith('.my-widget { color: red; }\n'))
        self.assertTrue((self.config / 'xsettingsd/xsettingsd.conf').is_symlink())
        wallpaper.write_text(str(custom_night) + '\n')
        self.apply('aero')
        self.assertEqual(wallpaper.read_text().strip(), str(old))
        self.assertEqual(css.read_text(), '/* personal */\n.my-widget { color: red; }\n')
        self.assertIn('gtk-application-prefer-dark-theme=false',
                      (self.config / 'gtk-4.0/settings.ini').read_text())
        self.apply('night-circuit')
        self.assertEqual(wallpaper.read_text().strip(), str(custom_night))
        gtk4 = (self.config / 'gtk-4.0/settings.ini').read_text()
        self.assertIn('custom-option=keep', gtk4)
        self.assertIn('[Other]\nkeep=yes', gtk4)
        self.assertIn('gtk-application-prefer-dark-theme=true', gtk4)

    def test_same_profile_keeps_wallpaper_and_advanced_gtk_preferences(self):
        self.apply('night-circuit')
        wallpaper = self.state / 'awesome/wallpaper'
        wallpaper.write_text('/custom/keep.png\n')
        values = themes.profile_settings('night-circuit', settings.DEFAULTS)
        values['Gtk/FontName'] = 'DejaVu Sans 11'
        values['Net/ThemeName'] = 'Other'
        self.apply('night-circuit', values)
        self.assertEqual(wallpaper.read_text(), '/custom/keep.png\n')
        self.assertIn('gtk-font-name=DejaVu Sans 11', (self.config / 'gtk-3.0/settings.ini').read_text())
        self.assertIn('Net/ThemeName "Other"', self.source.read_text())
        self.assertEqual((self.config / 'gtk-3.0/gtk.css').read_text().count(themes.BEGIN), 1)

    def test_restart_failure_rolls_back_all_files_and_preserves_links(self):
        before = self.snapshot()
        self.restart.side_effect = [RuntimeError('restart failed'), None, None]
        with self.assertRaisesRegex(RuntimeError, 'restart failed'):
            self.apply('night-circuit')
        self.assertEqual(self.snapshot(), before)
        self.assertTrue((self.config / 'xsettingsd/xsettingsd.conf').is_symlink())

    def test_partial_preferences_failure_rolls_back_files_and_preferences(self):
        before = self.snapshot()
        preferences = self.prefs.snapshot()
        self.prefs.fail = True
        with self.assertRaisesRegex(RuntimeError, 'preference failure'):
            self.apply('night-circuit')
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.prefs.values, preferences)

    def test_missing_assets_and_invalid_profiles_are_rejected_before_writing(self):
        (self.data / 'desktop-themes/night-circuit/gtk-4.0.css').unlink()
        before = self.snapshot()
        for name in ('night-circuit', '../unsafe'):
            with self.assertRaises(ValueError):
                self.apply(name)
        self.assertEqual(self.snapshot(), before)
        self.restart.assert_not_called()

    def test_missing_remembered_wallpaper_falls_back_to_bundled_asset(self):
        history = self.state / 'awesome/theme-wallpapers.json'
        history.parent.mkdir(parents=True)
        history.write_text(json.dumps({'night-circuit': '/missing/file.png'}))
        self.apply('night-circuit')
        self.assertEqual((self.state / 'awesome/wallpaper').read_text().strip(),
                         str(self.data / 'wallpapers/night-circuit.png'))

    def test_stylesheet_removes_only_managed_block_and_rejects_malformed_blocks(self):
        original = '.a { color: red; }\n'
        updated = themes.stylesheet(original, self.data / 'a.css')
        self.assertEqual(themes.stylesheet(updated, None), original)
        for value in (themes.BEGIN, themes.END, themes.END + themes.BEGIN,
                      themes.BEGIN + themes.END + themes.BEGIN + themes.END):
            with self.assertRaises(ValueError):
                themes.stylesheet(value, None)

    def test_lua_loader_uses_bundled_profiles_and_safe_fallback(self):
        path = ROOT / 'dotfiles/.config/awesome/appearance.lua'
        code = ('package.preload.gears=function() return {color=function(x) return x end} end; '
                f'local a=dofile({json.dumps(str(path))}); print(a.name, a.cyberpunk)')
        environment = dict(os.environ, HOME=str(self.root), XDG_STATE_HOME=str(self.state))
        def result():
            return subprocess.check_output(['lua', '-e', code], env=environment, text=True).strip()
        self.assertEqual(result(), 'aero\tfalse')
        selection = self.state / 'awesome/theme'
        selection.parent.mkdir(parents=True)
        selection.write_text('night-circuit\n')
        self.assertEqual(result(), 'night-circuit\ttrue')
        selection.write_text('../../etc/passwd\n')
        self.assertEqual(result(), 'aero\tfalse')


if __name__ == '__main__':
    unittest.main()
