#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compatibility command entry into the shared local gateway."""
import sys
import subprocess
from sam.commands import CommandGateway


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    if not args:
        return 1
    try:
        okay = CommandGateway().execute(args[0], *args[1:])
        if not okay and args[0] not in {'control', 'status', 'pause', 'resume', 'play'}:
            print('SAM: command refused; session is inactive, changed, or command failed.', file=sys.stderr)
        return 0 if okay else 1
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        print('SAM: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
