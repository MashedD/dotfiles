#!/usr/bin/env python3
"""Opt-in profiling: passive live /proc sampling, then isolated fixture sessions."""
import argparse
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
LOCAL = Path(__file__).resolve().parent / 'helpers/awesome-profile.lua'


def proc_sample(pid, proc=Path('/proc')):
    path = proc / str(pid)
    fields = (path / 'stat').read_text().rsplit(')', 1)[1].split()
    if fields[0] in ('Z', 'X'):
        raise ProcessLookupError(pid)
    return dict(pid=int(pid), start=fields[19], ticks=int(fields[11])+int(fields[12]),
                rss=int(fields[21])*os.sysconf('SC_PAGE_SIZE'))


def summarize(samples, hz):
    assert len(samples) >= 2 and hz > 0
    elapsed = samples[-1][0]-samples[0][0]
    assert elapsed > 0
    assert len({(s['pid'], s['start']) for _, s in samples}) == 1, 'PID reused'
    ticks = samples[-1][1]['ticks']-samples[0][1]['ticks']
    assert ticks >= 0
    rss = [s['rss']/1024**2 for _, s in samples]
    return dict(elapsed=elapsed, samples=len(samples), cpu_percent=100*ticks/hz/elapsed,
                mean_rss_mib=statistics.mean(rss), peak_rss_mib=max(rss))


def sample_process(pid, duration, *, clock=time.monotonic, sleep=time.sleep, read=proc_sample, expected_start=None):
    started = clock()
    samples = [(started, read(pid))]
    identity = samples[0][1]['start']
    assert expected_start is None or identity == expected_start, 'Process identity changed before sampling'
    while clock()-started < duration:
        sleep(min(1, max(0, duration-(clock()-started))))
        value = read(pid)
        assert value['start'] == identity, 'Process identity changed; stopped sampling'
        samples.append((clock(), value))
    return summarize(samples, os.sysconf('SC_CLK_TCK'))


def find_live(proc=Path('/proc'), display=None, executable=None):
    display = display if display is not None else os.environ.get('DISPLAY')
    executable = Path(executable or shutil.which('awesome') or '/nonexistent').resolve()
    matches = []
    if not display:
        return matches
    for path in proc.iterdir():
        if not path.name.isdigit():
            continue
        try:
            if path.stat().st_uid != os.getuid() or (path/'comm').read_text().strip() != 'awesome':
                continue
            before = proc_sample(path.name, proc)
            if (path/'exe').resolve(strict=True) != executable:
                continue
            cmd = (path/'cmdline').read_bytes().split(b'\0')[0].decode()
            if Path(cmd).name != 'awesome':
                continue
            if ('DISPLAY='+display).encode() not in (path/'environ').read_bytes().split(b'\0'):
                continue
            after = proc_sample(path.name, proc)
            if before['start'] == after['start']:
                matches.append(after)
        except (OSError, ValueError, IndexError):
            pass
    return matches


def replace_once(source, old, new):
    assert source.count(old) == 1, f'Instrumentation anchor changed: {old}'
    return source.replace(old, new, 1)


def cached_clock(source):
    """Private candidate generated from the unchanged production drawing primitives."""
    start='    clock.draw = function(_, _, cr, width, height)\n'
    header, rest=source.split(start,1)
    body, tail=rest.split('    return clock\n',1)
    setup, paint=body.split('        cr:set_line_cap(cairo.LineCap.ROUND)\n',1)
    face, hands=paint.split('        local function hand(',1)
    helper=json.dumps(str(ROOT/'tests/helpers/awesome-clock-cache.lua'))
    candidate=(header+'    local function face(cr,width,height)\n'+setup+
               '        cr:set_line_cap(cairo.LineCap.ROUND)\n'+face+'    end\n'+
               '    local cache=dofile('+helper+').new(cairo,face,{\n'+
               '        now=function() return require("lgi").GLib.get_monotonic_time()/1000000 end,\n'+
               '        event=function(...) if _G.__idle_prof then __idle_prof.cache_event(...) end end,\n'+
               '    })\n    clock._face_cache=cache\n'+
               '    clock.draw = function(_, context, cr, width, height)\n'+setup+
               '        local face_radius=radius-4\n'+
               '        if not cache.paint(context,cr,width,height) then return end\n'+
               '        local function hand('+hands+'    return clock\n'+tail)
    return replace_once(candidate,'        clock:buttons({}); digital:buttons({})',
                        '        clock._face_cache.destroy()\n        clock:buttons({}); digital:buttons({})')


