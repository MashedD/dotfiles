"""Real cached helpers + parsers, isolated caches and fake backends; no account/network."""
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT=Path(__file__).resolve().parents[1]
QUOTA={'rateLimits':{'primary':{'usedPercent':16,'windowDurationMins':300,'resetsAt':1900000000},
                     'secondary':{'usedPercent':67,'windowDurationMins':10080,'resetsAt':1900100000}}}


class StatusHelpers(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.base=Path(self.tmp.name);self.bin=self.base/'bin';self.bin.mkdir()
        self.body=self.base/'body.json';self.counter=self.base/'requests'
        self.backend=self.bin/'backend'
        self.backend.write_text('#!'+sys.executable+'\n'+'''import json,os,sys,time
from pathlib import Path
with open(os.environ['FAKE_COUNTER'],'a') as f:f.write('request\\n')
if os.environ.get('FAKE_BLOCK'):time.sleep(60)
if os.path.basename(sys.argv[0])=='curl':
 print(Path(os.environ['FAKE_BODY']).read_text());sys.exit(0)
for line in sys.stdin:
 data=json.loads(line)
 if data.get('id')==1:print(json.dumps({'id':1,'result':{}}),flush=True)
 elif data.get('id')==2:print(json.dumps({'id':2,'result':json.loads(Path(os.environ['FAKE_BODY']).read_text())}),flush=True)
''')
        self.backend.chmod(0o755);(self.bin/'curl').symlink_to(self.backend)
        self.env=dict(os.environ,HOME=str(self.base),PATH=str(self.bin)+':'+os.environ['PATH'],
                      FAKE_BODY=str(self.body),FAKE_COUNTER=str(self.counter),
                      CODEX_USAGE_TIMEOUT='1',CRYPTO_TIMEOUT='1',
                      CODEX_USAGE_PROXY=str(self.backend),CODEX_USAGE_STDIO=str(self.backend))

    def setup_kind(self,kind):
        self.kind=kind;self.cache=self.base/(kind+'.json')
        self.env['CODEX_USAGE_CACHE' if kind=='codex' else 'CRYPTO_CACHE']=str(self.cache)
        self.script=ROOT/'dotfiles/.local/bin'/('codex-usage' if kind=='codex' else 'crypto-prices')
        self.body.write_text(json.dumps(QUOTA if kind=='codex' else {
            'bitcoin':{'usd':97123.45},'ethereum':{'usd':3456.78},'litecoin':{'usd':123.45}}))

    def run_helper(self,*args):
        result=subprocess.run([str(self.script),*args],env=self.env,capture_output=True,text=True,timeout=8)
        self.assertEqual(result.returncode,0,result.stderr)
        return result.stdout.strip()

    def sample(self):
        fields=self.run_helper('--sidebar-data').split('\t')
        self.assertEqual(fields[0],self.kind+'-v1')
        return fields

    def expire(self):
        data=json.loads(self.cache.read_text());data['fetched_at']=int(time.time())-900
        self.cache.write_text(json.dumps(data));return data

    def requests(self):return len(self.counter.read_text().splitlines()) if self.counter.exists() else 0

    def test_fresh_cache_wire_and_legacy_orphan(self):
        for kind in ('codex','crypto'):
            with self.subTest(kind=kind):
                self.setup_kind(kind)
                orphan=Path(str(self.cache)+'.lock');orphan.mkdir();(orphan/'sentinel').touch()
                sample=self.sample();self.assertEqual(sample[1],'fresh')
                self.assertLess(abs(int(sample[2])-time.time()),3)
                requests=self.requests();self.assertEqual(self.sample(),sample);self.assertEqual(self.requests(),requests)
                self.assertTrue((orphan/'sentinel').exists())
                parser='parse_codex_sample' if kind=='codex' else 'parse_crypto_sample'
                code="local m=dofile('dotfiles/.config/awesome/sidebar-data.lua');local v,e=m.%s(io.read('*a'));assert(v,e);assert(v.source_updated);print(v.five or v.BTC)"%parser
                result=subprocess.run(['lua','-e',code],input='\t'.join(sample)+'\n',cwd=ROOT,capture_output=True,text=True)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertEqual(result.stdout.strip(),'84' if kind=='codex' else '97.123')
                legacy=self.run_helper('--sidebar' if kind=='codex' else '')
                self.assertTrue(legacy.startswith('C ') if kind=='codex' else legacy.startswith('#[fg='))

    def test_failure_lock_contention_and_recovery_preserve_source_age(self):
        for kind in ('codex','crypto'):
            with self.subTest(kind=kind):
                self.setup_kind(kind);self.sample();old=self.expire()
                requests=self.requests()
                with open(str(self.cache)+'.flock','w') as lock:
                    fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
                    sample=self.sample();self.assertEqual(sample[1],'stale');self.assertEqual(int(sample[2]),old['fetched_at'])
                    self.assertEqual(self.requests(),requests)
                # Malformed upstream data cannot replace the last good cache.
                self.body.write_text('{}')
                sample=self.sample();self.assertEqual(sample[1],'stale')
                self.assertEqual(json.loads(self.cache.read_text()),old)
                legacy=self.run_helper('--sidebar' if kind=='codex' else '')
                self.assertTrue(legacy.startswith('C* ') if kind=='codex' else legacy.startswith('STALE '),legacy)
                self.setup_kind(kind);self.assertEqual(self.sample()[1],'fresh')

    def test_invalid_partial_quota_zero_and_fractional_percentages(self):
        self.setup_kind('codex')
        for used,expected in ((100,'0%'),(0,'100%'),(3.2,'96%')):
            data=json.loads(json.dumps(QUOTA));data['rateLimits']['primary']['usedPercent']=used
            self.body.write_text(json.dumps(data));self.cache.unlink(missing_ok=True)
            sample=self.sample();self.assertEqual(sample[1],'fresh');self.assertIn(expected,sample[3])
        for change in ('missing','negative','too-large','string','reset'):
            data=json.loads(json.dumps(QUOTA))
            if change=='missing':del data['rateLimits']['secondary']
            elif change=='reset':data['rateLimits']['primary']['resetsAt']=None
            else:data['rateLimits']['primary']['usedPercent']={'negative':-1,'too-large':101,'string':'16'}[change]
            self.body.write_text(json.dumps(data));self.cache.unlink(missing_ok=True)
            self.assertEqual(self.sample()[1],'unavailable',change)
        data=json.loads(json.dumps(QUOTA));data['rateLimitsByLimitId']={'codex':data['rateLimits']}
        data['rateLimits']={'primary':{'usedPercent':99}}
        self.body.write_text(json.dumps(data));self.assertEqual(self.sample()[1],'fresh')

    def test_future_cache_and_killed_fetch_do_not_wedge_lock(self):
        for kind in ('codex','crypto'):
            with self.subTest(kind=kind):
                self.setup_kind(kind);self.sample()
                data=json.loads(self.cache.read_text());data['fetched_at']=int(time.time())+86400
                self.cache.write_text(json.dumps(data));self.assertEqual(self.sample()[1],'fresh')
                self.assertLess(json.loads(self.cache.read_text())['fetched_at'],data['fetched_at'])
                self.expire();self.env['FAKE_BLOCK']='1';before=self.requests()
                process=subprocess.Popen([str(self.script),'--sidebar-data'],env=self.env,
                    stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
                try:
                    deadline=time.monotonic()+3
                    while self.requests()==before and time.monotonic()<deadline:time.sleep(.02)
                    self.assertGreater(self.requests(),before,'backend did not acquire lock/start')
                finally:
                    os.killpg(process.pid,signal.SIGKILL);process.wait(timeout=3)
                    self.env.pop('FAKE_BLOCK')
                self.assertEqual(self.sample()[1],'fresh')


if __name__=='__main__':unittest.main()
