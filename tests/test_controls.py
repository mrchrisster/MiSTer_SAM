"""Linux integration: actual SAM countdown + actual Monitor HTTP methods, isolated files."""
import ast
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import types
import unittest
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse
from urllib.request import Request, urlopen
from urllib.error import HTTPError

HERE = Path(__file__).resolve().parent
from paths import PACKAGE, MONITOR_SERVER
TEMP = tempfile.TemporaryDirectory(prefix='sam-control-test-')
ROOT = Path(TEMP.name)
os.environ.update(SAM_CONTROL_ROOT=str(ROOT/'handoff'), SAM_CONTROL_STORE=str(ROOT/'journal'), SAM_CONTROL_STATE=str(ROOT/'SAM_state'))
import sys
sys.path.insert(0,str(PACKAGE/'.MiSTer_SAM/control'))
import sam_control as control
from sam_status import read_sam_status


def function(name):
    root=PACKAGE/'.MiSTer_SAM'
    if name.startswith('sam_display_'): path=root/'control/state.sh'
    elif name in {'sam_apply_exclusions','sam_is_excluded','ignoregame'}: path=root/'lib/filter.sh'
    elif name=='exit_sam': path=root/'lib/lifecycle.sh'
    else: path=root/'lib/engine.sh'
    text=path.read_text()
    import re
    match=re.search(r'^(?:function )?'+name+r'\(\)\s*\{',text,re.M)
    end=re.search(r'^}',text[match.end():],re.M)
    return text[match.start():match.end()+end.end()]+'\n'


def handler():
    tree = ast.parse(MONITOR_SERVER.read_text())
    cls = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == 'MiSTerStatusHandler')
    methods = [n for n in cls.body if isinstance(n, ast.FunctionDef) and n.name in {'do_GET','do_POST','get_state_snapshot','send_json_response','send_error_response'}]
    shell = ast.ClassDef(name='Handler', bases=[ast.Name(id='Base',ctx=ast.Load())], keywords=[], body=methods, decorator_list=[])
    state = dict(seq=201, core='SNES', core_raw='SNES', system_name='SNES', game_system='SNES', game='test', game_path=str(ROOT/'Game = Pokémon.sfc'), is_arcade=False, rom_details_stale=False, rom_details=None, last_event='', updated_at=0)
    ns = dict(Base=BaseHTTPRequestHandler,_state=state,_state_lock=threading.Lock(),SERVER_VERSION='test',json=json,time=time,urlparse=urlparse,_requests_count=0,sam_control=control,read_sam_status=lambda:read_sam_status(control.STATE))
    exec(compile(ast.fix_missing_locations(ast.Module(body=[shell],type_ignores=[])),'handler','exec'),ns)
    ns['Handler'].log_message=lambda *args:None
    return ns['Handler'], state