def instrument(config, rendering=False):
    rc = config/'rc.lua'
    prefix='_G.__idle_prof=dofile(' + json.dumps(str(LOCAL)) + '); __idle_prof.install_spawn(); '
    if rendering: prefix+='__idle_prof.install_rendering(); '
    rc.write_text(prefix+'\n'+rc.read_text())
    path = config/'sidebar-data.lua'
    source = path.read_text()
    source = replace_once(source, 'local function notify(c)', 'local function notify_impl(c)')
    source = replace_once(source, '    local function publish_if_changed',
                          '    local notify = __idle_prof.notify(notify_impl)\n    local function publish_if_changed')
    source = replace_once(source, '    function service.define(name, interval, fetch, max_age)',
                          '    function service.define(name, interval, fetch, max_age)\n        fetch = __idle_prof.fetch(name, fetch)')
    source = replace_once(source, 'collectors[name] = {interval = interval, max_age = max_age,\n            fetch = fetch, listeners = {}, state = {}, generation = 0}',
                          'collectors[name] = {name=name, interval = interval, max_age = max_age, fetch = fetch, listeners = {}, state = {}, generation = 0}\n        __idle_prof.collectors[name] = collectors[name]')
    source = replace_once(source, '        if c.pending then return end',
                          '        if c.pending then __idle_prof.count("pending."..name); return end')
    path.write_text(source)
    path = config/'sidebar.lua'
    source = path.read_text()
    for name in ('todo', 'calendar'):
        anchor = f'    s.sidebar_{name}_timer = gears.timer {{'
        source = replace_once(source, anchor,
            f'    refresh_{name} = __idle_prof.wrap("document.{name}.screen"..s.index, refresh_{name})\n'+anchor)
    path.write_text(source)


def prepare(directory, profiled, rendering=False, cached=False):
    home = directory/'home'
    config = home/'.config/awesome'
    shutil.copytree(ROOT/'dotfiles/.config/awesome', config)
    # Deterministic local Trash directory; no session GVfs service or user Trash.
    data = config/'sidebar-data.lua'
    data.write_text(replace_once(data.read_text(), 'Gio.File.new_for_uri("trash:///")',
                                'Gio.File.new_for_path(os.getenv("HOME").."/.local/share/Trash/files")'))
    if cached:
        path=config/'sidebar-clock.lua'
        path.write_text(cached_clock(path.read_text()))
    if profiled:
        instrument(config, rendering)
    for folder in ['Documents', '.local/bin', '.local/share/wallpapers', '.local/share/applications',
                   '.local/state/awesome', 'Pictures/Wallpapers']:
        (home/folder).mkdir(parents=True, exist_ok=True)
    trash = home/'.local/share/Trash/files'
    trash.mkdir(parents=True)
    for index in range(32):
        (trash/str(index)).write_text('fixture')
    (home/'Documents/todo.md').write_text('## Sidebar\n' + ''.join(f'- Fixture task {i}\n' for i in range(5)))
    (home/'Documents/calendar.md').write_text('2030-01-01 12:00 Fixture event\n')
    for name in ['aurora-cabin.png']:
        shutil.copy2(ROOT/'dotfiles/.local/share/wallpapers'/name, home/'.local/share/wallpapers'/name)
    commands = {
        'curl': 'printf \'%s\\n\' \'{"current":{"temperature_2m":12,"apparent_temperature":10,"weather_code":3,"wind_speed_10m":9}}\'',
        'wpctl': 'echo "Volume: 0.42"',
        'playerctl': 'echo "Fixture artist — Fixture title"',
        'crypto-prices': 'echo \'#[fg=#006400]BTC #[fg=#55ff99,bold]$97.123 #[fg=#006400]ETH #[fg=#55ff99,bold]$3.456 #[fg=#006400]LTC #[fg=#55ff99,bold]$123,45\'',
        'codex-usage': 'printf \'%s\\t%s\\n\' \'C 5h #[fg=#55ff99]84%#[fg=#006400]@#[fg=#55ff99]Sat 13:46 7d #[fg=#55ff99]33%#[fg=#006400]@#[fg=#55ff99]Wed 06:41\' \'fixture reset dates\'',
    }
    for name, body in commands.items():
        path = home/'.local/bin'/name
        path.write_text('#!/bin/sh\n'+body+'\n')
        path.chmod(0o755)
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home/'.config'),
               XDG_DATA_HOME=str(home/'.local/share'), XDG_STATE_HOME=str(home/'.local/state'),
               XDG_CACHE_HOME=str(home/'.cache'), XDG_RUNTIME_DIR=str(directory),
               PATH=str(home/'.local/bin')+':'+os.environ['PATH'], AWESOME_TEST_MODE='1',
               AWESOME_TEST_WEATHER='1', NO_AT_BRIDGE='1', GIO_USE_VFS='local')
    for name in ['DISPLAY', 'XAUTHORITY', 'XSS_SLEEP_LOCK_FD', 'DESKTOP_STARTUP_ID']:
        env.pop(name, None)
    return config, env


