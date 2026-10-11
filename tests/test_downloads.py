"""Asset failures preserve working files; no network is used."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from paths import PACKAGE

class Downloads(unittest.TestCase):
    def shell(self, code):
        with tempfile.TemporaryDirectory() as tmp:
            env=dict(os.environ,SAM_ROOT=(PACKAGE/'.MiSTer_SAM').as_posix(),TEST_ROOT=Path(tmp).as_posix())
            result=subprocess.run([os.environ.get('SAM_TEST_BASH','bash'),'-c',
                'set -e\nsource "$SAM_ROOT/lib/downloads.sh"\ncd "$TEST_ROOT"\nsamdebug(){ :; }\n'+code],
                env=env,capture_output=True,text=True,timeout=5)
            self.assertEqual(result.returncode,0,result.stderr+'\n'+result.stdout)

    def test_failed_transfer_never_replaces_working_asset(self):
        self.shell('''printf working > asset
curl(){ while (($#)); do if [[ "$1" == -o ]]; then printf partial > "$2"; break; fi; shift; done; return 22; }
rc=0; curl_download asset https://fixture || rc=$?
[[ "$rc" == 22 && $(<asset) == working ]]
shopt -s nullglob; leftovers=(asset.part.*); [[ ${#leftovers[@]} == 0 ]]
''')

    def test_success_preserves_executable_and_unchanged_file(self):
        self.shell('''printf old > asset.sh; chmod +x asset.sh
curl(){ while (($#)); do if [[ "$1" == -o ]]; then printf new > "$2"; break; fi; shift; done; }
curl_download asset.sh https://fixture
[[ $(<asset.sh) == new ]]
[[ "$OSTYPE" == msys ]] || [[ -x asset.sh ]]
mv(){ echo unexpected-replacement >&2; return 99; }
curl_download asset.sh https://fixture
''')

    def test_failed_bootstrap_download_does_not_publish_or_report_success(self):
        self.shell('''raw_base=https://fixture
curl_download(){ return 22; }
mv(){ echo forbidden-move >&2; return 99; }
rc=0; output=$(get_samstuff helper.sh "$TEST_ROOT") || rc=$?
[[ "$rc" == 1 && "$output" != *Done* ]]
''')
