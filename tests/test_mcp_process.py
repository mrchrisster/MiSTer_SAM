"""Real isolated Python processes prove exact MCP shutdown ownership."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
from paths import PACKAGE

spec = importlib.util.spec_from_file_location('mcp_process', PACKAGE / '.MiSTer_SAM/sam_mcp_process.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


@unittest.skipUnless(sys.platform == 'linux', 'Linux /proc identities')
class MCPProcesses(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='sam-mcp-stop-')
        self.addCleanup(self.tmp.cleanup)
        self.script = Path(self.tmp.name) / 'MiSTer_SAM_MCP.py'
        self.script.write_text('import signal,time,sys\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\nprint("ready",flush=True)\nwhile True: time.sleep(1)\n')

    def spawn(self, script):
        child = subprocess.Popen([sys.executable, str(script)], stdout=subprocess.PIPE, text=True)
        self.addCleanup(self.cleanup_child, child)
        self.assertEqual(child.stdout.readline().strip(), 'ready')
        return child

    @staticmethod
    def cleanup_child(child):
        if child.poll() is None:
            child.kill()
        child.wait(timeout=3)
        child.stdout.close()

    def test_all_exact_instances_reaped_foreign_script_untouched(self):
        first, second = self.spawn(self.script), self.spawn(self.script)
        other = self.script.with_name('foreign.py')
        other.write_text(self.script.read_text())
        foreign = self.spawn(other)
        began = time.monotonic()
        helper.stop(self.script, grace=.15)
        self.assertLess(time.monotonic() - began, 2)
        self.assertEqual(first.wait(timeout=2), -9)
        self.assertEqual(second.wait(timeout=2), -9)
        self.assertIsNone(foreign.poll())
        self.assertEqual(helper.processes(self.script), [])

    def test_changed_start_identity_is_never_signalled(self):
        owned = (123, '10', '/usr/bin/python3')
        with patch.object(helper, 'processes', side_effect=[[owned], []]), patch.object(helper, 'identity', return_value=(123, '11', '/usr/bin/python3')), patch.object(helper.os, 'kill') as kill:
            helper.stop(self.script, grace=0)
        kill.assert_not_called()

    def test_running_cli_detects_duplicates_without_stopping_them(self):
        first,second=self.spawn(self.script),self.spawn(self.script)
        command=[sys.executable,str(PACKAGE/'.MiSTer_SAM/sam_mcp_process.py')]
        result=subprocess.run(command+['--running',str(self.script)],timeout=3)
        self.assertEqual(result.returncode,0)
        self.assertIsNone(first.poll());self.assertIsNone(second.poll())
        result=subprocess.run(command+['--single',str(self.script)],timeout=3)
        self.assertEqual(result.returncode,1)

    def test_script_argument_elsewhere_does_not_match(self):
        child = subprocess.Popen([sys.executable, '-c', 'import time;time.sleep(30)', str(self.script)])
        self.addCleanup(lambda: (child.kill(), child.wait(timeout=3)) if child.poll() is None else None)
        self.assertIsNone(helper.identity(child.pid, self.script))
