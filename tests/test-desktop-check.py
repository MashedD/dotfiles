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
        self.command('id')
        for name in ['awesome/rc.lua', 'awesome/panel.lua', 'awesome/autostart',
                     'picom/picom.conf', 'X11/xinitrc']:
            self.file(self.config / name)
        self.file(self.config / 'xsettingsd/xsettingsd.conf',
                  'Net/ThemeName "Adwaita"\nNet/IconThemeName "Breeze"\nGtk/CursorThemeName "Adwaita"\nGtk/ColorScheme "selected_bg_color:#3584e4\\nselected_fg_color:#ffffff"\n')
        self.file(self.config / 'xdg-terminals.list', 'kitty.desktop\n')
        for name in ['aurora-cabin.png']:
            self.file(self.home / '.local/share/wallpapers' / name)
        self.file(self.data / 'icons/hicolor/32x32/apps/tux-start.png')
        self.file(self.data / 'applications/desktop-control-center.desktop')
        self.file(self.home / '.local/bin/desktop-control-center')
        self.file(self.home / '.local/lib/desktop_control_center/settings.py')
        for name in ['lock', 'display', 'screenshot', 'battery-watch', 'brightness', 'volume']:
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
  id)
    if [ "$1" = -u ]; then echo 1000; else exit 2; fi
    ;;
  timeout)
    [ "$1" = 3s ] || exit 2
    shift
    exec "$@"
    ;;
  xset)
    if [ "${DISPLAY_CHECK_FAIL:-}" = yes ]; then echo 'display unavailable' >&2; exit 9; fi
    ;;
  awesome-client)
    if [ "${AWESOME_CLIENT_FAIL:-}" = yes ]; then echo 'Awesome not responding' >&2; exit 10; fi
    echo '4.3'
    ;;
  pgrep)
    for arg; do pattern=$arg; done
    case "$pattern" in
      *picom*) service=picom ;;
      *dunst*) service=dunst ;;
      *lxqt-policykit-agent*) service=lxqt-policykit-agent ;;
      *xss-lock*) service=xss-lock ;;
      *snixembed*) service=snixembed ;;
      *) exit 1 ;;
    esac
    case " ${ACTIVE_PROCESSES:-} " in *" $service "*) exit 0 ;; *) exit 1 ;; esac
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

    def test_terminal_executor_is_required(self):
        (self.bin / 'xdg-terminal-exec').unlink()
        result = self.invoke()
        self.assertEqual(result.returncode, 1)
        self.assertIn('required command: xdg-terminal-exec', result.stdout)
        self.assertIn('1 required failure(s)', result.stdout)

    def test_terminal_selection_must_prioritize_kitty(self):
        terminals = self.config / 'xdg-terminals.list'
        terminals.write_text('xfce4-terminal.desktop\nkitty.desktop\n')
        result = self.invoke()
        self.assertEqual(result.returncode, 1)
        self.assertIn('expected kitty.desktop as the first entry', result.stdout)
        self.assertIn('found xfce4-terminal.desktop', result.stdout)
        self.assertIn('1 required failure(s)', result.stdout)
        terminals.write_text('')
        result = self.invoke()
        self.assertEqual(result.returncode, 1)
        self.assertIn('found <empty>', result.stdout)
        terminals.unlink()
        result = self.invoke()
        self.assertEqual(result.returncode, 1)
        self.assertIn('config', result.stdout)
        self.assertIn('xdg-terminals.list', result.stdout)
        self.assertIn('1 required failure(s)', result.stdout)

    def test_adwaita_breeze_icons_cursor_and_blue_selection_are_required(self):
        settings = self.config / 'xsettingsd/xsettingsd.conf'
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stdout)
        settings.write_text('Net/ThemeName "VAX"\nGtk/ColorScheme "selected_bg_color:#001a00"\n')
        result = self.invoke()
        self.assertEqual(result.returncode, 1)
        self.assertIn('GTK theme: expected Adwaita', result.stdout)
        self.assertIn('GTK selection accent: expected #3584e4', result.stdout)
        self.assertIn('GTK icon theme: expected Breeze', result.stdout)
        self.assertIn('GTK cursor theme: expected Adwaita', result.stdout)

    def test_missing_default_wallpaper_is_required(self):
        (self.home / '.local/share/wallpapers/aurora-cabin.png').unlink()
        result = self.invoke()
        self.assertEqual(result.returncode, 1)
        self.assertIn('asset', result.stdout)
        self.assertIn('aurora-cabin.png', result.stdout)
        self.assertIn('1 required failure(s)', result.stdout)
        self.assertNotIn('win98-teal', result.stdout)

    def test_optional_warnings(self):
        (self.bin / 'firefox').unlink()
        result = self.invoke()
        self.assertEqual(result.returncode, 0)
        self.assertIn('optional command: firefox', result.stdout)
        self.assertIn('0 required failure(s), 1 warning(s)', result.stdout)

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

    def test_runtime_without_display_is_skipped(self):
        result = self.invoke('--runtime')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('runtime checks skipped: DISPLAY is not set', result.stdout)
        self.assertIn('0 required failure(s), 1 warning(s)', result.stdout)

    def test_runtime_checks_live_services_and_optional_services(self):
        self.env['DISPLAY'] = ':93'
        self.env['ACTIVE_PROCESSES'] = 'picom dunst lxqt-policykit-agent xss-lock snixembed'
        result = self.invoke('--runtime', '--verbose')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for detail in ['X11 display reachable', 'Awesome runtime query succeeded',
                       'runtime service picom', 'runtime service dunst',
                       'runtime service lxqt-policykit-agent', 'runtime service xss-lock']:
            self.assertIn(detail, result.stdout)
        self.assertIn('0 required failure(s), 0 warning(s)', result.stdout)

        self.env['ACTIVE_PROCESSES'] = 'picom dunst lxqt-policykit-agent snixembed'
        result = self.invoke('--runtime')
        self.assertEqual(result.returncode, 1)
        self.assertIn('required runtime service not running: xss-lock', result.stdout)
        self.assertIn('1 required failure(s)', result.stdout)

    def test_runtime_query_failures_and_optional_service_warnings(self):
        self.env['DISPLAY'] = ':93'
        self.env['ACTIVE_PROCESSES'] = 'picom dunst lxqt-policykit-agent xss-lock'
        self.env['DISPLAY_CHECK_FAIL'] = 'yes'
        self.env['AWESOME_CLIENT_FAIL'] = 'yes'
        result = self.invoke('--runtime')
        self.assertEqual(result.returncode, 1)
        self.assertIn('X11 display unavailable', result.stdout)
        self.assertIn('Awesome runtime query failed', result.stdout)
        self.assertIn('display unavailable', result.stdout)
        self.assertIn('Awesome not responding', result.stdout)
        self.assertIn('2 required failure(s)', result.stdout)

        del self.env['DISPLAY_CHECK_FAIL']
        del self.env['AWESOME_CLIENT_FAIL']
        result = self.invoke('--runtime')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn('optional runtime service not running: snixembed', result.stdout)
        self.assertIn('0 required failure(s), 1 warning(s)', result.stdout)

    def test_help_and_bad_options(self):
        self.assertEqual(self.invoke('--help').returncode, 0)
        self.assertIn('--runtime', self.invoke('--help').stdout)
        for args in [('--unknown',), ('--verbose', 'extra'), ('--help', 'extra'),
                     ('--runtime', '--runtime'), ('--verbose', '--verbose')]:
            with self.subTest(args=args):
                self.assertEqual(self.invoke(*args).returncode, 64)


if __name__ == '__main__':
    unittest.main()
