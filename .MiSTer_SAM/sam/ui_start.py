# SPDX-License-Identifier: GPL-3.0-or-later
"""First-launch Scripts UI handoff; never applied to ordinary CLI/idle starts."""
import math
import os
from .session import owner_key, read_literal_file


def blocked(owner, event_time, runtime=None):
    if not owner:
        return False
    pid, start = owner_key(owner)
    if not (pid.isascii() and pid.isdecimal() and start.isascii() and start.isdecimal()):
        return False
    runtime = runtime or os.environ.get('SAM_TMP_ROOT', '/tmp/.SAM_tmp')
    record = read_literal_file(os.path.join(runtime, 'session-%s:%s' % (pid, start), 'ui-start'))
    if (record.get('owner_pid'), record.get('owner_start')) != (pid, start):
        return False
    if record.get('state') != 'ready':
        return True
    try:
        ready = float(record['ready_at'])
        return not math.isfinite(ready) or ready <= 0 or event_time <= ready
    except (ValueError, KeyError):
        return True
