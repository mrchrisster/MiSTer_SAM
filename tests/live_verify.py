"""Run on MiSTer against the installed instance. Restores its test exclusion."""
import json,os,time,uuid,subprocess
from pathlib import Path
from urllib.request import urlopen,Request
from urllib.error import HTTPError
BASE='http://127.0.0.1:8081'
def snap(seq=None):
    with urlopen(BASE+'/status/snapshot'+('' if seq is None else '?seq='+str(seq)),timeout=3) as r:return json.load(r)
def ready():
    for _ in range(180):
        s=snap()
        if s['sam']['active'] and s['sam'].get('controls'):return s
        time.sleep(.5)
    raise RuntimeError('SAM failed to become ready')
def post(action,s,request_id=None):
    body=dict(action=action,expected_seq=s['seq'],game_path=s['game_path'],request_id=request_id or str(uuid.uuid4()))
    request=Request(BASE+'/control/sam',data=json.dumps(body).encode(),headers={'Content-Type':'application/json; charset=utf-8'})
    started=time.monotonic()
    try:
        with urlopen(request,timeout=8) as r:return r.status,json.load(r),round(time.monotonic()-started,3)
    except HTTPError as e:return e.code,json.load(e),round(time.monotonic()-started,3)
def cli(action,**flags):
    cmd=['/media/fat/Scripts/MiSTer_SAM_on.sh','control',action]
    for k,v in flags.items():cmd += ['--'+k.replace('_','-'),str(v)]
    p=subprocess.run(cmd,capture_output=True,text=True,timeout=8)
    return p.returncode,json.loads(p.stdout)
s=ready();print('initial',json.dumps(dict(seq=s['seq'],game=s['game'],is_arcade=s['is_arcade'],sam=s['sam'])))
assert s['is_arcade']
assert post('pause',s)[0]==200
paused=snap(s['seq']);remaining=paused['sam']['remaining_seconds']
time.sleep(2)
p2=snap(s['seq']);assert p2['unchanged'] and p2['seq']==s['seq'] and p2['sam']['active'] and p2['sam']['paused'] and p2['sam']['remaining_seconds']==remaining and p2['timestamp']>paused['timestamp']
assert cli('resume')[0]==0
resumed=snap(s['seq']);assert resumed['seq']==s['seq'] and not resumed['sam']['paused'] and resumed['sam']['next_game_at']>s['sam']['next_game_at']
print('pause_resume_unchanged',json.dumps(resumed))
id=str(uuid.uuid4());reply=post('next',s,id);assert reply[0]==200,reply
for _ in range(100):
    new=ready()
    if new['seq']!=s['seq'] and new['game_path']!=s['game_path']:break
    time.sleep(.1)
else:raise RuntimeError('Next did not change selection')
assert post('next',s,id)[0]==200
time.sleep(1);assert snap()['seq']==new['seq']
assert post('next',s)[0]==409
print('next_ack_seconds',reply[2],'stale_and_duplicate_passed',new['game'])
state=dict(line.split('=',1) for line in Path('/tmp/SAM_state').read_text().splitlines())
ignore=Path('/media/fat/SAM/Ignore')/(state['core']+'_excludelist.txt')
original=ignore.read_text() if ignore.exists() else ''
path=state['rom_path'];already=path in original.splitlines()
try:
    assert post('ignore',new)[0]==200
    selected=ready()
    assert path in ignore.read_text().splitlines()
    assert selected['game_path']!=path
    cache=Path('/tmp/.SAM_tmp/catalog-cache')/(state['core']+'.eligible')
    for _ in range(50):
        if cache.exists() and path not in cache.read_text().splitlines():break
        time.sleep(.2)
    else:raise RuntimeError('Ignore was not applied to cached candidates')
    print('ignore_persisted_and_cached_filter_updated')
finally:
    if not already and ignore.exists():
        lines=ignore.read_text().splitlines();lines=[line for line in lines if line!=path]
        temp=ignore.with_suffix('.undo.tmp');temp.write_text('\n'.join(lines)+('\n' if lines else ''));os.replace(temp,ignore)
        if not original and not lines:ignore.unlink()
play_id=str(uuid.uuid4());assert cli('play',request_id=play_id)[0]==0
assert cli('play',request_id=play_id)[0]==0
ended=snap();assert not ended['sam']['active']
state=dict(line.split('=',1) for line in Path('/tmp/SAM_state').read_text().splitlines());assert state['active']=='no' and state['game_kept']=='yes'
print('play_kept_game_duplicate_and_inactive_passed')
