"""Explicit live SAM checks; runs only when invoked manually on the MiSTer."""
import json
import subprocess
import threading
import time
import urllib.request
from pathlib import Path

ON = '/media/fat/Scripts/MiSTer_SAM_on.sh'
ROOT = Path('/tmp/.SAM_tmp')

def record(path):
    try:
        return dict(line.split('=', 1) for line in Path(path).read_text().splitlines() if '=' in line)
    except OSError:
        return {}

def owner():
    r = record(ROOT / 'session-owner')
    try:
        f = Path('/proc/' + r['pid'] + '/stat').read_text().rsplit(') ', 1)[1].split()
        return r if f[0] not in ('Z', 'X', 'x') and f[19] == r['start'] else {}
    except (OSError, KeyError, IndexError):
        return {}

def wait(check, seconds=30):
    until = time.monotonic() + seconds
    while time.monotonic() < until:
        if check():
            return
        time.sleep(.1)
    raise AssertionError('Timed out: owner=' + str(owner()) + ' state=' + str(record('/tmp/SAM_state')))

def command(*args):
    result = subprocess.run(['bash', ON, *args], text=True, capture_output=True, timeout=185)
    if result.returncode:
        raise AssertionError(str(args) + ': ' + result.stdout + result.stderr)
    return result.stdout

def emit(name, **fields):
    print(json.dumps(dict(test=name, **fields)), flush=True)

def snapshot():
    with urllib.request.urlopen('http://127.0.0.1:8081/status/snapshot', timeout=5) as reply:
        return json.load(reply)

def ready():
    return owner().get('phase') == 'playing' and record('/tmp/mister_sam_control/status').get('ready') == '1'

def start():
    command('start', 'snes')
    wait(ready, 120)
    wait(lambda: snapshot().get('game_path') == record('/tmp/SAM_state').get('rom_path'), 25)

def volumes():
    return [line for line in Path('/proc/mounts').read_text().splitlines()
            if '/media/fat/config/Volume.dat ' in line or '_volume.cfg ' in line]

def stop():
    then = time.monotonic()
    had_volume_bind = bool(volumes())
    samples = []
    done = threading.Event()
    def sample():
        while not done.is_set():
            try:
                before = Path('/tmp/CORENAME').read_text().strip().upper()
                bound = bool(volumes())
                after = Path('/tmp/CORENAME').read_text().strip().upper()
                samples.append((before, bound, after))
            except OSError:
                pass
            done.wait(.02)
    observer = threading.Thread(target=sample, daemon=True)
    observer.start()
    try:
        command('stop')
    finally:
        done.set()
        observer.join(timeout=1)
    wait(lambda: not owner() and Path('/tmp/CORENAME').read_text().strip().upper() == 'MENU', 20)
    assert record('/tmp/SAM_state').get('active') == 'no'
    assert not volumes(), volumes()
    saw_menu = False
    for before, bound, after in samples:
        if before == 'MENU' or after == 'MENU':
            saw_menu = True
        if had_volume_bind and not saw_menu and before == after and before:
            assert bound, ('Volume released before observed Menu', samples)
    time.sleep(2)
    assert not owner(), 'SAM restarted without waiting for a fresh idle interval'
    emit('Menu stop and volume mounts released after Menu',
         seconds=round(time.monotonic()-then-2, 3), observed_samples=len(samples))

def main():
    start()
    first = record('/tmp/SAM_state')['rom_path']
    with urllib.request.urlopen('http://127.0.0.1:8081/media/artwork', timeout=20) as reply:
        cover = reply.read()
        assert reply.status == 200 and reply.headers.get_content_type().startswith('image/') and len(cover)>100
    emit('SNES launched and Monitor serves artwork', path=first, cover_bytes=len(cover))
    identity = (owner()['pid'], owner()['start'])
    skipped = command('--gateway-backend', 'start', '--if-idle')
    assert (owner()['pid'], owner()['start']) == identity
    assert 'skipped' in skipped
    emit('Automatic start preserves explicit running session', owner=identity)
    command('pause')
    assert record('/tmp/mister_sam_control/status').get('paused') == '1'
    time.sleep(1)
    assert record('/tmp/SAM_state')['rom_path'] == first
    command('resume')
    assert record('/tmp/mister_sam_control/status').get('paused') == '0'
    emit('Pause/resume acknowledged')
    serial = owner()['launch']
    command('next')
    wait(lambda: ready() and owner().get('launch') != serial, 60)
    second = record('/tmp/SAM_state')['rom_path']
    assert first != second
    serial = owner()['launch']
    command('previous')
    wait(lambda: ready() and owner().get('launch') != serial, 60)
    assert record('/tmp/SAM_state')['rom_path'] == first
    emit('Next and Previous', first=first, second=second)
    stop()
    start()
    kept = record('/tmp/SAM_state')['rom_path']
    command('play')
    wait(lambda: not owner(), 15)
    state = record('/tmp/SAM_state')
    assert state.get('active') == 'no' and state.get('game_kept') == 'yes', state
    assert snapshot().get('game_path') == kept
    assert not volumes(), volumes()
    emit('Keep playing preserves game and restores volume', path=kept)
    start()
    stop()
    command('start')
    wait(ready, 150)
    emit('Configured automatic selection restored', owner=owner(), state=record('/tmp/SAM_state'))

if __name__ == '__main__':
    main()