def parse_metrics(output):
    body = output.split('IDLE_BEGIN\n', 1)[1].split('\nIDLE_END', 1)[0]
    metrics = {}
    for line in body.splitlines():
        fields=line.split('\t')
        key, count, samples, median, p95, maximum = fields[:6]
        metrics[key] = dict(count=int(count), samples=int(samples), median=float(median),
                            p95=float(p95), maximum=float(maximum),total=float(fields[6]) if len(fields)>6 else 0)
    return metrics


def run_isolated(command):
    """Own a fresh process group; interruption cannot leave private servers behind."""
    env = dict(os.environ, AWESOME_IDLE_PRIVATE='1')
    process = subprocess.Popen(command, env=env, start_new_session=True)
    try:
        status = process.wait()
        if status:
            raise subprocess.CalledProcessError(status, command)
    except BaseException:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        raise


def private_case(args):
    assert os.environ.get('AWESOME_IDLE_PRIVATE') == '1', 'Internal case requires the isolated audit launcher'
    def interrupted(signum, frame):
        raise SystemExit('Private audit interrupted')
    signal.signal(signal.SIGTERM, interrupted)
    with tempfile.TemporaryDirectory(prefix='awesome-idle-') as name:
        directory = Path(name)
        profiled = args.case != 'control'
        config, env = prepare(directory, profiled, args.render_case is not None, args.render_case=='cached')
        processes = []
        with (directory/'awesome.log').open('w') as log:
            def client(code):
                result = subprocess.run(['awesome-client', code], env=env, capture_output=True, text=True, timeout=5)
                assert result.returncode == 0 and 'Error' not in result.stdout, result.stdout+result.stderr
                return result.stdout
            try:
                server = subprocess.Popen(['Xvfb', '-displayfd', '1', '-screen', '0', '2560x800x24',
                                           '-nolisten', 'tcp', '-ac'], stdout=subprocess.PIPE, stderr=log, text=True)
                processes.append(server)
                number = server.stdout.readline().strip()
                assert number.isdigit(), 'Xvfb startup failed'
                env['DISPLAY'] = ':'+number
                wm = subprocess.Popen(['awesome', '-c', str(config/'rc.lua')], env=env, stdout=log, stderr=log)
                processes.append(wm)
                deadline = time.monotonic()+15
                while True:
                    assert wm.poll() is None, (directory/'awesome.log').read_text()
                    try:
                        assert 'true' in client('return screen[1].sidebar ~= nil')
                        break
                    except (AssertionError, subprocess.TimeoutExpired):
                        assert time.monotonic() < deadline, 'Awesome startup timeout'
                        time.sleep(0.1)
                setup = 'screen[1]:fake_resize(0,0,1280,800); '
                if args.screens == 2 or args.case == 'two':
                    setup += 'screen.fake_add(1280,0,1280,800); '
                setup += 'for s in screen do for _,section in pairs(s.sidebar_sections) do if section.collapsed then section.toggle_action() end end end; '
                if args.render_case == 'digital':
                    setup += 'for s in screen do s.sidebar_components.clock.set_mode("text") end; '
                elif args.render_case == 'hidden':
                    setup += 'for s in screen do s.sidebar_mode=0; s.selected_tag:emit_signal("property::selected"); s.sidebar.visible=false; s.sidebar_scrollbar_panel.visible=false; s.panel_clock_container.visible=true; s.sidebar:struts({left=0,right=0,top=0,bottom=0}) end; '
                if profiled:
                    if args.render_case is not None: setup += '__idle_prof.bind_rendering(); '
                    setup += '__idle_prof.phase="warmup"; '
                setup += 'return screen.count()'
                client(setup)
                time.sleep(args.warmup)
                if profiled:
                    client('__idle_prof.begin()')
                cpu = sample_process(wm.pid, args.duration)
                output = client('return __idle_prof.finish()') if profiled else ''
                topology = client('local r={}; for s in screen do local n=0; for _ in pairs(s.sidebar_data.collectors.volume.listeners) do n=n+1 end; r[#r+1]=s.index..":"..s.geometry.width.."x"..s.geometry.height..":volume_listeners="..n end; return table.concat(r,",")')
                if args.screens == 2 or args.case == 'two':
                    assert 'true' in client('return screen[1].sidebar_data == screen[2].sidebar_data'), 'Collectors not shared'
                metrics = parse_metrics(output) if profiled else {}
                if profiled:
                    expected_listeners = 2 if args.screens==2 or args.case == 'two' else 1
                    for key, value in metrics.items():
                        if key.startswith('collector:'):
                            assert value['samples'] == expected_listeners, f'Unexpected subscriptions: {key}'
                log_text=(directory/'awesome.log').read_text()
                if args.render_case is not None:
                    assert not re.search(r'stack traceback:|Error during a protected call|Error while drawing',log_text),log_text
                result = dict(cpu=cpu, metrics=metrics, topology=topology.strip(), log=log_text)
                if args.render_case=='cached':
                    assert 'true' in client('for s in screen do local c=s.sidebar_components.clock; for _,b in ipairs(c.clock:buttons()) do if b.button==1 then b:emit_signal("press");break end end; if c.mode~="text" or c.clock.visible then return false end; for _,b in ipairs(c.digital:buttons()) do if b.button==1 then b:emit_signal("press");break end end; if c.mode~="analog" or not c.clock.visible then return false end end; return true')
                    result['cache_lifecycle']=True
                    assert 'true' in client('local caches={}; for s in screen do caches[#caches+1]=s.sidebar_clock._face_cache end; if screen[2] then screen[2]:fake_remove() end; screen[1].sidebar_components.clock.destroy(); for _,c in ipairs(caches) do if c.bytes~=0 then return false end end; return true')
                client('awesome.quit()')
                assert wm.wait(timeout=5) == 0
                Path(args.result).write_text(json.dumps(result, indent=2)+'\n')
            except BaseException:
                print((directory/'awesome.log').read_text(), file=sys.stderr)
                raise
            finally:
                for process in reversed(processes):
                    if process.poll() is None:
                        process.terminate()
                        try:
                            process.wait(timeout=3)
                        except subprocess.TimeoutExpired:
                            process.kill(); process.wait()


