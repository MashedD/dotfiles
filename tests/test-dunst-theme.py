"""Static checks for the Dunst palette and preserved notification behavior."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / 'dotfiles/.config/dunst/dunstrc'


def parse_dunstrc(path):
    sections = {}
    current = None
    for number, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('[') and line.endswith(']'):
            current = line[1:-1]
            if current in sections:
                raise AssertionError(f'duplicate section {current!r} on line {number}')
            sections[current] = {}
            continue
        if current is None or '=' not in line:
            raise AssertionError(f'unexpected Dunst syntax on line {number}: {line!r}')
        key, value = (part.strip() for part in line.split('=', 1))
        if key in sections[current]:
            raise AssertionError(f'duplicate option {key!r} in [{current}]')
        sections[current][key] = value.strip('"')
    return sections


class DunstThemeTests(unittest.TestCase):
    def setUp(self):
        self.sections = parse_dunstrc(CONFIG)
        self.global_options = self.sections['global']

    def test_aero_palette_and_urgency_accents(self):
        expected = {
            'urgency_low': dict(background='#183d5b', foreground='#b8c5d6',
                                frame_color='#536a82', highlight='#9cddd4', timeout='8'),
            'urgency_normal': dict(background='#183d5b', foreground='#e0e8f2',
                                   frame_color='#73a7c5', highlight='#a8f0bd', timeout='10'),
            'urgency_critical': dict(background='#183d5b', foreground='#f2fffb',
                                     frame_color='#ff8e89', highlight='#ff8e89', timeout='0'),
        }
        for section, options in expected.items():
            with self.subTest(section=section):
                for key, value in options.items():
                    self.assertEqual(self.sections[section][key], value)
        self.assertEqual(self.global_options['separator_color'], '#527b96')
        self.assertEqual(self.global_options['frame_color'], '#73a7c5')
        self.assertNotIn('#ffffe1', CONFIG.read_text())

    def test_shape_font_geometry_and_actions_are_preserved(self):
        expected = {
            'width': '360', 'height': '(0, 220)', 'origin': 'top-right',
            'offset': '(10, 40)', 'notification_limit': '5',
            'font': 'Microsoft Sans Serif 8', 'frame_width': '2',
            'separator_height': '1', 'corner_radius': '0',
            'progress_bar_height': '10', 'progress_bar_frame_width': '1',
            'progress_bar_corner_radius': '0', 'icon_position': 'left',
            'min_icon_size': '16', 'max_icon_size': '32',
            'mouse_left_click': 'close_current',
            'mouse_middle_click': 'do_action, close_current',
            'mouse_right_click': 'close_all',
        }
        for key, value in expected.items():
            with self.subTest(key=key):
                self.assertEqual(self.global_options[key], value)
        self.assertNotIn('transparency', self.global_options)
        self.assertNotIn('opacity', self.global_options)
        self.assertIn('Awesome desktop', CONFIG.read_text())
        self.assertNotIn('Openbox', CONFIG.read_text())

    def test_project_guidance_matches_selected_direction(self):
        guidance = (ROOT / 'AGENTS.md').read_text()
        self.assertIn('opaque, square-edged Aero-blue notifications', guidance)
        self.assertNotIn('background `#ffffe1`', guidance)


if __name__ == '__main__':
    unittest.main()