@unittest.skipUnless(Path('/proc/self/stat').exists(), 'Linux procfs required')
class Integration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.Handler, cls.state = handler()
        cls.server = ThreadingHTTPServer(('127.0.0.1',0),cls.Handler)
        cls.url='http://127.0.0.1:'+str(cls.server.server_port)
        control.MONITOR=cls.url+'/status/snapshot'
        os.environ['SAM_CONTROL_MONITOR']=control.MONITOR
        threading.Thread(target=cls.server.serve_forever,daemon=True).start()
    @classmethod
    def tearDownClass(cls): cls.server.shutdown(); cls.server.server_close()
    def setUp(self):
        for file in (ROOT/'handoff').glob('*'):
            if file.is_file():file.unlink()
        (ROOT/'lists').mkdir(exist_ok=True); (ROOT/'session').mkdir(exist_ok=True)
        for file in (ROOT/'lists').glob('*'):file.unlink()
        self.state['seq']=201
        self.state['game_path']=str(ROOT/'Game = Pokémon.sfc')
        Path(self.state['game_path']).touch()
        (ROOT/'returned').unlink(missing_ok=True)
        script='\n'.join(function(n) for n in ['sam_display_read','sam_display_write','sam_display_publish','sam_display_off','sam_apply_exclusions','sam_is_excluded','ignoregame','exit_sam','run_countdown_timer'])
        script+='''
sam_cleanup() { :; }; tty_exit() { :; }
monitorenable=yes; sam_status_enabled=yes; sam_generation=1; m82=no; samvideo=no; mute=no; gametimer=4
sam_display_state_file="$SAM_CONTROL_STATE"
sam_display_owner_start=""
gamelistpath="$TEST_ROOT/lists"; ignorepath="$TEST_ROOT/lists"; gamelistpathtmp="$TEST_ROOT/session"
sam_schedule_preparation() { :; }
sam_service() { :; }
sam_emit() {
    local event="$1"; shift
    case "$event" in
        display_read) sam_display_read "$@" ;;
        display_publish) sam_display_publish "$@" ;;
        display_off) sam_display_off "$@" ;;
        controls_ready) sam_control_publish "$@" ;;
        countdown_start) sam_control_publish 1 ;;
        countdown_tick) sam_control_tick "$@" ;;
    esac
}
source "$TEST_PACKAGE/.MiSTer_SAM/control/handler.sh"
sam_display_game='test'; sam_display_rom_path="$TEST_GAME"; sam_display_core=snes; sam_display_setname=''
sam_display_write yes normal 4 "$EPOCHSECONDS"
run_countdown_timer < <(sleep 30)
printf '%s' "$SAM_ACTION" > "$TEST_ROOT/returned"
while true; do sleep 1; done
'''
        env=dict(os.environ,TEST_ROOT=str(ROOT),TEST_HERE=str(HERE),TEST_PACKAGE=str(PACKAGE),TEST_GAME=self.state['game_path'],SAM_CONTROL_HELPER=str(PACKAGE/'.MiSTer_SAM/control/sam_control.py'))
        self.child=subprocess.Popen(['bash','-c',script],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,start_new_session=True)
        self.addCleanup(self.stop)
        self.wait(lambda:control.advertised()['controls'])
    def stop(self):
        import signal
        try: os.killpg(self.child.pid,signal.SIGTERM)
        except ProcessLookupError: pass
        self.child.communicate(timeout=3)
    def wait(self,predicate):
        deadline=time.monotonic()+5
        while time.monotonic()<deadline:
            if predicate():return
            if self.child.poll() is not None: self.fail(self.child.stderr.read().decode())
            time.sleep(.05)
        self.fail('Timed out waiting for SAM fixture')
    def get(self,query=''):
        with urlopen(self.url+'/status/snapshot'+query) as r:return json.load(r)
    def request(self,action='pause',**kwargs):
        return dict(action=action,expected_seq=201,game_path=self.state['game_path'],request_id=str(uuid.uuid4()),**kwargs)
    def post(self,request,headers=None):
        data=json.dumps(request).encode() if not isinstance(request,bytes) else request
        try:
            with urlopen(Request(self.url+'/control/sam',data=data,headers=headers or {'Content-Type':'application/json; charset=utf-8'}),timeout=8) as r:return r.status,json.load(r)
        except HTTPError as e:
            raw=e.read()
            try: body=json.loads(raw)
            except ValueError: body={'error':raw.decode()}
            return e.code,body
    def test_pause_resume_past_old_deadline_and_unchanged(self):
        old=self.get(); request=self.request()
        self.assertEqual(self.post(request),(200,{'ok':True}))
        snap=self.get('?seq=201'); remaining=snap['sam']['remaining_seconds']
        self.assertTrue(snap['unchanged']);self.assertTrue(snap['sam']['active']);self.assertTrue(snap['sam']['paused']);self.assertIsNone(snap['sam']['next_game_at'])
        time.sleep(4.2)
        snap2=self.get('?seq=201')
        self.assertEqual(snap2['sam']['remaining_seconds'],remaining);self.assertGreater(snap2['timestamp'],snap['timestamp']);self.assertFalse((ROOT/'returned').exists())
        self.assertEqual(self.post(request)[0],200)
        self.assertEqual(self.post(self.request('pause'))[0],409)
        self.assertEqual(self.post(self.request('resume'))[0],200)
        resumed=self.get('?seq=201');self.assertFalse(resumed['sam']['paused']);self.assertGreater(resumed['sam']['next_game_at'],old['sam']['next_game_at']);self.assertLessEqual(abs(resumed['sam']['next_game_at']-resumed['timestamp']-remaining),1)
        self.assertEqual(self.post(self.request('resume'))[0],409)
    def test_next_deduplicated_and_reused_id_rejected(self):
        request=self.request('next');self.assertEqual(self.post(request)[0],200)
        self.wait(lambda:(ROOT/'returned').exists());self.assertEqual((ROOT/'returned').read_text(),'next')
        self.assertEqual(self.post(request)[0],200)
        self.assertEqual(self.post(dict(request,action='play'))[0],409)
        self.assertEqual(self.post(self.request('next'))[0],409)
    def test_ignore_existing_list_cache_refill_and_undo(self):
        request=self.request('ignore'); path=self.state['game_path'];other=str(ROOT/'Other.sfc')
        cache=ROOT/'session/snes_gamelist.txt';cache.write_text(path+'\n'+other+'\n')
        self.assertEqual(self.post(request)[0],200)
        file=ROOT/'lists/snes_excludelist.txt';self.assertEqual(file.read_text().strip(),path)
        self.assertEqual(cache.read_text().strip(),other)
        # Warm/refilled candidate caches use the same standard filter.
        cache.write_text('/zip/collection.zip/'+Path(path).name+'\n'+other+'\n')
        env=dict(os.environ,gamelistpath=str(ROOT/'lists'))
        code=function('sam_apply_exclusions')+function('sam_is_excluded')+'\ngamelistpath="$LISTS"; ignorepath="$LISTS"\nsam_apply_exclusions snes "$CACHE"\nsam_is_excluded snes "$GAME"'
        run=subprocess.run(['bash','-c',code],env=dict(os.environ,LISTS=str(ROOT/'lists'),CACHE=str(cache),GAME=path))
        self.assertEqual(run.returncode,0);self.assertEqual(cache.read_text().strip(),other)
        file.write_text('');cache.write_text(path+'\n'+other+'\n')
        subprocess.run(['bash','-c',function('sam_apply_exclusions')+'\ngamelistpath="$LISTS"; ignorepath="$LISTS"; sam_apply_exclusions snes "$CACHE"'],env=dict(os.environ,LISTS=str(ROOT/'lists'),CACHE=str(cache)),check=True)
        self.assertIn(path,cache.read_text())
    def test_play_preserves_game_and_duplicate_after_owner_exit(self):
        request=self.request('play');self.assertEqual(self.post(request)[0],200)
        self.child.wait(timeout=3)
        self.assertFalse(self.get()['sam']['active'])
        values=control.parse_sam_state(control.STATE.read_bytes());self.assertEqual(values['game_kept'],'yes');self.assertEqual(values['rom_path'],self.state['game_path'])
        self.assertEqual(self.post(request)[0],200)
        self.assertEqual(self.post(self.request('next'))[0],409)
    def test_stale_malformed_unsupported_and_origin(self):
        for field,value in [('expected_seq',200),('game_path','/other/game.sfc')]:
            r=self.request();r[field]=value;self.assertEqual(self.post(r)[0],409)
        for field,value in [('expected_seq',True),('request_id','bad'),('game_path','/a\nb')]:
            r=self.request();r[field]=value;self.assertEqual(self.post(r)[0],400)
        self.assertEqual(self.post(self.request('arbitrary'))[0],501)
        self.assertEqual(self.post(b'{"action":"next","action":"play"}')[0],400)
        self.assertEqual(self.post(b'x'*4097)[0],400)
        self.assertEqual(self.post(self.request(),{'Content-Type':'application/json','Origin':'https://example.test'})[0],403)
    def test_owner_reuse_dead_inactive_and_generation_race(self):
        original=control.STATE.read_text()
        control.STATE.write_text(original.replace('owner_start='+control.owner()['owner_start'],'owner_start=1'))
        self.assertEqual(self.post(self.request())[0],409)
        control.STATE.write_text(original.replace('active=yes','active=no'));self.assertEqual(self.post(self.request())[0],409)
        control.STATE.write_text(original)
        current=control.status();request=self.request()
        envelope=dict(request=request,generation='old-generation',identity=current['identity'],expires=time.monotonic()+4)
        control.atomic(control.ROOT/'pending.json',envelope)
        self.wait(lambda:(control.ROOT/('ack-'+request['request_id']+'.json')).exists())
        self.assertEqual(control.read_json(control.ROOT/('ack-'+request['request_id']+'.json'))['code'],409)
        self.assertFalse(control.advertised()['paused'])
        self.stop();self.assertFalse(self.get()['sam']['active']);self.assertEqual(self.post(self.request())[0],409)
    def test_unavailable_transport_times_out_without_late_action(self):
        # Owner is alive, but stopped at the OS level and cannot consume.
        import signal
        os.kill(self.child.pid,signal.SIGSTOP)
        try:
            r=self.request('next');self.assertEqual(self.post(r)[0],503)
            self.assertEqual(self.post(r)[0],503)
        finally:os.kill(self.child.pid,signal.SIGCONT)
        time.sleep(.3);self.assertFalse(control.ROOT.joinpath('pending.json').exists())

