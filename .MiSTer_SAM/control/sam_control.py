# SPDX-License-Identifier: AGPL-3.0-or-later
"""Allowlisted Monitor/SAM bridge. SAM consumes commands in its own timer loop.

No commands are executed by the HTTP handler. The durable request journal
reserves an ID before dispatch, preventing retries from repeating an action even
if SAM or Monitor exits between acceptance and the HTTP response.
"""
import argparse
import fcntl
import ipaddress
import json
import os
from pathlib import Path
import threading
import time
import uuid
from urllib.request import urlopen

from sam_status import parse_sam_state, read_sam_status

ACTIONS = ('next', 'play', 'ignore', 'pause', 'resume')
ROOT = Path(os.environ.get('SAM_CONTROL_ROOT', '/tmp/mister_sam_control'))
STORE = Path(os.environ.get('SAM_CONTROL_STORE', '/media/fat/Scripts/.MiSTer_SAM/control-journal'))
STATE = Path(os.environ.get('SAM_CONTROL_STATE', '/tmp/SAM_state'))
MONITOR = os.environ.get('SAM_CONTROL_MONITOR', 'http://127.0.0.1:8081/status/snapshot')
MAX_REQUEST = 4096


def read_json(path, default=None):
    try:
        with open(path, encoding='utf-8') as source:
            raw=source.read(16385)
            if len(raw.encode('utf-8')) > 16384: return default
            return json.loads(raw)
    except (OSError, ValueError):
        return default


def atomic(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + '.tmp.' + str(os.getpid()))
    try:
        with open(tmp, 'w', encoding='utf-8') as target:
            json.dump(value, target, ensure_ascii=False)
            target.flush()
            os.fsync(target.fileno())
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


def owner():
    if not read_sam_status(STATE)['active']:
        return None
    try:
        state = parse_sam_state(STATE.read_bytes())
        if state.get('active') != 'yes' or not process_matches(state['owner_pid'], state['owner_start']):
            return None
        return state
    except (OSError, ValueError, KeyError):
        return None


def process_matches(pid, ticks):
    try:
        if not str(pid).isascii() or not str(pid).isdigit() or int(pid) <= 0: return False
        tail = Path('/proc', str(pid), 'stat').read_text().rsplit(')', 1)[1].split()
        return tail[0] not in {'Z', 'X', 'x'} and tail[19] == str(ticks)
    except (OSError, ValueError, IndexError):
        return False


def identity(state):
    # Path is literal data. The unique countdown generation disambiguates repeat
    # launches of the same path, even within one server epoch second.
    return {key: state[key] for key in ('owner_pid', 'owner_start', 'start_time', 'rom_path')}


def status():
    state = owner()
    try:
        raw = (ROOT / 'status').read_bytes()
        if len(raw) > 4096: return {}
        current = dict(line.split('=', 1) for line in raw.decode('utf-8').splitlines() if line)
        if not state or any(current.get(k) != state[k] for k in identity(state)): return {}
        return dict(current, identity=identity(state), ready=current.get('ready') == '1',
                    paused=current.get('paused') == '1', remaining_seconds=max(0, int(current['remaining_seconds'])))
    except (OSError, ValueError, KeyError):
        return {}


def advertised():
    current = status()
    if not current.get('ready') or (owner() or {}).get('mode') not in {'normal', 'roulette'}: return {'controls': [], 'paused': False}
    result = {'controls': list(ACTIONS), 'paused': current['paused']}
    if result['paused']: result['remaining_seconds'] = current['remaining_seconds']
    return result


def validate(request):
    if not isinstance(request, dict) or set(request) != {'action', 'expected_seq', 'game_path', 'request_id'}:
        raise ValueError('Expected action, expected_seq, game_path and request_id')
    if type(request['expected_seq']) is not int or request['expected_seq'] < 0:
        raise ValueError('Invalid expected_seq')
    path = request['game_path']
    if not isinstance(path, str) or not path.startswith('/') or len(path.encode('utf-8')) > 2048 or '\n' in path or '\r' in path or '\0' in path:
        raise ValueError('Invalid game_path')
    if not isinstance(request['action'], str):
        raise ValueError('Invalid action')
    if request['action'] not in ACTIONS:
        raise NotImplementedError('Unsupported SAM action')
    if not isinstance(request['request_id'], str) or len(request['request_id']) != 36:
        raise ValueError('request_id must be a UUID')
    request = dict(request)
    request['request_id'] = str(uuid.UUID(request['request_id']))
    return request


def fingerprint(request):
    return {key: request[key] for key in ('action', 'expected_seq', 'game_path')}


def journal_lookup(request):
    entry = None
    try:
        with open(STORE / 'requests.jsonl', encoding='utf-8') as source:
            for line in source:
                try: value = json.loads(line)
                except ValueError: continue  # A crash can leave a partial tail.
                if value['id'] == request['request_id']: entry = value
    except FileNotFoundError:
        pass
    if entry is None: return None
    if entry['request'] != fingerprint(request): return 409, {'ok': False, 'error': 'request_id was already used for another command'}
    return entry.get('code', 503), entry.get('body', {'ok': False, 'error': 'Command was already submitted; result unavailable'})


