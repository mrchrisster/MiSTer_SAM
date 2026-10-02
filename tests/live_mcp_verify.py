"""Explicit live smoke test. Sends existing MCP network-input signals on MiSTer."""
import json,os,subprocess,time,urllib.request
from pathlib import Path
ON='/media/fat/Scripts/MiSTer_SAM_on.sh'
def literal(path):
    try:return dict(x.split('=',1) for x in Path(path).read_text().splitlines() if '=' in x)
    except OSError:return {}
def owner():
    r=literal('/tmp/.SAM_tmp/session-owner')
    try:
        f=Path('/proc/'+r['pid']+'/stat').read_text().rsplit(') ',1)[1].split()
        return r if f[0] not in ('Z','X','x') and f[19]==r['start'] else {}
    except (OSError,KeyError,IndexError):return {}
def snapshot(seq=None):
    with urllib.request.urlopen('http://127.0.0.1:8081/status/snapshot'+('' if seq is None else '?seq='+str(seq)),timeout=4) as f:return json.load(f)
def wait(check,seconds=40):
    until=time.monotonic()+seconds
    while time.monotonic()<until:
        if check():return
        time.sleep(.25)
    raise AssertionError('Timed out: '+str(owner())+' state='+str(literal('/tmp/SAM_state')))
def start():
    subprocess.run([ON,'start','arcade'],check=True)
    wait(lambda:owner().get('phase')=='playing',120)
    wait(lambda:Path('/tmp/CORENAME').read_text().strip()==literal('/tmp/SAM_state').get('setname'),90)
    time.sleep(2) # allow the owner observer to arm this actual launch

def stopped():
    return not owner() and subprocess.run(['tmux','has-session','-t','SAM'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode!=0

def check_off(seq):
    state=literal('/tmp/SAM_state');assert state.get('active')=='no',state
    s=snapshot(seq);assert not s['sam']['active'] and 'timestamp' in s,s
    return s

import sys
if '--skip-keyboard' not in sys.argv:
    wait(lambda:owner().get('phase')=='playing',120)
    wait(lambda:Path('/tmp/CORENAME').read_text().strip()==literal('/tmp/SAM_state').get('setname'),90)
    time.sleep(2)
    s=snapshot();pid=owner()['pid']
    with open('/tmp/remote.log','a') as f:f.write('kbd SAM MCP live shutdown test\n')
    wait(stopped,15);wait(lambda:Path('/tmp/CORENAME').read_text().strip()=='MENU',15)
    check_off(s['seq']);time.sleep(5);assert stopped(),'Late ghost session after input'
    print('PASS: network keyboard input stops owner and pane, loads Menu, stays stopped',flush=True)
start();s=snapshot();game=s['game_path']
Path('/tmp/.SAM_tmp/SAM_Joy_Activity').write_text('zaparoo')
wait(stopped,15);wait(lambda:literal('/tmp/SAM_state').get('game_kept')=='yes',5);off=check_off(s['seq'])
state=literal('/tmp/SAM_state');assert state.get('game_kept')=='yes',state
full=snapshot();assert full['game_path']==game,(full,game)
print('PASS: Zaparoo exits to game; game_kept=yes and game unchanged',flush=True)
start();s=snapshot()
subprocess.run(['timeout','1','sh','-c',"printf '%s\\n' 'load_core /media/fat/menu.rbf' > /dev/MiSTer_cmd"],check=True)
wait(lambda:Path('/tmp/CORENAME').read_text().strip()=='MENU',15)
wait(stopped,12);check_off(s['seq']);time.sleep(5);assert stopped()
print('PASS: external Menu stops SAM after debounce without an input event',flush=True)
# Restore the user's normal configured selection policy.
subprocess.run([ON,'start'],check=True)
wait(lambda:owner().get('phase')=='playing',90)
s=snapshot();assert s['sam']['active'],s
print('PASS: normal configured SAM restored; fresh endpoint active',flush=True)
print(json.dumps({'seq':s['seq'],'core':s['core'],'sam':s['sam'],'timestamp':s['timestamp']}),flush=True)
