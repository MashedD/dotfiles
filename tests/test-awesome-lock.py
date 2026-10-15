"""Fake-time lock lifecycle tests; no X server, real locker, or real signals."""
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent / 'helpers'))
from awesome_lock import Identity, PrivateLock


A, B = Identity(100, '10'), Identity(101, '20')


class FakeLock(PrivateLock):
    def __init__(self, mode='ok'):
        self.now, self.mode, self.current = 0.0, mode, set()
        self.signals, self.presses, self.searches = [], [], []
        self.window_until = 0
        super().__init__({'DISPLAY': ':999'}, Path('/private/desktop-lock'),
                         lambda: 'private Awesome/Picom log', run=self.command,
                         kill=self.send_signal, clock=lambda: self.now, sleep=self.advance)
        if mode == 'preexisting':
            self.current = {A, B}

    def advance(self, seconds):
        self.now += seconds

    def press(self, keys):
        self.presses.append(keys)
        if self.mode != 'no-process':
            self.current = {A, B} if self.mode == 'multiple-ready' else {A}

    def discover(self):
        if self.mode == 'early-exit' and self.stage == 'lock readiness' and self.now >= 0.1:
            self.current = set()
        self.last_processes = set(self.current)
        self.observed.update(self.current)
        return set(self.current)

    def identity(self, pid):
        return next((item for item in self.current if item.pid == pid), None)

    def send_signal(self, pid, sig):
        self.signals.append((pid, sig))
        if self.mode != 'cleanup-stuck':
            self.current = {item for item in self.current if item.pid != pid}
            self.window_until = self.now + 0.2

    def windows(self):
        self.searches.append((self.stage, self.now))
        visible = self.now >= 0.2 and bool(self.current)
        if self.mode in ('never-visible', 'early-exit'):
            visible = False
        if self.stage == 'cleanup':
            visible = bool(self.current) or self.now < self.window_until
        if self.stage == 'duplicate observation' and self.mode == 'lost-window':
            visible = False
        self.last_window = (0 if visible else 1, '123\n' if visible else '', '')
        return ['123'] if visible else []

    def command(self, args, **kwargs):
        assert args == ['sh', '/private/desktop-lock']
        if self.mode == 'duplicate-timeout':
            raise subprocess.TimeoutExpired(args, 3)
        if self.mode == 'duplicate-extra':
            self.current.add(B)
        if self.mode == 'duplicate-replaced':
            self.current = {B}
        return subprocess.CompletedProcess(args, 7 if self.mode == 'duplicate-failed' else 0, '', 'stub stderr')


