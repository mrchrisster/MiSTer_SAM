"""Read-only real arcade bootstrap, isolated lists, no core launch."""
import os,subprocess,time,tempfile,json
from pathlib import Path
HERE=Path(__file__).resolve().parents[1]
from paths import PACKAGE
with tempfile.TemporaryDirectory(prefix='sam-bootstrap-bench-') as tmp:
    root=Path(tmp);ini=root/'ini';ini.write_text('corelist="arcade"\ncorelistall="arcade"\nArtwork_only="No"\ncheck_for_new_games="No"\nrating="No"\n')
    env=dict(os.environ,SAM_MODULES_OVERRIDE='',SAM_ROOT=str(PACKAGE/'.MiSTer_SAM'),SAM_INI=str(ini),SAM_LIST_ROOT=str(root/'lists'),SAM_TMP_ROOT=str(root/'tmp'),SAM_SESSION_LIST_ROOT=str(root/'session'),SAM_CONFIG_ROOT=str(root/'config'),SAM_GAME_LOG=str(root/'games.log'))
    script='''source "$SAM_ROOT/../MiSTer_SAM_on.sh" --source-only
SAM_MODE=SINGLE; SAM_TARGET_CORE=arcade; corelist=(arcade); corelisttmp=(arcade); sam_bootstrap=1
sam_owner=bench; sam_revision=1; sam_job_serial=1
sam_session="$SAM_TMP_ROOT/bench"; sam_catalog_cache="$SAM_TMP_ROOT/cache"
mkdir -p "$sam_session/ready" "$sam_session/jobs" "$sam_session/consumed" "$sam_catalog_cache"
: > "$sam_session/alive"
sam_prepare_worker
'''
    log=open(root/'output','w');start=time.monotonic();p=subprocess.Popen(['bash','-c',script],env=env,stdout=log,stderr=log)
    for attempt in range(500):
        if list((root/'tmp/bench/ready').glob('*.record')):
            print(json.dumps(dict(cold_first_prepared_seconds=round(time.monotonic()-start,3),artwork=False)));break
        if p.poll() is not None:raise RuntimeError((root/'output').read_text())
        time.sleep(.01)
    else:raise RuntimeError('Bootstrap failed')
    p.wait(timeout=15);log.close()
