"""Real Linux BGM wrapper/daemon/socket fixtures, isolated from installed music.

Only the private executable and Unix socket are used. No audio device, volume
configuration, network stream, or installed BGM service is accessed.
"""
import ctypes
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from paths import PACKAGE

ACTOR = r'''#!/usr/bin/env python3
import json, os, signal, socket, subprocess, sys, time
from pathlib import Path
root = Path(os.environ['BGMI_ROOT'])

def ticks(pid):
    return Path('/proc/%s/stat' % pid).read_text().rsplit(') ', 1)[1].split()[19]

def log(role):
    row = dict(role=role, pid=os.getpid(), start=ticks(os.getpid()))
    fd = os.open(str(root/'actors'), os.O_WRONLY|os.O_CREAT|os.O_APPEND, 0o600)
    os.write(fd, (json.dumps(row)+'\n').encode()); os.close(fd)

if len(sys.argv)>1 and sys.argv[1]=='daemon':
    log('daemon')
    endpoint = root/'control.sock'
    time.sleep(float(os.environ.get('BGMI_START_DELAY','0')))
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(endpoint)); server.listen(20); server.settimeout(.05)
    state = dict(pid=os.getpid(), playing=False, playincore='no', playback='random', play_calls=0)
    terminate_at = None
    def term(_sig, _frame):
        global terminate_at
        if terminate_at is None:
            terminate_at = time.monotonic()+float(os.environ.get('BGMI_TERM_DELAY','0'))
    signal.signal(signal.SIGTERM, term)
    def save():
        (root/'state').write_text(json.dumps(state))
    save()
    try:
        while terminate_at is None or time.monotonic()<terminate_at:
            try: conn, _ = server.accept()
            except socket.timeout: continue
            with conn:
                conn.settimeout(.5); data=b''
                while True:
                    chunk=conn.recv(4096)
                    if not chunk: break
                    data+=chunk
                command=data.decode().strip(); reply=''
                # The installed handler blocks while changing/stopping tracks.
                # Its connection closes only after that work has completed.
                if command in {'play','stop'} or command.startswith('set playback '):
                    time.sleep(float(os.environ.get('BGMI_COMMAND_DELAY','0')))
                if command=='pid': reply=os.environ.get('BGMI_REPORTED_PID',str(os.getpid()))
                elif command=='status':
                    reply=('yes' if state['playing'] else 'no')+'\t'+state['playback']+'\tnone\tfixture'
                elif command=='get playincore': reply=state['playincore']
                elif command=='get playback': reply=state['playback']
                elif command=='play': state['playing']=True; state['play_calls']+=1
                elif command=='stop': state['playing']=False
                elif command.startswith('set playincore '): state['playincore']=command.split()[-1]
                elif command.startswith('set playback '): state['playback']=command.split()[-1]
                save()
                if reply:
                    try: conn.sendall((reply+'\n').encode())
                    except BrokenPipeError: pass
    finally:
        server.close()
        try: endpoint.unlink()
        except FileNotFoundError: pass
else:
    if sys.argv[1:] != ['exec']:
        (root/'wrong-invocation').write_text(repr(sys.argv[1:]))
        raise SystemExit(2)
    log('wrapper')
    child=subprocess.Popen([sys.executable,str(root/'daemon.py'),'daemon'],
                           start_new_session=True, stdin=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    stopping=False; signalled=False
    def term(_sig,_frame):
        global stopping
        stopping=True
    signal.signal(signal.SIGTERM,term)
    while child.poll() is None:
        if stopping and not signalled:
            try: child.terminate()
            except ProcessLookupError: pass
            signalled=True
        time.sleep(.02)
    child.wait()
'''


@unittest.skipUnless(sys.platform.startswith('linux') and shutil.which('socat'),
                     'Linux /proc and socat are required')
