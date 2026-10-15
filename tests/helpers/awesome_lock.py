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
        self.process_details = {}
        self.window_owners = {}
        self.original_windows = set()
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

    def process_info(self, pid):
        path = self.proc / str(pid)
        try:
            before = (path / 'stat').read_text().rsplit(')', 1)[1].split()
            name = (path / 'comm').read_text().strip()
            try:
                executable = os.readlink(path / 'exe')
            except (PermissionError, FileNotFoundError):
                executable = None
            try:
                command = (path / 'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
            except PermissionError:
                command = '<unavailable>'
            after = (path / 'stat').read_text().rsplit(')', 1)[1].split()
            if before[19] != after[19] or before[1] != after[1] or after[0] in ('Z', 'X'):
                return None
            return dict(identity=Identity(int(pid), after[19]), parent=int(after[1]),
                        executable=executable, command=command, name=name)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            return None

    def ancestry(self, identity):
        chain, seen, pid = [], set(), identity.pid
        while pid > 1:
            assert pid not in seen, 'Cyclic process ancestry'
            seen.add(pid)
            info = self.process_info(pid)
            assert info is not None, f'Missing/ambiguous ancestry for PID {pid}'
            self.process_details[info['identity']] = info
            if not chain:
                assert info['identity'] == identity, 'PID reused while reading locker ancestry'
                assert info['executable'], 'Locker executable identity unavailable'
            else:
                assert int(info['identity'].start) <= int(chain[-1]['identity'].start), 'Parent PID was reused'
            chain.append(info)
            pid = info['parent']
        return chain

    def instance_root(self, found, original=None):
        assert found, 'Locker exited or was replaced'
        chains = {item: self.ancestry(item) for item in found}
        roots = [item for item in found if not any(
            info['identity'] in found for info in chains[item][1:])]
        assert len(roots) == 1, f'Independent locker roots: {roots}'
        root = roots[0]
        if original is not None:
            assert root == original, 'Original locker root was replaced'
        executable = chains[root][0]['executable']
        for item, chain in chains.items():
            assert root in {info['identity'] for info in chain}, 'Unverified locker descendant'
            assert chain[0]['executable'] == executable, 'Locker executable differs from original'
            assert self.identity(item.pid) == item, 'Locker exited or PID was reused during ancestry check'
        return root

    def record_window_owners(self, windows):
        for window in windows:
            try:
                result = self.run(['xprop', '-id', window, '_NET_WM_PID'], env=self.env,
                                  capture_output=True, text=True, timeout=3)
                self.window_owners[window] = (result.returncode, result.stdout, result.stderr)
            except (OSError, subprocess.TimeoutExpired) as error:
                self.window_owners[window] = str(error)

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
            if found:
                original = self.instance_root(found, original)
            else:
                assert original is None, 'Locker exited or was replaced before readiness'
            visible = self.windows()
            if original is not None and visible:
                self.original_windows = set(visible)
                self.record_window_owners(visible)
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
            self.instance_root(self.discover(), original)
            windows = self.windows()
            self.record_window_owners(windows)
            assert set(windows) == self.original_windows, 'Original lock windows disappeared or were replaced'
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
                   f'last_window={self.last_window}; failure={error}',
                   f'process_details={self.process_details}',
                   f'original_windows={self.original_windows}; window_owners={self.window_owners}']
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
