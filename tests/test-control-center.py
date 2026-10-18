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


class SidebarSettingsTests(unittest.TestCase):
    def test_legacy_state_defaults_to_compact_sidebar(self):
        self.assertEqual(settings.parse_sidebar_enabled("order=calendar,todo\ncrypto\n"),
                         set(settings.DEFAULT_SIDEBAR_ENABLED))
        self.assertNotIn("quick-launch", settings.parse_sidebar_enabled(""))

    def test_explicit_sidebar_visibility_including_empty_list(self):
        self.assertEqual(settings.parse_sidebar_enabled("enabled=quick-launch,crypto,unknown\n"),
                         {"quick-launch", "crypto", "news"})
        self.assertEqual(settings.parse_sidebar_enabled("enabled=\n"), {"news"})
        self.assertEqual(settings.parse_sidebar_enabled("version=2\nenabled=\n"), set())

    def test_update_preserves_order_and_collapsed_state(self):
        original = "order=calendar,quick-launch,todo\ncrypto\n"
        updated = settings.update_sidebar_enabled_text(original, {"calendar", "quick-launch"})
        self.assertEqual(updated, "version=2\norder=calendar,quick-launch,todo\nenabled=calendar,quick-launch\ncrypto\n")
        replaced = settings.update_sidebar_enabled_text(
            updated + "enabled=crypto\n", {"weather"})
        self.assertEqual(replaced, "version=2\norder=calendar,quick-launch,todo\nenabled=weather\ncrypto\n")

    def test_unknown_sidebar_sections_rejected(self):
        with self.assertRaisesRegex(settings.SettingsError, "Unknown sidebar section"):
            settings.update_sidebar_enabled_text("", {"not-a-section"})

    def test_sidebar_preferences_round_trip_multiple_folders_and_equals(self):
        preferences = settings.default_sidebar_preferences(Path("/home/test"), Path("/data"))
        preferences.update({
            "weather_label": "Toruń & region",
            "latitude": "53.0138", "longitude": "18.5984",
            "todo_path": "/home/test/Documents/todo=work.md",
            "calendar_path": "/home/test/Notes/calendar.md",
            "wallpaper_dirs": ["/data/wallpapers", "/mnt/pictures/Walls"],
            "editor_command": ["kitty", "mdn-editor", "--", "{file}"],
            "browser_command": ["chromium", "--new-window", "{url}"],
        })
        serialized = settings.serialize_sidebar_preferences(preferences)
        parsed = settings.parse_sidebar_preferences(serialized, settings.default_sidebar_preferences(
            Path("/home/test"), Path("/data")))
        self.assertEqual(parsed["weather_label"], "Toruń & region")
        self.assertEqual(parsed["latitude"], 53.0138)
        self.assertEqual(parsed["todo_path"], "/home/test/Documents/todo=work.md")
        self.assertEqual(parsed["wallpaper_dirs"], ["/data/wallpapers", "/mnt/pictures/Walls"])
        self.assertEqual(parsed["editor_command"], ["kitty", "mdn-editor", "--", "{file}"])
        self.assertEqual(parsed["browser_command"], ["chromium", "--new-window", "{url}"])

    def test_sidebar_preferences_reject_invalid_coordinates_and_control_characters(self):
        defaults = settings.default_sidebar_preferences(Path("/home/test"), Path("/data"))
        invalid = dict(defaults, latitude=float("nan"))
        with self.assertRaisesRegex(settings.SettingsError, "latitude must be between"):
            settings.serialize_sidebar_preferences(invalid)
        invalid = dict(defaults, weather_label="City\nOther")
        with self.assertRaisesRegex(settings.SettingsError, "control character"):
            settings.serialize_sidebar_preferences(invalid)
        with self.assertRaisesRegex(settings.SettingsError, "longitude must be between"):
            settings.parse_sidebar_preferences("version=1\nlongitude=181\n", defaults)


class QuickLaunchSettingsTests(unittest.TestCase):
    def test_default_entries_preserve_current_launcher_set(self):
        config = settings.default_quick_launch_config(Path("/home/test"))
        entries = config["entries"]
        self.assertEqual([entry["label"] for entry in entries], [
            "Terminal", "Files", "Control Panel", "Finder", "Firefox", "Quake 1", "Quake 2", "Sleep",
        ])
        self.assertEqual(entries[2]["argv"], ["/home/test/.local/bin/desktop-control-center"])
        self.assertEqual(entries[5]["argv"], ["/home/test/Games/quake-rerelease/vkquake.sh"])

    def test_command_tokenization_is_quoted_argv_not_a_shell(self):
        self.assertEqual(settings.parse_quick_launch_command(
            'kitty mdn-editor -- "~/Documents/my notes.md"'),
            ["kitty", "mdn-editor", "--", "~/Documents/my notes.md"])
        with self.assertRaisesRegex(settings.SettingsError, "quoting"):
            settings.parse_quick_launch_command('kitty "unterminated')

    def test_config_round_trip_empty_list_and_validation(self):
        entries = settings.default_quick_launch_entries(Path("/home/test"))
        entries.append({"label": "Notes", "icon": "accessories-text-editor",
                        "argv": ["kitty", "mdn-editor", "--", "~/Documents/notes.md"],
                        "enabled": True})
        text = settings.serialize_quick_launch_config(entries)
        parsed = settings.parse_quick_launch_config(text)
        self.assertEqual(parsed["entries"], entries)
        self.assertEqual(settings.parse_quick_launch_config('{"version":1,"entries":[]}')["entries"], [])
        duplicated = [dict(entries[0]), dict(entries[1], label=entries[0]["label"].lower())]
        with self.assertRaisesRegex(settings.SettingsError, "unique"):
            settings.serialize_quick_launch_config(duplicated)
        invalid = [dict(entries[0], enabled=1)]
        with self.assertRaisesRegex(settings.SettingsError, "boolean"):
            settings.serialize_quick_launch_config(invalid)
        with self.assertRaisesRegex(settings.SettingsError, "version"):
            settings.parse_quick_launch_config('{"version":2,"entries":[]}')
        too_many = entries * 4
        with self.assertRaisesRegex(settings.SettingsError, "at most 24"):
            settings.serialize_quick_launch_config(too_many)


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