class BGMIntegration(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sam-bgmi-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.wrapper = self.root/'bgm.sh'
        self.daemon_script = self.root/'daemon.py'
        for path in (self.wrapper, self.daemon_script):
            path.write_text(ACTOR); path.chmod(0o700)
        (self.root/'runtime').mkdir()
        self.env = dict(os.environ, BGMI_ROOT=str(self.root),
                        SAM_BGM_SCRIPT=str(self.wrapper),
                        SAM_BGM_SOCKET=str(self.root/'control.sock'),
                        SAM_BGM_OWNER_FILE=str(self.root/'owner'),
                        SAM_BGM_PROC_ROOT='/proc',
                        BGMI_RUNTIME=str(self.root/'runtime'),
                        BGMI_FUNCTIONS=str(PACKAGE/'.MiSTer_SAM/modules/bgm-functions.sh'))
        self.foreign = None
        # Restore this process-local setting after reaping our detached actors.
        self.libc = ctypes.CDLL(None, use_errno=True)
        previous = ctypes.c_int()
        if self.libc.prctl(37, ctypes.byref(previous), 0, 0, 0) or self.libc.prctl(36, 1, 0, 0, 0):
            self.skipTest('Child subreaper unavailable')
        self.previous_subreaper = previous.value
        self.addCleanup(self.cleanup)

    @staticmethod
    def proc(pid):
        try:
            fields = Path('/proc/%s/stat' % pid).read_text().rsplit(') ', 1)[1].split()
            return fields[0], fields[19]
        except (OSError, IndexError): return None

    def actors(self):
        path = self.root/'actors'
        if not path.exists(): return []
        return [json.loads(line) for line in path.read_text().splitlines() if line]

    def alive(self, actor):
        value = self.proc(actor['pid'])
        return bool(value and value[1] == actor['start'] and value[0] not in {'Z','X','x'})

    def cleanup(self):
        # Signal only known fixture identities; never discover victims by name.
        actors = sorted(self.actors(), key=lambda row: row['role'] != 'daemon')
        for actor in actors:
            if self.alive(actor):
                try: os.kill(actor['pid'], signal.SIGKILL)
                except ProcessLookupError: pass
        if self.foreign is not None:
            if self.foreign.poll() is None: self.foreign.kill()
            self.foreign.wait(timeout=2)
        def present(actor):
            value=self.proc(actor['pid'])
            return bool(value and value[1] == actor['start'])
        until = time.monotonic()+2
        while time.monotonic()<until:
            for actor in actors:
                try:
                    os.waitpid(actor['pid'], os.WNOHANG)
                except ChildProcessError: pass
            if all(not present(row) for row in actors): break
            time.sleep(.01)
        leaked = [row for row in actors if present(row)]
        self.libc.prctl(36, self.previous_subreaper, 0, 0, 0)
        self.assertEqual(leaked, [], 'Private BGM actors survived teardown')

    def run_api(self, command, stop='yes', timeout=12):
        script = '''mrsamtmp="$BGMI_RUNTIME"
source "$BGMI_FUNCTIONS"
# The historical metadata switch must never edit/read installed bgm.ini.
grep(){ [[ "${@: -1}" != /media/fat/music/bgm.ini ]] || return 1; command grep "$@"; }
sed(){ echo forbidden-installed-config-edit >&2; return 99; }
bgm=yes
bgmstop="$BGMI_STOP"
''' + command + '\n'
        return subprocess.run(['bash','-c',script], env=dict(self.env, BGMI_STOP=stop),
                              text=True, capture_output=True, timeout=timeout,
                              start_new_session=True)

    def query(self, command):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as peer:
            peer.settimeout(1); peer.connect(str(self.root/'control.sock'))
            peer.sendall(command.encode()); peer.shutdown(socket.SHUT_WR)
            data=b''
            while True:
                block=peer.recv(4096)
                if not block: break
                data+=block
            return data.decode().strip()

    def owner(self):
        return dict(line.split('=',1) for line in (self.root/'owner').read_text().splitlines() if '=' in line)

    def wait_dead(self, actors, timeout=4):
        until=time.monotonic()+timeout
        while time.monotonic()<until:
            if all(not self.alive(row) for row in actors): return
            time.sleep(.02)
        self.fail('Actors still live: '+str(actors))

    def start(self):
        result=self.run_api('bgm_start')
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr+'\n'+str(self.actors()))
        self.assertEqual(self.query('status').split('\t')[0], 'yes')
        self.assertEqual(self.query('get playincore'), 'yes')
        self.assertFalse((self.root/'wrong-invocation').exists())
        return self.actors()

    def test_start_captures_detached_daemon_and_fresh_shell_stop_reaps_both(self):
        actors=self.start(); self.assertEqual(len(actors),2)
        daemon=next(row for row in actors if row['role']=='daemon')
        wrapper=next(row for row in actors if row['role']=='wrapper')
        record=self.owner()
        self.assertEqual(record['pid'],str(daemon['pid']))
        self.assertEqual(record['start'],daemon['start'])
        self.assertEqual(record['exe'],os.readlink('/proc/%s/exe'%daemon['pid']))
        self.assertEqual(record['wrapper_pid'],str(wrapper['pid']))
        self.assertNotEqual(os.getsid(daemon['pid']),os.getsid(wrapper['pid']))
        result=self.run_api('bgm_stop')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.wait_dead(actors)

    def test_stop_no_retains_daemon_but_reports_stopped(self):
        actors=self.start()
        result=self.run_api('bgm_stop',stop='no')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertTrue(all(self.alive(row) for row in actors))
        self.assertEqual(self.query('status').split('\t')[0],'no')
        self.assertEqual(self.query('get playincore'),'no')

    def test_next_start_reuses_persistent_daemon_without_duplicates(self):
        actors=self.start(); original=self.owner()['pid']
        result=self.run_api('bgm_stop',stop='no')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.start()
        self.assertEqual(self.owner()['pid'],original)
        self.assertEqual(self.actors(),actors)
        self.assertTrue(all(self.alive(row) for row in actors))

    def make_foreign(self):
        marker=self.root/'foreign-term'
        code='import signal,time,pathlib; signal.signal(signal.SIGTERM,lambda *_: pathlib.Path(%r).write_text("term")); time.sleep(30)'%str(marker)
        self.foreign=subprocess.Popen([sys.executable,'-c',code,str(self.wrapper)],start_new_session=True)
        return self.foreign.pid,marker

    def test_stale_owner_record_cannot_signal_foreign_instance(self):
        self.start(); foreign,marker=self.make_foreign()
        record=self.owner(); record['pid']=str(foreign); record['start']='0'
        (self.root/'owner').write_text(''.join('%s=%s\n'%item for item in record.items()))
        self.run_api('bgm_stop')
        time.sleep(.1)
        self.assertIsNone(self.foreign.poll())
        self.assertFalse(marker.exists())

    def test_socket_claiming_foreign_pid_is_rejected_without_signalling_it(self):
        foreign,marker=self.make_foreign(); self.env['BGMI_REPORTED_PID']=str(foreign)
        result=self.run_api('bgm_start')
        self.assertNotEqual(result.returncode,0,result.stdout+result.stderr)
        time.sleep(.1)
        self.assertIsNone(self.foreign.poll())
        self.assertFalse(marker.exists())
        self.wait_dead(self.actors())

    def test_slow_daemon_shutdown_returns_bounded_failure(self):
        self.env['BGMI_TERM_DELAY']='8'
        actors=self.start(); then=time.monotonic()
        result=self.run_api('bgm_stop')
        elapsed=time.monotonic()-then
        self.assertNotEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertLess(elapsed,6,'Shutdown exceeded shared bounded wait')
        self.assertTrue((self.root/'owner').exists())
        self.assertTrue(any(self.alive(row) for row in actors))

    def test_delayed_command_eof_ack_and_playing_reuse(self):
        self.env['BGMI_COMMAND_DELAY']='2'
        actors=self.start()
        before=json.loads((self.root/'state').read_text())['play_calls']
        result=self.run_api('bgm_start')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual(self.query('status').split('\t')[0],'yes')
        self.assertEqual(json.loads((self.root/'state').read_text())['play_calls'],before)
        result=self.run_api('bgm_stop',stop='no')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual(self.query('status').split('\t')[0],'no')
        self.assertEqual(self.query('get playincore'),'no')
        self.start()
        self.assertEqual(json.loads((self.root/'state').read_text())['play_calls'],before+1)
        self.assertEqual(self.actors(),actors)

    def test_same_shell_persistent_reuse_repeated_stop_and_exit_cleanup(self):
        result=self.run_api('''
bgm_start || exit 10
bgmstop=no
bgm_stop || exit 11
bgm_start || exit 12
bgmstop=yes
bgm_stop || exit 13
bgm_stop || exit 14
trap 'bgm_stop || exit 15' EXIT
''', timeout=30)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        actors=self.actors()
        self.assertEqual(len(actors),2,'Persistent reuse launched a duplicate daemon')
        self.wait_dead(actors)

    def test_delayed_daemon_startup_is_captured_and_owned(self):
        self.env['BGMI_START_DELAY']='2.1'
        actors=self.start()
        daemon=next(row for row in actors if row['role']=='daemon')
        self.assertEqual(self.owner()['pid'],str(daemon['pid']))
        result=self.run_api('bgm_stop')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.wait_dead(actors)


if __name__=='__main__': unittest.main(verbosity=2)