class PathRecovery(unittest.TestCase):
    def test_title_only_log_requires_exact_live_sam_identity(self):
        tree=ast.parse(MONITOR_SERVER.read_text())
        methods=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in {'_sam_get_current','_sam_looks_like_path'}]
        log=ROOT/'log';log.write_text('12:00:00 - snes - Pokémon = USA\n')
        selected=[dict(core='snes',game='Pokémon = USA',rom_path='/games/Pokémon = USA.sfc')]
        fake_os=types.SimpleNamespace(path=types.SimpleNamespace(exists=lambda _:True,getmtime=lambda _:time.time(),splitext=os.path.splitext))
        ns=dict(os=fake_os,time=time,open=lambda *args,**kwargs:open(log,**kwargs),CORE_NAME_MAPPING={},CORE_NAME_MAPPING_LOWER={},sam_control=types.SimpleNamespace(owner=lambda:selected[0]))
        exec(compile(ast.fix_missing_locations(ast.Module(body=methods,type_ignores=[])),'path-recovery','exec'),ns)
        self.assertEqual(ns['_sam_get_current']()[-1],'/games/Pokémon = USA.sfc')
        for bad in [dict(core='nes',game='Pokémon = USA'),dict(core='snes',game='Other'),None]:
            selected[0]=bad;self.assertEqual(ns['_sam_get_current']()[-1],'')

if __name__=='__main__':unittest.main(verbosity=2)
