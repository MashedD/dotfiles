"""Private-Xvfb lock verification; never discover or signal real-display lockers."""
from dataclasses import dataclass
import os
from pathlib import Path
import signal
import subprocess
import time


@dataclass(frozen=True, order=True)
class Identity:
    pid: int
    start: str


class PrivateLock:
    def __init__(self, env, helper, log_text, *, proc=Path('/proc'),
                 run=subprocess.run, kill=os.kill, clock=time.monotonic, sleep=time.sleep):
        self.env, self.helper, self.log_text = env, helper, log_text
        self.proc, self.run, self.kill = proc, run, kill
        self.clock, self.sleep = clock, sleep
        self.stage = 'before Win+L'
        self.started = False
        self.observed = set()
        self.last_processes = set()
        self.last_window = None
        self.began = clock()

    def identity(self, pid):
        """Read identity around the environment check to reject a recycled PID."""
        path = self.proc / str(pid)
        try:
            first = (path / 'stat').read_text().rsplit(')', 1)[1].split()
            if first[0] in ('Z', 'X') or (path / 'comm').read_text().strip() != 'i3lock':
                return None
            environment = (path / 'environ').read_bytes().split(b'\0')
            if ('DISPLAY=' + self.env['DISPLAY']).encode() not in environment:
                return None
            second = (path / 'stat').read_text().rsplit(')', 1)[1].split()
            if first[19] != second[19] or second[0] in ('Z', 'X'):
                return None
            return Identity(int(pid), first[19])
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            return None

    def discover(self):
        found = set()
        for path in self.proc.iterdir():
            if path.name.isdigit():
                identity = self.identity(path.name)
                if identity is not None:
                    found.add(identity)
        self.last_processes = found
        self.observed.update(found)
        return found

    def windows(self):
        result = self.run(['xdotool', 'search', '--onlyvisible', '--class', '^i3lock$'],
                          env=self.env, capture_output=True, text=True, timeout=3)
        self.last_window = (result.returncode, result.stdout, result.stderr)
        assert result.returncode in (0, 1), f'Window search failed: {self.last_window}'
        return result.stdout.split() if result.returncode == 0 else []

    def wait_ready(self):
        self.stage = 'lock readiness'
        deadline = self.clock() + 8
        original = None
        while True:
            found = self.discover()
            assert len(found) <= 1, f'Multiple private lockers: {found}'
            if original is not None:
                assert found == {original}, 'Locker exited or was replaced before readiness'
            elif found:
                original = next(iter(found))
            visible = self.windows()
            if original is not None and visible:
                return original
            assert self.clock() < deadline, 'Timed out waiting for live locker and visible window'
            self.sleep(0.05)

    def verify_duplicate(self, original):
        self.stage = 'duplicate helper request'
        result = self.run(['sh', str(self.helper)], env=self.env, timeout=3,
                          capture_output=True, text=True)
        assert result.returncode == 0, f'Duplicate helper failed: {result}'
        self.stage = 'duplicate observation'
        deadline = self.clock() + 1
        while True:
            assert self.discover() == {original}, 'Duplicate request changed the locker process set'
            assert self.windows(), 'Lock window disappeared after duplicate request'
            if self.clock() >= deadline:
                return
            self.sleep(0.05)

    def cleanup(self):
        if not self.started:
            return
        self.stage = 'cleanup'
        deadline = self.clock() + 3
        signalled = set()
        while True:
            found = self.discover()
            for identity in found - signalled:
                # Recheck identity AND display immediately before signalling.
                if self.identity(identity.pid) == identity:
                    try:
                        self.kill(identity.pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                    signalled.add(identity)
            visible = self.windows()
            if not found and not visible:
                self.started = False
                return
            assert self.clock() < deadline, 'Private locker/window did not disappear during cleanup'
            self.sleep(0.05)

    def diagnostic(self, error):
        details = [f'Lock stage={self.stage}; elapsed={self.clock()-self.began:.3f}s; DISPLAY={self.env["DISPLAY"]}',
                   f'observed={sorted(self.observed)}; last_processes={sorted(self.last_processes)}',
                   f'last_window={self.last_window}; failure={error}']
        try:
            details.append(self.log_text())
        except Exception as diagnostic_error:
            details.append(f'Private log unavailable: {diagnostic_error}')
        return '\n'.join(details)

    def exercise(self, press):
        """Run Win+L once; preserve original diagnostics if cleanup also fails."""
        failure = None
        try:
            assert not self.discover(), 'Private display already has an i3lock process'
            self.started = True
            press('super+l')
            original = self.wait_ready()
            self.verify_duplicate(original)
        except BaseException as error:
            failure = AssertionError(self.diagnostic(error))
            raise failure from error
        finally:
            try:
                self.cleanup()
            except Exception as cleanup_error:
                details = self.diagnostic(cleanup_error)
                if failure is None:
                    raise AssertionError(details) from cleanup_error
                failure.add_note('Cleanup also failed:\n' + details)
