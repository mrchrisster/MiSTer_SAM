"""Teardown failures cannot leak resources belonging to later modules."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from paths import PACKAGE

class ModuleCleanup(unittest.TestCase):
    def test_teardown_attempts_all_hooks_and_retains_first_error(self):
        script = '''source "$SAM_ROOT/lib/modules.sh"
first(){ printf first; return 7; }
second(){ printf second; return 8; }
third(){ printf third; }
for event in session_stop audio_stop display_shutdown display_exit; do
    SAM_HOOKS=()
    sam_register "$event" first
    sam_register "$event" second
    sam_register "$event" third
    rc=0; sam_emit "$event" || rc=$?
    printf ':%s\\n' "$rc"
done
SAM_HOOKS=()
sam_register candidate_prepare first
sam_register candidate_prepare third
rc=0; sam_emit candidate_prepare || rc=$?
printf ':%s\\n' "$rc"
'''
        result = subprocess.run([os.environ.get('SAM_TEST_BASH','bash'), '-c', script],
                                env=dict(os.environ, SAM_ROOT=(PACKAGE/'.MiSTer_SAM').as_posix()),
                                capture_output=True,text=True,timeout=5)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stdout.splitlines(),['firstsecondthird:7']*4+['first:7'])
