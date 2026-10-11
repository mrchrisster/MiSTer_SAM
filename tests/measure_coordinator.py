"""Compare session runtimes with mocked hardware; optional sample seconds."""
import json
import os
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(sys.argv[1]) / 'tests'))
from test_engine import Engine

def process(pid):
    try:
        root = Path('/proc') / str(pid)
        fields = (root / 'stat').read_text().rsplit(') ', 1)[1].split()
        return dict(pid=pid, parent=int(fields[1]), start=fields[19],
                    ticks=int(fields[11])+int(fields[12]),
                    rss_kib=int(fields[21])*os.sysconf('SC_PAGE_SIZE')//1024,
                    command=(root/'cmdline').read_bytes().replace(b'\0',b' ').decode(errors='replace'))
    except (OSError, IndexError):
        return None

fixture = Engine('test_prepared_next_loading_burst_previous_and_cleanup')
try:
    fixture.setUp()
    fixture.wait(fixture.ready, 30)
    fixture.wait(lambda: len(list((fixture.root/'tmp').glob('session-*/ready/*.record'))) >= 2, 30)
    time.sleep(1)
    parent=fixture.proc.pid
    initial={}
    for path in Path('/proc').glob('[0-9]*'):
        p=process(int(path.name))
        if p and (p['pid']==parent or p['parent']==parent):
            initial[p['pid']]=p
    began=time.monotonic()
    time.sleep(float(sys.argv[2]) if len(sys.argv) > 2 else 8)
    elapsed=time.monotonic()-began
    final=[]
    for pid,p in initial.items():
        current=process(pid)
        if current and p['start']==current['start']:
            current['cpu_percent_one_core']=round((current['ticks']-p['ticks'])/os.sysconf('SC_CLK_TCK')/elapsed*100,3)
            # Report identity without dumping the fixture shell's script.
            current['command']='python controller' if 'sam.engine' in current['command'] else 'Bash owner/worker'
            final.append(current)
    print(json.dumps(dict(source=sys.argv[1], seconds=round(elapsed,3), processes=final,
                          cpu_percent_one_core=sum(p['cpu_percent_one_core'] for p in final),
                          rss_kib_sum=sum(p['rss_kib'] for p in final))), flush=True)
finally:
    fixture.doCleanups()
