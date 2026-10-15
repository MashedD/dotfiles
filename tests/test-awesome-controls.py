"""Deterministic failure-path tests for private-session pointer scenarios."""
import sys
from pathlib import Path
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent / 'helpers'))
import awesome_controls


class ReorderDragTests(unittest.TestCase):
    def test_acquisition_feedback_release_and_failures(self):
        for failure in (None, 1, 2):
            calls=[]
            waits=[0]
            def pointer(*args): calls.append(('pointer',args))
            def wait(code,expected):
                waits[0]+=1
                calls.append(('wait',expected))
                if waits[0]==failure: raise AssertionError('bounded barrier failed')
            def run():
                awesome_controls.verify_reorder_drag(start=(100,200),end=(100,400),section='calendar',
                    lua=lambda _: 'string "false"',pointer=pointer,wait=wait)
            if failure:
                with self.assertRaisesRegex(AssertionError,'bounded barrier failed'): run()
            else: run()
            self.assertEqual(calls[0],('pointer',('mousemove',100,200,'mousedown',1)))
            self.assertEqual(calls[1],('wait','grab=true:button=true'))
            releases=[call for call in calls if call==('pointer',('mouseup',1))]
            self.assertEqual(len(releases),1)
            if failure==1:
                self.assertNotIn(('pointer',('mousemove','--sync',100,400)),calls)
            else:
                self.assertEqual(calls[2],('pointer',('mousemove','--sync',100,400)))
                self.assertEqual(calls[3],('wait','#ffffff'))
            if not failure:self.assertEqual(calls[-1],('wait','grab=false:button=false'))


class EdgeScrollTests(unittest.TestCase):
    def run_drag(self, blocked=None):
        now = [0.0]
        calls = []
        state = dict(grab='false', button='false', pointer_x=1150, pointer_y=300,
                     visible='true', x=1000, y=30, width=300, height=850,
                     top=150, bottom=850, position=0, maximum=100,
                     dragging='false', header='#588cd4', order='todo,calendar')
        at_edge = [False]

        def lua(_):
            if at_edge[0] and blocked != 'progress':
                ceiling = 40 if blocked == 'bottom' else 100
                state['position'] = min(ceiling, state['position'] + 20)
            return '   string "' + '|'.join(f'{key}={value}' for key, value in state.items()) + '"\n'

        def pointer(*args):
            calls.append(args)
            if 'mousedown' in args:
                state['button'] = 'true'
                state['grab'] = 'false' if blocked == 'grab' else 'true'
            elif args[0] == 'mouseup':
                state['button'] = state['grab'] = 'false'
            elif args[0] == 'mousemove':
                state['pointer_x'], state['pointer_y'] = args[-2:]
                if blocked != 'threshold':
                    state['dragging'] = 'true'
                    state['header'] = '#ffffff'
                at_edge[0] = args[-1] >= 842

        def sleep(seconds):
            now[0] += seconds

        with patch.object(awesome_controls.time, 'monotonic', side_effect=lambda: now[0]), \
             patch.object(awesome_controls.time, 'sleep', side_effect=sleep):
            try:
                awesome_controls.verify_sidebar_edge_scroll(
                    lua=lua, pointer=pointer,
                    sidebar_title_point=lambda *args, **kwargs: (1150, 300),
                    log_text=lambda: 'private Awesome log')
            except AssertionError as error:
                self.assertEqual(calls[-1], ('mouseup', 1))
                self.assertEqual(sum('mousedown' in call for call in calls), 1)
                self.assertEqual(state['button'], 'false')
                raise error
        return calls

    def test_success_has_separate_threshold_and_edge_moves(self):
        calls = self.run_drag()
        self.assertIn(('mousemove', '--sync', 1162, 300), calls)
        self.assertIn(('mousemove', '--sync', 1150, 842), calls)
        self.assertEqual(calls[-1], ('mouseup', 1))
        self.assertEqual(sum('mousedown' in call for call in calls), 1)

    def test_failures_are_bounded_diagnostic_and_release_button(self):
        for blocked, stage in [('grab', 'acquire grab'), ('threshold', 'cross drag threshold'),
                               ('progress', 'positive scroll progress'), ('bottom', 'reach scroll bottom')]:
            with self.subTest(blocked=blocked):
                with self.assertRaises(AssertionError) as raised:
                    self.run_drag(blocked)
                text = str(raised.exception)
                for detail in [f'stage={stage}', 'elapsed=', 'target=', 'initial=', 'last=',
                               'pointer_x', 'pointer_y', 'button', 'grab', 'visible', 'width',
                               'height', 'top', 'bottom', 'position', 'maximum', 'header',
                               'order', 'private Awesome log', 'Original failure:']:
                    self.assertIn(detail, text)
                self.assertIsInstance(raised.exception.__cause__, AssertionError)

    def test_diagnostic_and_cleanup_failures_preserve_original(self):
        def fail_source(*args, **kwargs):
            raise RuntimeError('original locate failure')

        def fail_diagnostic(*args):
            raise RuntimeError('diagnostic unavailable')

        releases = []

        def fail_release(*args):
            releases.append(args)
            raise RuntimeError('release unavailable')

        with self.assertRaises(AssertionError) as raised:
            awesome_controls.verify_sidebar_edge_scroll(
                lua=fail_diagnostic, pointer=fail_release, sidebar_title_point=fail_source,
                log_text=fail_diagnostic)
        self.assertEqual(releases, [('mouseup', 1)])
        self.assertEqual(str(raised.exception.__cause__), 'original locate failure')
        self.assertIn('State diagnostic failed:', str(raised.exception))
        self.assertIn('Log diagnostic failed:', str(raised.exception))
        self.assertIn('release unavailable', str(raised.exception.__cause__.__notes__))


if __name__ == '__main__':
    unittest.main()