def render_report(result):
    lines = ['# Awesome idle performance audit', '',
             f'Measured {result["duration"]} seconds per case, after {result["warmup"]} seconds private warm-up.', '',
             '| Case | CPU (% of one core) | Mean RSS MiB | Peak RSS MiB | Samples |',
             '| --- | ---: | ---: | ---: | ---: |']
    for name, case in result['cases'].items():
        c = case['cpu']
        lines.append(f'| {name} | {c["cpu_percent"]:.3f} | {c["mean_rss_mib"]:.2f} | {c["peak_rss_mib"]:.2f} | {c["samples"]} |')
    if 'cpu' in result['live']:
        c=result['live']['cpu']
        lines.append(f'| live (ordinary use) | {c["cpu_percent"]:.3f} | {c["mean_rss_mib"]:.2f} | {c["peak_rss_mib"]:.2f} | {c["samples"]} |')
    else:
        lines += ['', 'Live baseline unavailable: '+result['live']['status']]
    lines += ['', '## Private timing and counts', '',
              '| Case | Metric | Count | Timed samples | Median ms | p95 ms | Max ms |',
              '| --- | --- | ---: | ---: | ---: | ---: | ---: |']
    for name, case in result['cases'].items():
        for key, value in sorted(case['metrics'].items()):
            if key.startswith('collector:'):
                continue
            lines.append(f'| {name} | {key} | {value["count"]} | {value["samples"]} | {value["median"]*1000:.3f} | {value["p95"]*1000:.3f} | {value["maximum"]*1000:.3f} |')
    lines += ['', '## Timer-derived expectations', '', '| Collector | Interval s | Expected measured requests (±1 boundary) |', '| --- | ---: | ---: |']
    for key, value in sorted(result['cases']['one']['metrics'].items()):
        if key.startswith('collector:'):
            lines.append(f'| {key[10:]} | {value["count"]} | {result["duration"]/value["count"]:.2f} |')
    return '\n'.join(lines)+'\n'