class LockLifecycleTests(unittest.TestCase):
    def test_delayed_window_duplicate_observation_and_cleanup(self):
        lock = FakeLock()
        lock.exercise(lock.press)
        self.assertEqual(lock.presses, ['super+l'])
        self.assertEqual(lock.signals, [(A.pid, signal.SIGTERM)])
        self.assertFalse(lock.started)
        self.assertFalse(lock.current)
        self.assertGreaterEqual(lock.now, 1.4)
        self.assertTrue(any(stage == 'lock readiness' and now < 0.2 for stage, now in lock.searches))
        cleanup_times = [now for stage, now in lock.searches if stage == 'cleanup']
        self.assertGreaterEqual(cleanup_times[-1] - cleanup_times[0], 0.2)

    def test_bounded_readiness_failures_and_diagnostics(self):
        for mode in ['no-process', 'early-exit', 'never-visible', 'multiple-ready']:
            with self.subTest(mode=mode):
                lock = FakeLock(mode)
                with self.assertRaises(AssertionError) as raised:
                    lock.exercise(lock.press)
                text = str(raised.exception)
                for field in ['stage=lock readiness', 'elapsed=', 'DISPLAY=:999',
                              'observed=', 'last_processes=', 'last_window=', 'private Awesome/Picom log']:
                    self.assertIn(field, text)
                self.assertIsNotNone(raised.exception.__cause__)
                self.assertLess(lock.now, 12)
                if mode == 'early-exit': self.assertLess(lock.now, 1)
                self.assertFalse(lock.current)
                self.assertEqual(lock.presses, ['super+l'])

    def test_preexisting_processes_are_not_signalled(self):
        lock = FakeLock('preexisting')
        with self.assertRaisesRegex(AssertionError, 'already has'):
            lock.exercise(lock.press)
        self.assertEqual(lock.signals, [])
        self.assertEqual(lock.presses, [])

    def test_duplicate_failures_and_unexpected_process_cleanup(self):
        for mode in ['duplicate-extra', 'duplicate-replaced', 'duplicate-failed',
                     'duplicate-timeout', 'lost-window']:
            with self.subTest(mode=mode):
                lock = FakeLock(mode)
                with self.assertRaises(AssertionError) as raised:
                    lock.exercise(lock.press)
                self.assertIn('stage=duplicate', str(raised.exception))
                self.assertFalse(lock.current)
                self.assertFalse(lock.started)
                if mode == 'duplicate-extra':
                    self.assertEqual({pid for pid, _ in lock.signals}, {A.pid, B.pid})

    def test_cleanup_failure_is_bounded_and_diagnostic(self):
        lock = FakeLock('cleanup-stuck')
        with self.assertRaisesRegex(AssertionError, 'stage=cleanup'):
            lock.exercise(lock.press)
        self.assertLess(lock.now, 5)
        self.assertEqual(len(lock.signals), 1)

    def test_cleanup_and_log_errors_do_not_replace_original(self):
        lock = FakeLock('never-visible')
        def broken_log():
            raise RuntimeError('log unavailable')
        def broken_cleanup():
            raise RuntimeError('cleanup unavailable')
        lock.log_text, lock.cleanup = broken_log, broken_cleanup
        with self.assertRaises(AssertionError) as raised:
            lock.exercise(lock.press)
        self.assertIn('stage=lock readiness', str(raised.exception))
        self.assertIn('Private log unavailable', str(raised.exception))
        self.assertIn('Timed out', str(raised.exception.__cause__))
        self.assertIn('cleanup unavailable', str(raised.exception.__notes__))

    def test_identity_recheck_prevents_signalling_reused_pid(self):
        lock = FakeLock()
        lock.started = True
        lock.current = {A}
        def reused(pid):
            lock.current.clear()
            return Identity(pid, 'new-start')
        lock.identity = reused
        lock.cleanup()
        self.assertEqual(lock.signals, [])


class ProcIdentityTests(unittest.TestCase):
    def test_exact_display_filter_start_time_and_zombies(self):
        with tempfile.TemporaryDirectory() as directory:
            proc = Path(directory)
            def process(pid, display, start, status='S', comm='i3lock'):
                path = proc / str(pid)
                path.mkdir()
                (path / 'stat').write_text(f'{pid} (name with spaces) ' + ' '.join([status] + ['0'] * 18 + [start]))
                (path / 'comm').write_text(comm + '\n')
                (path / 'environ').write_bytes(f'HOME=/private\0DISPLAY={display}\0'.encode())
            process(1, ':999', '123')
            process(2, ':0', '456')
            process(3, ':9990', '789')
            process(4, ':999', '999', 'Z')
            process(5, ':999', '111', comm='other')
            lock = PrivateLock({'DISPLAY': ':999'}, Path('/unused'), lambda: '', proc=proc)
            self.assertEqual(lock.discover(), {Identity(1, '123')})
            self.assertIsNone(lock.identity(99999))

    def test_window_search_uses_private_environment_and_visible_filter(self):
        calls = []
        def run(args, **kwargs):
            calls.append((args, kwargs))
            return subprocess.CompletedProcess(args, 0, '42\n', '')
        lock = PrivateLock({'DISPLAY': ':999'}, Path('/unused'), lambda: '', run=run)
        self.assertEqual(lock.windows(), ['42'])
        self.assertIn('--onlyvisible', calls[0][0])
        self.assertEqual(calls[0][1]['env']['DISPLAY'], ':999')
        self.assertEqual(lock.last_window, (0, '42\n', ''))


if __name__ == '__main__':
    unittest.main()
