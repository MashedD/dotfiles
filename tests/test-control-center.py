"""Pure settings-file tests; never start or restart the live X11 services."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[1]
MODULE_DIR = ROOT / "dotfiles/.local/lib"
sys.path.insert(0, str(MODULE_DIR))
sys.dont_write_bytecode = True
from desktop_control_center import settings  # noqa: E402


class XSettingsFileTests(unittest.TestCase):
    def test_parse_escaped_strings_and_ignore_comments(self):
        parsed = settings.parse_xsettings(
            '# theme\nNet/ThemeName "Adwaita"\n'
            'Gtk/ColorScheme "selected_bg_color:#3584e4\\nselected_fg_color:#ffffff"\n'
            'Xft/Antialias 1 # enabled\n'
        )
        self.assertEqual(parsed["Net/ThemeName"], "Adwaita")
        self.assertEqual(parsed["Gtk/ColorScheme"],
                         "selected_bg_color:#3584e4\nselected_fg_color:#ffffff")
        self.assertEqual(parsed["Xft/Antialias"], 1)

    def test_update_preserves_comments_unknown_keys_and_stow_links(self):
        original = (
            "# keep this comment\n"
            'Net/ThemeName "Old" # retain note\n'
            'Custom/Preference "untouched"\n'
        )
        updated = settings.update_xsettings_text(original, {"Net/ThemeName": "Adwaita Dark"})
        self.assertIn("# keep this comment\n", updated)
        self.assertIn('Net/ThemeName "Adwaita Dark" # retain note\n', updated)
        self.assertIn('Custom/Preference "untouched"\n', updated)

        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "repo.conf"
            source.write_text(original)
            link = root / "config.conf"
            link.symlink_to(source)
            settings.atomic_write(link, updated)
            self.assertTrue(link.is_symlink())
            self.assertEqual(link.read_text(), updated)
            self.assertEqual(source.read_text(), updated)

    def test_settings_merge_prefers_xsettings_over_gtk_ini(self):
        gtk = "[Settings]\ngtk-theme-name=Adwaita\ngtk-icon-theme-name=Breeze\n"
        merged = settings.settings_from_files(
            'Net/ThemeName "Other"\nGtk/ToolbarStyle 1\n', gtk)
        self.assertEqual(merged["Net/ThemeName"], "Other")
        self.assertEqual(merged["Net/IconThemeName"], "Breeze")
        self.assertEqual(merged["Gtk/ToolbarStyle"], 1)

    def test_update_gtk_ini_preserves_other_sections_and_preferences(self):
        original = "# keep\n[Settings]\ngtk-theme-name=Old\ngtk-extra=keep\n[Other]\nvalue=yes\n"
        updated = settings.update_gtk_settings_text(original, settings.DEFAULTS)
        self.assertTrue(updated.startswith("# keep\n[Settings]\n"))
        self.assertIn("gtk-theme-name=Adwaita\n", updated)
        self.assertIn("gtk-extra=keep\n", updated)
        self.assertIn("[Other]\nvalue=yes\n", updated)
        self.assertIn("gtk-toolbar-style=GTK_TOOLBAR_BOTH_HORIZ\n", updated)
        self.assertIn("gtk-xft-rgba=rgb\n", updated)

    def test_invalid_settings_rejected(self):
        with self.assertRaisesRegex(settings.SettingsError, "between 0 and 128"):
            settings.update_xsettings_text("", {"Gtk/CursorThemeSize": 129})
        with self.assertRaisesRegex(settings.SettingsError, "Unsupported setting"):
            settings.update_xsettings_text("", {"Desktop/Unknown": 1})


class ApplyTests(unittest.TestCase):
    def test_apply_writes_both_files_then_restarts(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            xsettings = root / "xsettingsd.conf"
            gtk = root / "gtk-3.0/settings.ini"
            xsettings.write_text('# preserve\nNet/ThemeName "Adwaita"\n')
            gtk.parent.mkdir()
            gtk.write_text("[Settings]\ngtk-theme-name=Adwaita\nkeep=yes\n")
            restart = Mock()
            settings.apply_settings(xsettings, gtk, settings.DEFAULTS, restart=restart)
            restart.assert_called_once_with(xsettings)
            self.assertIn('Net/ThemeName "Adwaita"', xsettings.read_text())
            self.assertIn("gtk-theme-name=Adwaita\n", gtk.read_text())
            self.assertIn("keep=yes\n", gtk.read_text())

    def test_restart_failure_rolls_back_both_files_and_restarts_old_values(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            xsettings = root / "xsettingsd.conf"
            gtk = root / "settings.ini"
            original_x = 'Net/ThemeName "Adwaita"\n'
            original_gtk = "[Settings]\ngtk-theme-name=Adwaita\n"
            xsettings.write_text(original_x)
            gtk.write_text(original_gtk)
            restart = Mock(side_effect=[RuntimeError("test restart failure"), None])
            with self.assertRaisesRegex(settings.SettingsError, "Could not apply settings"):
                settings.apply_settings(xsettings, gtk, {**settings.DEFAULTS,
                                          "Net/ThemeName": "Other"}, restart=restart)
            self.assertEqual(xsettings.read_text(), original_x)
            self.assertEqual(gtk.read_text(), original_gtk)
            self.assertEqual(restart.call_count, 2)

    def test_failed_first_apply_removes_created_files_on_rollback(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            xsettings = root / "xsettingsd.conf"
            gtk = root / "gtk/settings.ini"
            restart = Mock(side_effect=[RuntimeError("startup failed"), None])
            with self.assertRaises(settings.SettingsError):
                settings.apply_settings(xsettings, gtk, settings.DEFAULTS, restart=restart)
            self.assertFalse(xsettings.exists())
            self.assertFalse(gtk.exists())


if __name__ == "__main__":
    unittest.main()
