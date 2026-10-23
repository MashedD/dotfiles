#!/usr/bin/env python3
"""Dependency-free checks for the original Night Circuit wallpaper assets."""
import importlib.util
from pathlib import Path
import struct
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('night_city', ROOT / 'tools/generate-night-city.py')
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


class NightCircuitTests(unittest.TestCase):
    def test_wallpaper_is_deterministic_and_self_contained(self):
        svg = GENERATOR.generate()
        self.assertEqual(svg, GENERATOR.generate())
        root = ET.fromstring(svg)
        self.assertEqual(root.attrib['viewBox'], '0 0 3840 2160')
        # No fonts, linked images, script, animation, or expensive SVG filters.
        forbidden = {'text', 'image', 'script', 'filter', 'animate', 'foreignObject'}
        self.assertFalse({node.tag.rsplit('}', 1)[-1] for node in root.iter()} & forbidden)
        self.assertNotIn('href=', svg)
        self.assertLess(len(svg), 2_000_000)

    def test_bundled_raster_is_a_4k_png(self):
        png = (ROOT / 'dotfiles/.local/share/wallpapers/night-circuit.png').read_bytes()
        self.assertEqual(png[:8], b'\x89PNG\r\n\x1a\n')
        self.assertEqual(png[12:16], b'IHDR')
        self.assertEqual(struct.unpack('>II', png[16:24]), (3840, 2160))
        self.assertLess(len(png), 5_000_000)


if __name__ == '__main__':
    unittest.main()
