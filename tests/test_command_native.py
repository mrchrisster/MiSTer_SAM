"""Real tmux command routing on an isolated, uniquely named private server."""
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import uuid

from paths import PACKAGE

sys.path.insert(0, str(PACKAGE / '.MiSTer_SAM'))
from sam.commands import CommandGateway
from sam.session import read_session


@unittest.skipUnless(sys.platform.startswith('linux') and shutil.which('tmux'),
                     'native Linux and tmux required')
class NativeCommands(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sam-command-native-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.label = 'sam-test-' + uuid.uuid4().hex
        self.tmux = shutil.which('tmux')
        self.env = dict(os.environ)
        self.env.pop('TMUX', None)
        self.addCleanup(self.cleanup_server)
        self.owner_path = self.root / 'session-owner'
        self.script = self.root / 'reader.sh'
        self.script.write_text('''#!/bin/bash
stty -echo -icanon
printf ready > "$1"
while IFS= read -r -s -n 1 key; do
    printf '%s' "$key" >> "$2"
done
''')
        self.gateway = CommandGateway(owner_reader=lambda: read_session(str(self.owner_path)),
                                      runner=self.gateway_run)

    def private_tmux(self, *args, **kwargs):
        kwargs.setdefault('timeout', 5)
        kwargs.setdefault('capture_output', True)
        kwargs.setdefault('text', True)
        return subprocess.run([self.tmux, '-L', self.label, *args], env=self.env, **kwargs)

    def gateway_run(self, argv, **kwargs):
        # These fixtures exercise only keys. Refuse every other subprocess so
        # even a gateway regression cannot launch the real SAM entry script.
        self.assertEqual(argv[0], 'tmux')
        return self.private_tmux(*argv[1:], **kwargs)

    def cleanup_server(self):
        try:
            self.private_tmux('kill-server')
        except (OSError, subprocess.TimeoutExpired):
            pass

    def wait_for(self, predicate):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(.01)
        self.fail('Private tmux reader did not reach the expected state')

    def start_reader(self, session, stem, publish_owner=False):
        ready = self.root / (stem + '.ready')
        log = self.root / (stem + '.keys')
        command = 'exec bash ' + ' '.join(shlex.quote(str(path)) for path in (self.script, ready, log))
        result = self.private_tmux('new-session', '-P', '-F', '#{pane_id} #{pane_pid}',
                                   '-d', '-s', session, command)
        self.assertEqual(result.returncode, 0, result.stderr)
        pane, pid = result.stdout.strip().split()
        self.wait_for(ready.exists)
        fields = Path('/proc', pid, 'stat').read_text().rsplit(') ', 1)[1].split()
        if publish_owner:
            self.owner_path.write_text('pid=%s\nstart=%s\nphase=playing\nlaunch=1\n' % (pid, fields[19]))
        return pane, pid, log

    def test_next_uses_exact_real_session_and_owner_pane(self):
        _, _, decoy = self.start_reader('SAM_other', 'decoy')
        pane, pid, log = self.start_reader('SAM', 'owner', publish_owner=True)
        owner = read_session(str(self.owner_path))
        self.assertIsNotNone(owner)
        self.assertEqual(owner.pid, pid)
        self.assertTrue(self.gateway.execute('next', owner=owner))
        self.wait_for(lambda: log.exists() and log.read_text() == 'n')
        self.assertFalse(decoy.exists())
        panes = self.gateway.read_panes()
        self.assertEqual(panes, [(pane, pid)])

    def test_stale_owner_cannot_send_to_replacement_pane(self):
        self.start_reader('SAM_other', 'anchor')
        old_pane, _, old_log = self.start_reader('SAM', 'old', publish_owner=True)
        old_owner = read_session(str(self.owner_path))
        self.assertIsNotNone(old_owner)
        removed = self.private_tmux('kill-session', '-t', '=SAM')
        self.assertEqual(removed.returncode, 0, removed.stderr)
        new_pane, _, new_log = self.start_reader('SAM', 'replacement', publish_owner=True)
        self.assertNotEqual(new_pane, old_pane)
        self.assertFalse(self.gateway.execute('next', owner=old_owner))
        self.assertFalse(old_log.exists())
        self.assertFalse(new_log.exists())
        # A fresh command proves the replacement's reader is operational; only
        # the explicitly stale request was rejected.
        self.assertTrue(self.gateway.execute('next'))
        self.wait_for(lambda: new_log.exists() and new_log.read_text() == 'n')


if __name__ == '__main__':
    unittest.main()
