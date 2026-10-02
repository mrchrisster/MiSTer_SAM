"""Exercise the real session loop, with hardware launch/audio/mounts replaced."""
import os, json, signal, subprocess, tempfile, time, unittest
from pathlib import Path
HERE=Path(__file__).resolve().parents[1]
from paths import PACKAGE
class Engine(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='sam-engine-'); self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name); self.log=self.root/'launches'
        ini=self.root/'ini'; ini.write_text('corelist="snes"\ncorelistall="snes"\nrating="no"\ngametimer=0\ncheck_for_new_games="no"\nmute="no"\n')
        self.env=dict(os.environ,SAM_MODULES_OVERRIDE="controls",SAM_ROOT=str(PACKAGE/'.MiSTer_SAM'),SAM_INI=str(ini),SAM_LIST_ROOT=str(self.root/'lists'),SAM_TMP_ROOT=str(self.root/'tmp'),SAM_SESSION_LIST_ROOT=str(self.root/'session-lists'),SAM_CONFIG_ROOT=str(self.root/'config'),SAM_MISTER_ROOT=str(self.root/'media'),SAM_STATE_FILE=str(self.root/'state'),SAM_CONTROL_STATE=str(self.root/'state'),SAM_CONTROL_ROOT=str(self.root/'controls'),SAM_CONTROL_STORE=str(self.root/'journal'),TEST_LOG=str(self.log),SAM_GAME_LOG=str(self.root/"games.log"))
        (self.root/'lists/Gamelists').mkdir(parents=True)
        games=[]
        for name in ['A','B','C','D','E']:
            p=self.root/(name+'.sfc');p.touch();games.append(str(p))
        (self.root/'lists/Gamelists/snes_gamelist.txt').write_text('\n'.join(games)+'\n')
        script='''source "$SAM_ROOT/../MiSTer_SAM_on.sh" --source-only
sam_prep(){ :; }; disable_bootrom(){ :; }; sam_cleanup(){ :; }
load_core(){ printf '%s\\n' "$2" >> "$TEST_LOG"; sam_emit display_launch "$3" "$2" "$1" ''; sleep 0.35; }
loop_core snes
'''
        self.output=open(self.root/'output','w');self.addCleanup(self.output.close)
        self.proc=subprocess.Popen(['bash','-c',script],env=self.env,stdin=subprocess.PIPE,stdout=self.output,stderr=self.output)
        self.addCleanup(self.stop)
    def stop(self):
        if self.proc.poll() is None:self.proc.terminate()
        try:self.proc.wait(timeout=4)
        except subprocess.TimeoutExpired:self.proc.kill();self.proc.wait()
        self.proc.stdin.close()
    def wait(self,predicate,timeout=8):
        deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            if predicate():return
            if self.proc.poll() is not None:self.fail((self.root/'output').read_text())
            time.sleep(.02)
        self.fail('Timed out: '+(self.root/'output').read_text())
    def launches(self):return self.log.read_text().splitlines() if self.log.exists() else []
    def ready(self):return (self.root/'controls/status').exists() and '\nready=1\n' in (self.root/'controls/status').read_text()
    def key(self,key):self.proc.stdin.write(key.encode());self.proc.stdin.flush()
    def control(self,action,**options):
        cmd=['python3',str(PACKAGE/'.MiSTer_SAM/control/samctl.py'),action]
        for k,v in options.items():cmd+=['--'+k.replace('_','-'),str(v)]
        p=subprocess.run(cmd,env=self.env,text=True,capture_output=True,timeout=8)
        return p.returncode,json.loads(p.stdout)
    def test_prepared_next_loading_burst_previous_and_cleanup(self):
        self.wait(self.ready);first=self.launches()[0]
        start=time.monotonic();self.key('n');self.wait(lambda:len(self.launches())==2)
        self.assertLess(time.monotonic()-start,.5)
        self.key('n'*40);self.wait(lambda:len(self.launches())==3);self.wait(self.ready)
        time.sleep(.5);self.assertEqual(len(self.launches()),3)
        previous=self.launches()[1];self.key('p');self.wait(lambda:len(self.launches())==4);self.wait(self.ready)
        self.assertEqual(self.launches()[3],previous)
        self.stop();self.assertIn('active=no',(self.root/'state').read_text())
        self.assertFalse(list((self.root/'tmp').glob('session-*/alive')))
    def test_real_engine_commands_pause_resume_ignore_and_play(self):
        self.wait(self.ready);game=self.launches()[0]
        rc,reply=self.control('pause');self.assertEqual(rc,0,reply)
        self.assertIn('paused=1',(self.root/'controls/status').read_text())
        rc,reply=self.control('resume');self.assertEqual(rc,0,reply)
        rc,reply=self.control('next',game_path='/stale.sfc');self.assertEqual(reply['code'],409)
        rc,reply=self.control('ignore');self.assertEqual(rc,0,reply)
        self.wait(lambda:len(self.launches())==2);self.wait(self.ready)
        self.assertIn(game,(self.root/'lists/Ignore/snes_excludelist.txt').read_text())
        play_id='12345678-1234-1234-1234-123456789abc'
        rc,reply=self.control('play',request_id=play_id);self.assertEqual(rc,0,reply)
        rc,reply=self.control('play',request_id=play_id);self.assertEqual(rc,0,reply)
        self.proc.wait(timeout=4)
        state=(self.root/'state').read_text();self.assertIn('active=no',state);self.assertIn('game_kept=yes',state)
if __name__=='__main__':unittest.main(verbosity=2)
