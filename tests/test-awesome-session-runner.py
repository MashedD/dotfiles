"""Argument/dispatch tests without starting D-Bus, X11, or desktop programs."""
import ast
import contextlib
import importlib.util
import io
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock, patch

PATH = Path(__file__).with_name('test-awesome-session.py')
spec = importlib.util.spec_from_file_location('awesome_session_runner', PATH)
session = importlib.util.module_from_spec(spec)
spec.loader.exec_module(session)


class ArgumentTests(unittest.TestCase):
    def test_defaults_and_supported_combinations(self):
        self.assertEqual(session.parse_args([]).scenario, 'all')
        for name in ('all', 'titlebars', 'workspace-transfer', 'sidebar-documents', 'sidebar-settings', 'sidebar-news', 'sidebar-personalization', 'menu-popups'):
            for argv in (['--scenario', name], ['--scenario='+name, '--composited', '--inside']):
                args = session.parse_args(argv)
                self.assertEqual(args.scenario, name)
                self.assertEqual(args.inside, '--inside' in argv)
                self.assertEqual(args.composited, '--composited' in argv)

    def test_help_and_errors_do_not_launch_anything(self):
        cases = [(['--help'], 0), (['--unknown'], 2), (['--scenario'], 2),
                 (['--scenario', 'unknown'], 2), (['--scenario', ''], 2),
                 (['--scenario', 'all', '--scenario=titlebars'], 2),
                 (['--scenario=all', '--scenario=all'], 2)]
        for argv, status in cases:
            with self.subTest(argv=argv), patch.object(sys, 'argv', [str(PATH), *argv]), \
                 patch.object(session.subprocess, 'call') as call, \
                 patch.object(session.subprocess, 'Popen') as popen, \
                 contextlib.redirect_stdout(io.StringIO()) as out, \
                 contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as raised:
                    session.main()
                self.assertEqual(raised.exception.code, status)
                call.assert_not_called(); popen.assert_not_called()
                if status == 0:
                    self.assertIn('titlebars', out.getvalue())
                    self.assertNotIn('--inside', out.getvalue())

    def test_outer_process_forwards_flags_and_exit_status(self):
        argv = ['--scenario', 'sidebar-documents', '--composited']
        with patch.object(sys, 'argv', [str(PATH), *argv]), \
             patch.object(session.subprocess, 'call', return_value=17) as call:
            self.assertEqual(session.main(), 17)
            call.assert_called_once_with(['dbus-run-session', '--', sys.executable,
                                         str(PATH), '--inside', *argv])


class DispatchTests(unittest.TestCase):
    def callbacks(self, failure=None):
        events=[]
        def callback(name):
            def run():
                events.append(name)
                if name == failure:
                    raise RuntimeError('scenario failed')
            return run
        return events, {name: callback(name) for name in ('prepare', 'controls', 'destruction')}

    def test_focused_order_and_default_continuation(self):
        for scenario in ('all', 'titlebars', 'workspace-transfer', 'sidebar-documents', 'sidebar-settings', 'sidebar-news', 'sidebar-personalization', 'menu-popups'):
            events, callbacks = self.callbacks()
            focused = session.run_focused(scenario, **callbacks)
            self.assertEqual(focused, scenario == 'titlebars')
            expected = ['prepare', 'controls', 'destruction'] if scenario == 'titlebars' else []
            self.assertEqual(events, expected)

    def test_unknown_scenario_and_failure_do_not_continue(self):
        events, callbacks = self.callbacks()
        with self.assertRaises(ValueError): session.run_focused('unknown', **callbacks)
        self.assertEqual(events, [])
        for index, name in enumerate(('prepare', 'controls', 'destruction')):
            events, callbacks = self.callbacks(failure=name)
            with self.assertRaisesRegex(RuntimeError, 'scenario failed'):
                session.run_focused('titlebars', **callbacks)
            self.assertEqual(events, ['prepare', 'controls', 'destruction'][:index+1])

    def test_timing_reports_success_only_after_success(self):
        for fail in (False, True):
            check=Mock(side_effect=RuntimeError('failed') if fail else None)
            with contextlib.redirect_stdout(io.StringIO()) as output, \
                 patch.object(session.time, 'monotonic', side_effect=[10, 12]):
                if fail:
                    with self.assertRaises(RuntimeError): session.run_timed('titlebars.controls', check)
                else:
                    session.run_timed('titlebars.controls', check)
            check.assert_called_once_with()
            self.assertIn('RUN: titlebars.controls', output.getvalue())
            self.assertEqual('PASS:' in output.getvalue(), not fail)
            if not fail:self.assertIn('(2.00s)', output.getvalue())

    def test_full_sequence_keeps_late_destruction_and_lock(self):
        # Guard placement without simulating hundreds of unrelated X11 operations.
        tree=ast.parse(PATH.read_text())
        main=next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name=='main')
        calls={name:[] for name in ('run_focused','check_titlebars','check_titlebar_destruction','PrivateLock','finish_session')}
        for node in ast.walk(main):
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in calls:
                calls[node.func.id].append(node)
        self.assertEqual(len(calls['check_titlebars']),1)
        self.assertEqual(len(calls['check_titlebar_destruction']),1)
        self.assertEqual(len(calls['PrivateLock']),1)
        self.assertLess(calls['run_focused'][0].lineno,calls['check_titlebars'][0].lineno)
        self.assertLess(calls['check_titlebars'][0].lineno,calls['check_titlebar_destruction'][0].lineno)
        self.assertLess(calls['check_titlebar_destruction'][0].lineno,calls['PrivateLock'][0].lineno)
        focused=next(node for node in ast.walk(main) if isinstance(node, ast.If)
                     and isinstance(node.test, ast.Call) and isinstance(node.test.func, ast.Name)
                     and node.test.func.id=='run_focused')
        self.assertIsInstance(focused.body[-1],ast.Return)
        self.assertEqual(focused.body[-1].value.value,0)
        self.assertEqual(focused.body[0].value.args[0].value,'titlebars')
        self.assertEqual(max(calls['finish_session'],key=lambda call:call.lineno).args[0].value,'all')


if __name__ == '__main__':
    unittest.main()