def validate_clock_render(lua='lua5.3'):
    if not shutil.which(lua) or not shutil.which('compare'):
        raise RuntimeError('Clock rendering comparison requires '+lua+' with lgi and ImageMagick compare')
    with tempfile.TemporaryDirectory(prefix='awesome-clock-render-') as name:
        directory=Path(name)
        source=(ROOT/'dotfiles/.config/awesome/sidebar-clock.lua').read_text()
        for filename,text in [('baseline.lua',source),('candidate.lua',cached_clock(source))]:
            text=replace_once(text,'return M\n','M._test_clock=analog_clock; return M\n')
            (directory/filename).write_text(text)
        fixture=subprocess.run([lua,str(ROOT/'tests/helpers/render-clock.lua'),str(directory/'baseline.lua'),
                                str(directory/'candidate.lua'),str(directory),str(ROOT/'tests/helpers/awesome-clock-cache.lua')],capture_output=True,text=True)
        assert fixture.returncode==0,fixture.stdout+fixture.stderr
        failures=[];peak=0;count=0
        for image in directory.glob('*-A.png'):
            other=image.with_name(image.name.replace('-A.png','-B.png'))
            result=subprocess.run(['compare','-channel','RGBA','-metric','PAE',str(image),str(other),'null:'],
                                  capture_output=True,text=True,timeout=5)
            assert result.returncode in (0,1),result.stderr
            match=re.search(r'\(([0-9.eE+-]+)\)',result.stderr)
            assert match,result.stderr
            value=float(match[1]);peak=max(peak,value);count+=1
            if value>1/255+1e-6: failures.append(dict(case=image.stem,peak=value))
        return dict(passed=not failures,comparisons=count,maximum_channel_error=peak,
                    tolerance=1/255,failures=failures,fixture=fixture.stdout.strip())


def rendering_gate(cases):
    decision={}
    for screens in (1,2):
        def pair(kind): return [cases[f'{screens}-{kind}-{i}'] for i in (1,2)]
        a,b=pair('baseline'),pair('cached')
        def draw_cost(case):
            return sum(v['total'] for k,v in case['metrics'].items() if k.startswith('measured:redraw.sidebar.screen'))/case['cpu']['elapsed']
        def clock_median(group):
            return statistics.median(v['median'] for case in group for key,v in case['metrics'].items()
                                     if key.startswith('measured:draw.clock.screen'))
        base=statistics.mean(map(draw_cost,a)); candidate=statistics.mean(map(draw_cost,b))
        clock_a,clock_b=clock_median(a),clock_median(b)
        cpus=[c['cpu']['cpu_percent'] for c in a]
        cpu_delta=statistics.mean(c['cpu']['cpu_percent'] for c in b)-statistics.mean(cpus)
        heartbeat_a=[c['metrics']['measured:heartbeat.lateness']['p95'] for c in a]
        heartbeat_b=[c['metrics']['measured:heartbeat.lateness']['p95'] for c in b]
        # A repeatable >5ms p95 increase beyond baseline variation rejects shipment.
        heartbeat_regression=min(heartbeat_b)>max(heartbeat_a)+max(.005,abs(heartbeat_a[0]-heartbeat_a[1]))
        result=dict(sidebar_reduction=1-candidate/base if base else 0,
                    clock_reduction=1-clock_b/clock_a if clock_a else 0,
                    baseline_sidebar_seconds_per_second=base,cached_sidebar_seconds_per_second=candidate,
                    cpu_delta=cpu_delta,cpu_allowance=max(.2,abs(cpus[0]-cpus[1])),
                    heartbeat_regression=heartbeat_regression)
        result['passed']=(result['sidebar_reduction']>=.1 and result['clock_reduction']>=.25
                          and cpu_delta<=result['cpu_allowance'] and not heartbeat_regression)
        decision[str(screens)]=result
    return decision