def journal(request, code=None, body=None):
    STORE.mkdir(parents=True, exist_ok=True)
    value = {'id': request['request_id'], 'request': fingerprint(request)}
    if code is not None: value.update(code=code, body=body)
    # Only the serialized Monitor handler appends. A leading newline also separates a partial
    # crash tail from the next valid record without losing reserved IDs.
    with open(STORE / 'requests.jsonl', 'a', encoding='utf-8') as target:
        target.write('\n' + json.dumps(value, separators=(',', ':')) + '\n')
        target.flush()
        os.fsync(target.fileno())


def trusted(address):
    networks = read_json(Path(os.environ.get('SAM_CONTROL_NETWORKS', str(Path(__file__).with_name('sam_control_networks.json')))), {})
    try:
        ip = ipaddress.ip_address(address)
        return any(ip in ipaddress.ip_network(net) for net in networks.get('trusted_networks', []))
    except ValueError:
        return False


def check_current(request, expected=None):
    state, current = owner(), status()
    if not state or not current.get('ready') or state['mode'] not in {'normal', 'roulette'}:
        return 409, 'SAM is inactive or transitioning'
    if state['rom_path'] != request['game_path']:
        return 409, 'SAM selection changed'
    if expected is not None and (current.get('generation') != expected.get('generation') or identity(state) != expected.get('identity')):
        return 409, 'SAM owner or countdown generation changed'
    if (request['action'] == 'pause' and current.get('paused')) or (request['action'] == 'resume' and not current.get('paused')):
        return 409, 'Command is incompatible with paused state'
    if request.get('expected_seq') is None:
        return 200, current
    try:
        with urlopen(MONITOR, timeout=2) as response:
            snap = json.load(response)
        if snap['seq'] != request['expected_seq'] or snap['game_path'] != request['game_path']:
            return 409, 'Monitor selection changed'
    except (OSError, ValueError, KeyError):
        return 503, 'Monitor identity check unavailable'
    return 200, current


_command_lock = threading.Lock()


def submit(request, expected=None):
    # Existing Monitor threads serialize requests. A file lock also protects a
    # brief overlap during Monitor restart. No broker or additional daemon.
    ROOT.mkdir(parents=True, exist_ok=True)
    os.chmod(ROOT, 0o700)
    with _command_lock, open(ROOT / 'submit.lock', 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        cached = journal_lookup(request)
        if cached is not None: return cached
        code, result = check_current(request, expected)
        if code != 200: return code, {'ok': False, 'error': result}
        journal(request)  # Reserve before SAM can consume it.
        ack = ROOT / ('ack-' + request['request_id'] + '.json')
        ack.unlink(missing_ok=True)
        atomic(ROOT / 'pending.json', dict(request=request, generation=result['generation'],
               identity=result['identity'], expires=time.monotonic()+4))
        reply = None
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            reply = read_json(ack)
            if reply: break
            time.sleep(.05)
        if reply: code, body = reply['code'], reply['body']
        else: code, body = 503, {'ok': False, 'error': 'SAM did not accept the command'}
        journal(request, code, body)
        (ROOT / 'pending.json').unlink(missing_ok=True)
        ack.unlink(missing_ok=True)
        return code, body


def claim(pid):
    pending = read_json(ROOT / 'pending.json')
    if not pending: return
    try:
        request = pending['request']
        # Native requests omit Monitor seq internally; all other validation is identical.
        validate(dict(request, expected_seq=0 if request.get('expected_seq') is None else request['expected_seq']))
        if not isinstance(pending['identity'], dict) or not isinstance(pending['generation'], str): raise ValueError('Invalid envelope')
        if type(pending['expires']) not in (float, int): raise ValueError('Invalid expiration')
    except (KeyError, ValueError, TypeError, NotImplementedError):
        (ROOT / 'pending.json').unlink(missing_ok=True)
        return
    state = owner()
    if time.monotonic() > pending['expires']:
        code, result = 503, 'Command expired before SAM accepted it'
    elif not state or int(state['owner_pid']) != pid:
        code, result = 409, 'SAM owner changed'
    else:
        code, result = check_current(request, pending)
    if code != 200:
        acknowledge(request['request_id'], code, result)
        (ROOT / 'pending.json').unlink(missing_ok=True)
        return
    # No path or arbitrary command crosses into the shell: two allowlisted tokens.
    (ROOT / 'pending.json').unlink(missing_ok=True)
    print(request['request_id'], request['action'])


def acknowledge(request_id, code, error=''):
    request_id = str(uuid.UUID(request_id))
    atomic(ROOT / ('ack-' + request_id + '.json'), dict(code=code, body={'ok': True} if code == 200 else {'ok': False, 'error': error}))


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('operation', choices=['claim', 'ack'])
    p.add_argument('--owner', type=int)
    p.add_argument('--request-id')
    p.add_argument('--code', type=int, default=200)
    p.add_argument('--error', default='')
    args = p.parse_args()
    if args.operation == 'claim': claim(args.owner)
    else: acknowledge(args.request_id, args.code, args.error)
