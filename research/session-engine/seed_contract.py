"""Research-only seed checks, using already prepared eligibility evidence.

This is not an artwork matcher/decoder or a complete collection invalidator.
Callers must supply the current eligibility revision from the real policy.
"""
import os


def file_stamp(path):
    node = os.stat(path)
    return (node.st_dev, node.st_ino, node.st_size, node.st_mtime_ns)


def usable(seed, allowed_cores, policy_revision, artwork_required):
    if seed.get('core') not in allowed_cores or seed.get('policy_revision') != policy_revision:
        return False
    if not seed.get('eligibility_complete'):
        return False
    try:
        # ZIP members identify their prepared containing archive separately.
        if file_stamp(seed['container']) != seed['container_stamp']:
            return False
        if artwork_required:
            if not seed.get('artwork_decoded'):
                return False
            if file_stamp(seed['cover']) != seed['cover_stamp']:
                return False
    except (OSError, KeyError):
        return False
    return True
