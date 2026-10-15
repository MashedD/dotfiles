"""Isolated read-only desktop health checker tests with no host dependencies."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CHECK = ROOT / 'dotfiles/.local/bin/desktop-check'


class HealthCheckTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        self.config = self.home / 'config'
        self.data = self.home / 'data'
        self.helpers = self.home / 'helpers'
        self.env = dict(HOME=str(self.home), PATH=str(self.bin), XDG_CONFIG_HOME=str(self.config),
                        XDG_DATA_HOME=str(self.data), DESKTOP_HELPER_ROOT=str(self.helpers))
        source = CHECK.read_text()
        for group in ['required_commands', 'optional_commands']:
            commands = re.search(rf"^{group}='([^']+)'", source, re.M).group(1).split()
            for name in commands:
                self.command(name)
        self.command('clipmenu')
        self.command('clipmenud')
        for name in ['awesome/rc.lua', 'awesome/panel.lua', 'awesome/autostart',
                     'picom/picom.conf', 'X11/xinitrc']:
            self.file(self.config / name)
        for name in ['aurora-longhorn.png', 'win98-teal.svg']:
            self.file(self.home / '.local/share/wallpapers' / name)
        for name in ['icons/hicolor/32x32/apps/vax-tux-start.png',
                     'icons/hicolor/32x32/apps/vax-tux-start.png.vax-generated',
                     'themes/VAX/gtk-2.0/gtkrc', 'themes/VAX/gtk-3.0/gtk.css',
                     'themes/VAX/index.theme', 'icons/Chicago95/index.theme',
                     'icons/Chicago95_Standard_Cursors/index.theme']:
            self.file(self.data / name)
        chicago = self.home / 'Chicago95 source with spaces'
        for name in ['index.theme', 'gtk-2.0/gtkrc', 'gtk-3.0/gtk.css',
                     'gtk-2.0/panel/panel-button.png', 'gtk-2.0/panel/panel-button-active.png',
                     'misc/GTK2_start_buttons/tux_30px.png']:
            self.file(chicago / name)
        self.file(self.data / 'themes/VAX/.vax-generated', f'chicago95={chicago}\n')
        for name in ['lock', 'display', 'screenshot', 'battery-watch', 'brightness', 'clipboard', 'volume']:
            path = self.helpers / f'desktop-{name}'
            self.file(path, '#!/bin/sh\nexit 99\n')  # Must only inspect, never execute.
            path.chmod(0o755)

    def file(self, path, text='fixture'):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def command(self, name):
        path = self.bin / name
        path.write_text('''#!/bin/sh
name=${0##*/}
case "$name" in
  awesome|picom)
    if [ "${FAILED_VALIDATOR:-}" = "$name" ]; then
      if [ "${EMPTY_OUTPUT:-}" != yes ]; then
        echo 'validator stdout detail'
        echo 'validator stderr detail' >&2
      fi
      exit 7
    fi
    echo "$name successful diagnostic"
    ;;
  fc-match)
    if [ "${FONT_ERROR:-}" = yes ]; then echo 'font error detail' >&2; exit 8; fi
    for arg; do :; done
    if [ "$arg" = 'Microsoft Sans Serif' ]; then
      echo "${MATCH_FONT:-Microsoft Sans Serif}"
    else
      echo "${NERD_FONT:-FiraCode Nerd Font}"
    fi
    ;;
esac
''')
        path.chmod(0o755)

    def invoke(self, *args):
        return subprocess.run(['/bin/sh', str(CHECK), *args], env=self.env,
                              text=True, capture_output=True, timeout=5)

    def snapshot(self):
        return {str(path.relative_to(self.home)): (path.read_bytes(), path.stat().st_mode)
                for path in self.home.rglob('*') if path.is_file()}

    def test_quiet_and_verbose_success_are_read_only(self):
        before = self.snapshot()
        quiet = self.invoke()
        self.assertEqual(quiet.returncode, 0, quiet.stdout + quiet.stderr)
        self.assertNotIn('OK ', quiet.stdout)
        self.assertNotIn('successful diagnostic', quiet.stdout)
        self.assertIn('0 required failure(s), 0 warning(s)', quiet.stdout)
        self.assertEqual(len(quiet.stdout.splitlines()), 2)
        verbose = self.invoke('--verbose')
        self.assertEqual(verbose.returncode, 0)
        self.assertIn('OK ', verbose.stdout)
        self.assertIn('awesome successful diagnostic', verbose.stdout)
        self.assertIn('picom successful diagnostic', verbose.stdout)
        self.assertEqual(self.snapshot(), before)

    def test_missing_required_command_and_file(self):
        (self.bin / 'awesome').unlink()
        (self.config / 'awesome/panel.lua').unlink()
        result = self.invoke()
        self.assertEqual(result.returncode, 1)
        self.assertIn('required command: awesome', result.stdout)
        self.assertIn('awesome/panel.lua', result.stdout)
        self.assertIn('2 required failure(s)', result.stdout)
        self.assertNotIn('not found', result.stderr)

    def test_optional_warnings_and_disabled_clipboard(self):
        (self.bin / 'firefox').unlink()
        (self.bin / 'clipmenud').unlink()
        result = self.invoke()
        self.assertEqual(result.returncode, 0)
        self.assertIn('optional command: firefox', result.stdout)
        self.assertIn('Clipman is deliberately disabled', result.stdout)
        self.assertIn('0 required failure(s), 2 warning(s)', result.stdout)

    def test_font_fallback_missing_font_and_probe_failure(self):
        self.env['MATCH_FONT'] = 'Liberation Sans'
        result = self.invoke()
        self.assertEqual(result.returncode, 0)
        self.assertIn('font fallback', result.stdout)
        self.env['NERD_FONT'] = 'Other Font'
        self.assertEqual(self.invoke().returncode, 1)
        self.env['FONT_ERROR'] = 'yes'
        result = self.invoke()
        self.assertEqual(result.returncode, 1)
        self.assertIn('exit 8', result.stdout)
        self.assertIn('font error detail', result.stdout)
        (self.bin / 'fc-match').unlink()
        result = self.invoke()
        self.assertEqual(result.returncode, 1)
        self.assertNotIn('font probe', result.stdout)
        self.assertEqual(result.stderr, '')

    def test_validator_failure_keeps_stdout_stderr_status_and_command(self):
        for name in ['awesome', 'picom']:
            with self.subTest(name=name):
                self.env['FAILED_VALIDATOR'] = name
                result = self.invoke()
                self.assertEqual(result.returncode, 1)
                for detail in [f'validator: {name}', 'exit 7', 'validator stdout detail', 'validator stderr detail']:
                    self.assertIn(detail, result.stdout)
                self.env['EMPTY_OUTPUT'] = 'yes'
                result = self.invoke()
                self.assertIn('No diagnostic output was produced.', result.stdout)
                del self.env['EMPTY_OUTPUT']
        (self.bin / 'picom').unlink()
        result = self.invoke()
        self.assertNotIn('validator: picom', result.stdout)
        self.assertIn('required command: picom', result.stdout)

    def test_help_and_bad_options(self):
        self.assertEqual(self.invoke('--help').returncode, 0)
        for args in [('--unknown',), ('--verbose', 'extra'), ('--help', 'extra')]:
            with self.subTest(args=args):
                self.assertEqual(self.invoke(*args).returncode, 64)


if __name__ == '__main__':
    unittest.main()
