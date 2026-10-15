"""Pure/fake-process tests for the opt-in audit; never contact a display."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('idle', Path(__file__).with_name('audit-awesome-idle.py'))
idle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(idle)


class AuditTests(unittest.TestCase):
    def test_cpu_conversion_and_rss(self):
        result=idle.summarize([(0,dict(pid=1,start='10',ticks=100,rss=1048576)),
                               (2,dict(pid=1,start='10',ticks=150,rss=3145728))],100)
        self.assertEqual(result['cpu_percent'],25)
        self.assertEqual(result['mean_rss_mib'],2)
        self.assertEqual(result['peak_rss_mib'],3)

    def test_sampling_stops_on_reuse_or_exit(self):
        now=[0]
        def sleep(seconds): now[0]+=seconds
        def changed(pid): return dict(pid=pid,start='first' if now[0]==0 else 'second',ticks=0,rss=0)
        with self.assertRaisesRegex(AssertionError,'identity changed'):
            idle.sample_process(1,3,clock=lambda:now[0],sleep=sleep,read=changed)
        with self.assertRaisesRegex(AssertionError,'before sampling'):
            idle.sample_process(1,3,read=changed,expected_start='different')
        def missing(pid): raise ProcessLookupError(pid)
        with self.assertRaises(ProcessLookupError): idle.sample_process(1,3,read=missing)

    def test_proc_parser_missing_fields_and_identity(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name); (root/'1').mkdir()
            fields=['S','0']+['0']*9+['10','20']+['0']*6+['123','0','4']
            (root/'1/stat').write_text('1 (name with spaces) '+' '.join(fields))
            result=idle.proc_sample(1,root)
            self.assertEqual(result['start'],'123')
            self.assertEqual(result['ticks'],30)
            (root/'1/stat').write_text('1 (name) S')
            with self.assertRaises(IndexError): idle.proc_sample(1,root)
            self.assertEqual(idle.find_live(root,display=None,executable='/nonexistent'),[])

    def test_instrumentation_anchors_and_control_copy(self):
        with tempfile.TemporaryDirectory() as name:
            directory=Path(name)
            config,env=idle.prepare(directory,True)
            self.assertNotEqual(env.get('DISPLAY'),':0')
            self.assertNotIn('DISPLAY',env)
            self.assertEqual(env['HOME'],str(directory/'home'))
            self.assertIn('__idle_prof.fetch', (config/'sidebar-data.lua').read_text())
            self.assertIn('document.todo.screen',(config/'sidebar.lua').read_text())
            self.assertNotIn('new_for_uri("trash:///")',(config/'sidebar-data.lua').read_text())
            self.assertNotIn('__idle_prof', (idle.ROOT/'dotfiles/.config/awesome/rc.lua').read_text())
        with self.assertRaises(AssertionError): idle.replace_once('missing','anchor','new')

    def test_isolated_cleanup_only_signals_owned_process_group(self):
        process=Mock(pid=987654)
        process.wait.side_effect=[KeyboardInterrupt(), 0]
        process.poll.return_value=None
        with patch.object(idle.subprocess, 'Popen', return_value=process) as launch, \
             patch.object(idle.os, 'killpg') as kill:
            with self.assertRaises(KeyboardInterrupt): idle.run_isolated(['private-stub'])
        self.assertTrue(launch.call_args.kwargs['start_new_session'])
        self.assertEqual(launch.call_args.kwargs['env']['AWESOME_IDLE_PRIVATE'],'1')
        kill.assert_called_once_with(987654,idle.signal.SIGTERM)

    def test_metrics_and_report_keep_phases_separate(self):
        metrics=idle.parse_metrics('string "IDLE_BEGIN\nstartup:request.volume\t1\t0\t0\t0\t0\nmeasured:sync.volume\t3\t3\t.001\t.002\t.003\ncollector:volume\t3\t1\t4\t0\t0\nIDLE_END"')
        self.assertEqual(metrics['measured:sync.volume']['median'],.001)
        case=dict(cpu=dict(cpu_percent=1,mean_rss_mib=2,peak_rss_mib=3,samples=4),metrics=metrics)
        result=dict(duration=180,warmup=15,cases={'one':case},live={'status':'unavailable'})
        report=idle.render_report(result)
        self.assertIn('startup:request.volume',report)
        self.assertIn('60.00',report)
        self.assertIn('Live baseline unavailable',report)


if __name__=='__main__': unittest.main()
