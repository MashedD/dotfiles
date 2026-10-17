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
            breakdown, _ = idle.prepare(directory/'breakdown', True, rendering=True, breakdown=True)
            self.assertIn('__idle_prof.install_rendering_breakdown()', (breakdown/'rc.lua').read_text())
            attribution, _ = idle.prepare(directory/'attribution', True, rendering=True, attribution=True)
            self.assertIn('__idle_prof.install_rendering_attribution()', (attribution/'rc.lua').read_text())
            self.assertIn('__idle_prof.widget_update(widget, property', (attribution/'sidebar.lua').read_text())
            self.assertNotIn('__idle_prof.widget_update', (idle.ROOT/'dotfiles/.config/awesome/sidebar.lua').read_text())
            self.assertIn('P.drawables[drawable]', (idle.LOCAL).read_text())
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

    def test_rendering_mode_never_samples_live(self):
        with patch.object(idle.sys,'argv',['audit','--rendering']), \
             patch.object(idle.shutil,'which',return_value='/private/stub'), \
             patch.object(idle,'find_live',side_effect=AssertionError('Live access forbidden')), \
             patch.object(idle,'sample_process',side_effect=AssertionError('Live access forbidden')), \
             patch.object(idle,'rendering_matrix') as matrix:
            idle.main()
        self.assertEqual(matrix.call_args.args[0].duration,60)
        self.assertEqual(matrix.call_args.args[0].warmup,10)

    def test_render_breakdown_mode_never_samples_live(self):
        with patch.object(idle.sys,'argv',['audit','--render-breakdown']), \
             patch.object(idle.shutil,'which',return_value='/private/stub'), \
             patch.object(idle,'find_live',side_effect=AssertionError('Live access forbidden')), \
             patch.object(idle,'sample_process',side_effect=AssertionError('Live access forbidden')), \
             patch.object(idle,'rendering_breakdown_matrix') as matrix:
            idle.main()
        self.assertEqual(matrix.call_args.args[0].duration,60)
        self.assertEqual(matrix.call_args.args[0].warmup,10)

    def test_render_attribution_mode_never_samples_live(self):
        with patch.object(idle.sys,'argv',['audit','--render-attribution']), \
             patch.object(idle.shutil,'which',return_value='/private/stub'), \
             patch.object(idle,'find_live',side_effect=AssertionError('Live access forbidden')), \
             patch.object(idle,'sample_process',side_effect=AssertionError('Live access forbidden')), \
             patch.object(idle,'rendering_attribution_matrix') as matrix:
            idle.main()
        self.assertEqual(matrix.call_args.args[0].duration,60)
        self.assertEqual(matrix.call_args.args[0].warmup,10)

    def test_attribution_report_and_observer_gate(self):
        cases={}
        for screens in (1,2):
            for mode in ('baseline','attribution'):
                for index in (1,2):
                    metrics={'measured:heartbeat.lateness':dict(p95=.002)}
                    for screen in range(1,screens+1):
                        metrics[f'measured:redraw.sidebar.screen{screen}']=dict(total=6,count=100)
                    if mode=='attribution':
                        metrics['measured:draw.depth16.screen1.system-status']=dict(
                            total=.6,count=60,samples=60,median=.01,p95=.02,maximum=.03)
                        if index==1:
                            metrics['measured:update.screen1.system-status.text.changed']=dict(
                                total=0,count=4,samples=0,median=0,p95=0,maximum=0)
                    cases[f'{screens}-{mode}-{index}']=dict(
                        cpu=dict(elapsed=60,cpu_percent=5),metrics=metrics)
        gate=idle.attribution_observer_gate(cases)
        self.assertTrue(gate['1']['passed'] and gate['2']['passed'])
        report=idle.attribution_report(dict(duration=60,warmup=10,cases=cases))
        self.assertIn('screen1.system-status',report)
        self.assertIn('system-status.text.changed',report)
        self.assertNotIn('private widget content',report)

    def test_breakdown_report_uses_only_aggregated_metrics(self):
        cases={}
        for screens in (1,2):
            for mode in ('baseline','breakdown'):
                for index in (1,2):
                    metrics={
                        'measured:heartbeat.lateness':dict(total=0,count=100,samples=100,median=.001,p95=.002,maximum=.01),
                    }
                    for screen in range(1,screens+1):
                        metrics[f'measured:redraw.sidebar.screen{screen}']=dict(total=6.0,count=100,samples=100,median=.01,p95=.02,maximum=.03)
                        metrics[f'measured:paint.background.draw.screen{screen}']=dict(total=.2,count=100,samples=100,median=.001,p95=.002,maximum=.01)
                        if mode=='breakdown':
                            prefix=f'measured:hierarchy.sidebar.screen{screen}'
                            metrics[prefix+'.total']=dict(total=4.0,count=100,samples=100,median=.01,p95=.02,maximum=.03)
                            metrics[prefix+'.node.wibox.textbox.depth2.exclusive']=dict(total=2.0,count=10,samples=10,median=.1,p95=.2,maximum=.3)
                            metrics[f'measured:draw.callback.sidebar.screen{screen}.wibox.textbox.depth2']=dict(total=1.5,count=10,samples=10,median=.1,p95=.2,maximum=.3)
                    cases[f'{screens}-{mode}-{index}']=dict(cpu=dict(elapsed=60,cpu_percent=5),metrics=metrics)
        rates=idle.breakdown_rates(cases['2-breakdown-1'],2)
        self.assertAlmostEqual(rates['redraw'],.2)
        self.assertAlmostEqual(rates['hierarchy'],4/30)
        callbacks=idle.top_callback_metrics(cases['2-breakdown-1'],2)
        self.assertAlmostEqual(callbacks[0][0],3/60)
        report=idle.rendering_breakdown_report(dict(duration=60,warmup=10,cases=cases))
        self.assertIn('wibox.textbox.depth2',report)
        self.assertIn('Outer minus hierarchy',report)
        self.assertIn('not a measurement of native flush time',report)
        self.assertNotIn('fixture private text',report)

    def test_rendering_gate_requires_both_topologies_and_cpu_safety(self):
        cases={}
        for screens in (1,2):
            for kind in ('baseline','cached'):
                for index in (1,2):
                    cached=kind=='cached'
                    cases[f'{screens}-{kind}-{index}']=dict(cpu=dict(elapsed=60,cpu_percent=5),metrics={
                        'measured:redraw.sidebar.screen1':dict(total=4.8 if cached else 6),
                        'measured:draw.clock.screen1':dict(median=.005 if cached else .01),
                        'measured:heartbeat.lateness':dict(p95=.001),
                    })
        gate=idle.rendering_gate(cases)
        self.assertTrue(all(value['passed'] for value in gate.values()))
        cases['2-cached-1']['cpu']['cpu_percent']=6
        cases['2-cached-2']['cpu']['cpu_percent']=6
        self.assertFalse(idle.rendering_gate(cases)['2']['passed'])
        self.assertTrue(idle.rendering_gate(cases)['1']['passed'])
        cases['1-cached-1']['metrics']['measured:redraw.sidebar.screen1']['total']=6
        cases['1-cached-2']['metrics']['measured:redraw.sidebar.screen1']['total']=6
        self.assertFalse(idle.rendering_gate(cases)['1']['passed'])

    def test_cached_candidate_is_private_and_keeps_production_untouched(self):
        source=(idle.ROOT/'dotfiles/.config/awesome/sidebar-clock.lua').read_text()
        candidate=idle.cached_clock(source)
        self.assertIn('clock._face_cache=cache',candidate)
        self.assertIn('clock._face_cache.destroy()',candidate)
        self.assertNotIn('_face_cache',source)
        self.assertEqual(source,(idle.ROOT/'dotfiles/.config/awesome/sidebar-clock.lua').read_text())
        metrics=idle.parse_metrics('IDLE_BEGIN\nmeasured:redraw.sidebar.screen1\t2\t2\t.01\t.02\t.02\t.03\nIDLE_END')
        self.assertEqual(metrics['measured:redraw.sidebar.screen1']['total'],.03)

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
