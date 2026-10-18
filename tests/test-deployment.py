"""Isolated deployment and runner tests; never use the real HOME or desktop."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LOCAL_PATHS = ['.config/pcmanfm/default/pcmanfm.conf',
               '.config/pcmanfm/default/desktop-items-0.conf',
               '.config/pcmanfm/default/desktop-items-1.conf',
               '.config/mc/panels.ini', '.config/mc/hotlist']


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base / 'repo'
        self.repo.mkdir()
        self.home = self.base / 'home'
        self.home.mkdir()
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.log = self.base / 'calls'
        shutil.copy(ROOT / 'stow.sh', self.repo)
        self.env = dict(os.environ, HOME=str(self.home),
                        PATH=f'{self.bin}:{os.environ["PATH"]}', CALLS=str(self.log))
        self.stub('stow')
        self.stub('fc-cache')

    def stub(self, name):
        file = self.bin / name
        file.write_text(f'#!{shutil.which("python3")}\n'
                        'import json, os, sys\n'
                        'with open(os.environ["CALLS"], "a") as f:\n'
                        ' f.write(json.dumps([os.path.basename(sys.argv[0])] + sys.argv[1:]) + "\\n")\n'
                        'if "--simulate" in sys.argv and os.environ.get("FAIL_PREFLIGHT"):\n'
                        ' sys.exit(1)\n'
                        'if os.environ.get("FAIL_TOOL") == os.path.basename(sys.argv[0]):\n'
                        ' sys.exit(9)\n')
        file.chmod(0o755)

    def invoke(self, *args):
        return subprocess.run(['/bin/bash', str(self.repo / 'stow.sh'), *args],
                              env=self.env, cwd=self.base, text=True, capture_output=True)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_default_and_actions(self):
        self.assertEqual(self.invoke().returncode, 0)
        self.assertEqual(len(self.calls()), 1)
        self.assertIn('--simulate', self.calls()[0])
        for action, flag in [('apply', '--restow'), ('unlink', '--delete')]:
            self.log.unlink()
            self.assertEqual(self.invoke(action).returncode, 0)
            calls = self.calls()
            self.assertEqual(len(calls), 3)
            self.assertIn(flag, calls[0])
            self.assertIn(flag, calls[1])
            self.assertEqual(calls[2], ['fc-cache', '-f'])

    def test_no_exclusions_and_identical_preflight_arguments(self):
        for action in ['check', 'apply', 'unlink']:
            if self.log.exists(): self.log.unlink()
            result = self.invoke(action)
            self.assertEqual(result.returncode, 0, result.stderr)
            stow_calls = [c for c in self.calls() if c[0] == 'stow']
            for call in stow_calls:
                self.assertFalse(any(arg.startswith('--ignore') for arg in call))
            if len(stow_calls) == 2:
                self.assertEqual([a for a in stow_calls[0] if a not in ['--simulate', '--verbose=1']],
                                 stow_calls[1])
            self.assertNotIn('Excluding', result.stdout)

    def test_preflight_failure(self):
        self.env['FAIL_PREFLIGHT'] = '1'
        for action in ['apply', 'unlink']:
            if self.log.exists(): self.log.unlink()
            self.assertNotEqual(self.invoke(action).returncode, 0)
            self.assertEqual(len(self.calls()), 1)

    def test_invalid_arguments(self):
        for args in [('bad',), ('--bad',), ('check', 'apply'), ('--skip-local-conflicts',)]:
            self.assertEqual(self.invoke(*args).returncode, 64)
        self.assertEqual(self.calls(), [])

    def test_real_stow_conflict_safety(self):
        stow = shutil.which('stow')
        self.assertIsNotNone(stow, 'GNU Stow is required for integration checks')
        (self.bin / 'stow').unlink()
        (self.bin / 'stow').symlink_to(stow)
        managed = ['.local/bin/codex-usage', '.local/bin/crypto-prices',
                   '.config/picom/picom.conf', '.config/btop/btop.conf', '.config/unrelated']
        managed += ['.config/mc/menu', '.config/mc/mc.ext.ini', '.config/libfm/libfm.conf']
        for path in managed:
            source = self.repo / 'dotfiles' / path
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text('repository')
        originals = {}
        for index, path in enumerate(LOCAL_PATHS):
            self.assertFalse((self.repo / 'dotfiles' / path).exists())
            target = self.home / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(f'local state {index}\n'.encode())
            target.chmod(0o600)
            originals[path] = (target.read_bytes(), target.stat().st_mode)
        def verify_local():
            for path, (content, mode) in originals.items():
                target = self.home / path
                self.assertFalse(target.is_symlink())
                self.assertEqual(target.read_bytes(), content)
                self.assertEqual(target.stat().st_mode, mode)
        other = self.home / '.config/unrelated'
        other.write_text('unrelated conflict')
        self.assertNotEqual(self.invoke('apply').returncode, 0)
        self.assertEqual(other.read_text(), 'unrelated conflict')
        verify_local()
        other.unlink()
        result = self.invoke('apply')
        self.assertEqual(result.returncode, 0, result.stderr)
        for path in managed:
            self.assertEqual((self.home / path).resolve(),
                             (self.repo / 'dotfiles' / path).resolve(), path)
        verify_local()
        self.assertEqual(self.invoke('unlink').returncode, 0)
        self.assertFalse(other.exists())
        verify_local()


class ConfigCleanupTests(unittest.TestCase):
    def test_mutable_state_is_not_in_package(self):
        for path in LOCAL_PATHS:
            self.assertFalse(os.path.lexists(ROOT / 'dotfiles' / path), path)
        for path in ['.config/mc/menu', '.config/mc/mc.ext.ini', '.config/libfm/libfm.conf']:
            self.assertTrue((ROOT / 'dotfiles' / path).is_file(), path)

    def test_shared_code_settings_do_not_pin_project_or_broaden_approval(self):
        source = (ROOT / 'dotfiles/.config/Code - OSS/User/settings.json').read_text()
        # Code accepts JSONC. Preserve strings (including URLs) while removing
        # comments and trailing commas, then use the standard JSON parser.
        strings = r'"(?:\\.|[^"\\])*"'
        source = re.sub(strings + r'|//[^\n]*|/\*[\s\S]*?\*/',
                        lambda m: m[0] if m[0].startswith('"') else '', source)
        source = re.sub(strings + r'|,\s*(?=[}\]])',
                        lambda m: m[0] if m[0].startswith('"') else '', source)
        settings = json.loads(source)
        self.assertNotIn('python.defaultInterpreterPath', settings)
        self.assertEqual(settings['chat.tools.terminal.autoApprove'], {'make': True})

    def test_shell_path_cleanup_and_syntax(self):
        path = ROOT / 'dotfiles/.config/zsh/.zshrc'
        source = path.read_text()
        self.assertIn('export PATH="$HOME/.opencode/bin:$PATH"', source)
        self.assertNotIn('/home/user/.opencode', source)
        self.assertNotIn('HYPRSHOT_DIR', source)
        zsh = shutil.which('zsh')
        self.assertIsNotNone(zsh, 'zsh is required for configuration syntax checks')
        subprocess.run([zsh, '-n', str(path)], check=True)


class HelperNamesTests(unittest.TestCase):
    def test_desktop_helpers_without_old_aliases(self):
        helpers = ROOT / 'dotfiles/.local/bin'
        names = ['battery-watch', 'brightness', 'check', 'display',
                 'locale-setup', 'lock', 'screenshot', 'volume']
        for name in names:
            helper = helpers / f'desktop-{name}'
            alias = helpers / f'openbox-{name}'
            self.assertTrue(helper.is_file(), helper)
            self.assertTrue(os.access(helper, os.X_OK), helper)
            self.assertFalse(os.path.lexists(alias), alias)
            self.assertNotIn('OPENBOX_', helper.read_text(), helper)
            subprocess.run(['sh', '-n', str(helper)], check=True)
        for path in (ROOT / 'dotfiles/.config/awesome').glob('*'):
            if path.is_file():
                self.assertNotIn('openbox-', path.read_text(), str(path))

    def test_desktop_environment_overrides(self):
        helpers = ROOT / 'dotfiles/.local/bin'
        cases = [
            ('display', 'poll_seconds', 'DESKTOP_DISPLAY_POLL_SECONDS', '3'),
            ('display', 'retry_count', 'DESKTOP_DISPLAY_RETRY_COUNT', '3'),
            ('display', 'retry_delay', 'DESKTOP_DISPLAY_RETRY_DELAY', '1'),
            ('display', 'upgrade_delay', 'DESKTOP_DISPLAY_UPGRADE_DELAY', '30'),
            ('screenshot', 'destination', 'DESKTOP_SCREENSHOT_DIR', '/test-home/Pictures/Screenshots'),
            ('check', 'bin_root', 'DESKTOP_HELPER_ROOT', '/test-home/.local/bin'),
        ]
        for helper, variable, override, default in cases:
            # Evaluate just the actual assignment, never the service/helper body.
            source = (helpers / f'desktop-{helper}').read_text()
            assignment = next(line for line in source.splitlines() if line.startswith(variable + '='))
            script = assignment + '\nprintf "%s" "$' + variable + '"\n'
            env = {'HOME': '/test-home', override.replace('DESKTOP_', 'OPENBOX_', 1): 'ignored'}
            result = subprocess.run(['/bin/sh', '-c', script], env=env, text=True, capture_output=True, check=True)
            self.assertEqual(result.stdout, default)
            env[override] = 'explicit-value'
            result = subprocess.run(['/bin/sh', '-c', script], env=env, text=True, capture_output=True, check=True)
            self.assertEqual(result.stdout, 'explicit-value')


class RunnerTests(unittest.TestCase):
    setUp = DeploymentTests.setUp
    stub = DeploymentTests.stub
    calls = DeploymentTests.calls
    def prepare_runner(self):
        tests = self.repo / 'tests'
        tests.mkdir(exist_ok=True)
        shutil.copy(ROOT / 'tests/run.sh', tests)
        (tests / 'test-awesome-fake.lua').touch()
        for name in ['awesome', 'lua', 'python3']:
            self.stub(name)
        return tests / 'run.sh'

    def test_runner_modes(self):
        runner = self.prepare_runner()
        for mode in ['', '--session', '--visual']:
            if self.log.exists(): self.log.unlink()
            result = subprocess.run(['/bin/bash', str(runner)] + ([mode] if mode else []),
                                    env=self.env, cwd=self.base, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = self.calls()
            sessions = [c for c in calls if 'tests/test-awesome-session.py' in c]
            self.assertEqual(len(sessions), {'': 0, '--session': 6, '--visual': 7}[mode])
            if mode == '--visual': self.assertIn('--composited', sessions[-1])
        self.env['FAIL_TOOL'] = 'awesome'
        self.assertEqual(subprocess.run(['/bin/bash', str(runner)], env=self.env,
                                        capture_output=True).returncode, 9)
        del self.env['FAIL_TOOL']
        empty = self.base / 'empty'
        empty.mkdir()
        for tool in ['dirname', 'bash']:
            (empty / tool).symlink_to(shutil.which(tool))
        self.env['PATH'] = str(empty)
        self.assertEqual(subprocess.run(['/bin/bash', str(runner)], env=self.env,
                                        capture_output=True).returncode, 127)

    def test_runner_scenarios_and_validation(self):
        runner = self.prepare_runner()
        for mode in ('--session', '--visual'):
            for selector in (['--scenario', 'titlebars'], ['--scenario', 'workspace-transfer'],
                             ['--scenario=sidebar-documents'], ['--scenario=sidebar-settings'],
                             ['--scenario=sidebar-news'], ['--scenario=sidebar-personalization'], ['--scenario=all']):
                if self.log.exists(): self.log.unlink()
                result = subprocess.run(['/bin/bash', str(runner), mode, *selector],
                                        env=self.env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                sessions = [call for call in self.calls() if 'tests/test-awesome-session.py' in call]
                selected = selector[1] if selector[0] == '--scenario' else selector[0].split('=', 1)[1]
                if selected == 'all':
                    expected = ['workspace-transfer', 'sidebar-documents', 'sidebar-settings', 'sidebar-news', 'sidebar-personalization', 'all']
                    if mode == '--visual': expected.append('all')
                else:
                    expected = [selected] * (1 if mode == '--session' else 2)
                self.assertEqual(len(sessions), len(expected))
                actual = []
                for call in sessions:
                    index = call.index('--scenario')
                    actual.append(call[index+1])
                    self.assertEqual(call.count('--scenario'), 1)
                self.assertEqual(actual, expected)
                if mode == '--visual': self.assertIn('--composited', sessions[-1])
        for argv, status in [(['--help'],0), (['--scenario','titlebars'],64),
                             (['--session','--visual'],64), (['--session','--session'],64),
                             (['--session','--scenario'],64), (['--visual','--scenario=invalid'],64),
                             (['--session','--scenario=all','--scenario','titlebars'],64),
                             (['--session','--unknown'],64), (['--session','extra'],64)]:
            if self.log.exists(): self.log.unlink()
            result = subprocess.run(['/bin/bash', str(runner), *argv],env=self.env,
                                    capture_output=True,text=True)
            self.assertEqual(result.returncode,status,(argv,result.stderr))
            self.assertEqual(self.calls(),[],argv)
        stub = self.bin / 'python3'
        stub.write_text(stub.read_text() + '\nif "tests/test-awesome-session.py" in sys.argv: sys.exit(17)\n')
        for mode in ('--session','--visual'):
            if self.log.exists(): self.log.unlink()
            result = subprocess.run(['/bin/bash',str(runner),mode,'--scenario','titlebars'],
                                    env=self.env,capture_output=True,text=True)
            self.assertEqual(result.returncode,17,result.stderr)
            sessions = [call for call in self.calls() if 'tests/test-awesome-session.py' in call]
            self.assertEqual(len(sessions),1,'Failure must stop before a second runtime invocation')


if __name__ == '__main__':
    unittest.main()