def rendering_matrix(args):
    visual=validate_clock_render()
    print('Private pixel comparison: '+('passed' if visual['passed'] else 'rejected candidate'),flush=True)
    cases={}
    with tempfile.TemporaryDirectory(prefix='awesome-render-results-') as name:
        for screens in (1,2):
            order=[('control',1),('baseline',1),('cached',1),('cached',2),('baseline',2),('digital',1),('hidden',1)]
            for mode,index in order:
                case=f'{screens}-{mode}-{index}'
                path=Path(name)/(case+'.json')
                run_isolated(['dbus-run-session','--',sys.executable,str(Path(__file__).resolve()),
                              '--case','control' if mode=='control' else 'one',
                              '--render-case',mode,'--screens',str(screens),
                              '--duration',str(args.duration),'--warmup',str(args.warmup),'--result',str(path)])
                cases[case]=json.loads(path.read_text())
                print('Completed '+case,flush=True)
    result=dict(duration=args.duration,warmup=args.warmup,cases=cases,gate=rendering_gate(cases),visual=visual,
                versions=dict(python=platform.python_version(),kernel=platform.release(),
                              awesome=subprocess.check_output(['awesome','-v'],text=True)))
    result['ship']=visual['passed'] and all(value['passed'] for value in result['gate'].values())
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    print('Saved '+str(args.output))
    print(json.dumps(result['gate'],indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--duration', type=float)
    parser.add_argument('--warmup', type=float)
    parser.add_argument('--skip-live', action='store_true')
    parser.add_argument('--output', type=Path, default=Path('/tmp/awesome-idle-audit.json'))
    parser.add_argument('--case', choices=['control', 'one', 'two'], help=argparse.SUPPRESS)
    parser.add_argument('--result', help=argparse.SUPPRESS)
    parser.add_argument('--rendering', action='store_true', help='Private rendering A-B-B-A matrix; no live sampling')
    parser.add_argument('--render-case', choices=['baseline','cached','digital','hidden','control'], help=argparse.SUPPRESS)
    parser.add_argument('--screens', type=int, choices=[1,2], default=1, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.duration is None: args.duration=60 if args.rendering else 180
    if args.warmup is None: args.warmup=10 if args.rendering else 15
    if args.duration <= 0 or args.warmup < 0 or not math.isfinite(args.duration+args.warmup):
        parser.error('Durations must be finite, duration > 0 and warmup >= 0')
    if args.case:
        private_case(args)
        return
    for command in ['awesome', 'awesome-client', 'Xvfb', 'dbus-run-session', 'timeout']:
        if not shutil.which(command):
            parser.error('Required command not found: '+command)
    if args.rendering:
        rendering_matrix(args)
        return
    live = dict(status='explicitly skipped')
    if not args.skip_live:
        matches = find_live()
        if len(matches) != 1:
            live = dict(status=f'Expected one unambiguous Awesome process; found {len(matches)}')
        else:
            try:
                live = dict(cpu=sample_process(matches[0]['pid'], args.duration, expected_start=matches[0]['start']), status='passive /proc observation')
            except (OSError, AssertionError, ValueError, IndexError) as error:
                live = dict(status='Stopped passive sampling: '+str(error))
    result = dict(duration=args.duration, warmup=args.warmup, live=live, cases={},
                  versions=dict(python=platform.python_version(), kernel=platform.release(),
                                awesome=subprocess.check_output(['awesome', '-v'], text=True)))
    with tempfile.TemporaryDirectory(prefix='awesome-idle-results-') as name:
        for case in ['control', 'one', 'two']:
            path = Path(name)/(case+'.json')
            run_isolated(['dbus-run-session', '--', sys.executable, str(Path(__file__).resolve()),
                            '--case', case, '--duration', str(args.duration), '--warmup', str(args.warmup),
                            '--result', str(path)])
            result['cases'][case] = json.loads(path.read_text())
            print('Completed '+case, flush=True)
    args.output.write_text(json.dumps(result, indent=2)+'\n')
    args.output.with_suffix('.md').write_text(render_report(result))
    print('Saved '+str(args.output))


if __name__ == '__main__':
    main()
