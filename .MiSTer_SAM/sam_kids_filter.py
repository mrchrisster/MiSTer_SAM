#!/usr/bin/env python3
"""Refine Kids candidates by exact per-platform reviewed title, atomically.

SPDX-License-Identifier: GPL-3.0-or-later
"""
import argparse
import os
from pathlib import Path
import sys
from sam_titles import altered_release,title_key,title_keys


def filter_candidates(candidates,ratings):
    allowed={title_key(line) for line in ratings if line.strip() and not line.lstrip().startswith('#')}
    allowed.discard('')
    seen=set()
    for candidate in candidates:
        candidate=candidate.rstrip('\r\n')
        if candidate.lstrip().casefold().startswith('demo:') or altered_release(candidate):continue
        matches=allowed.intersection(title_keys(candidate))
        key=sorted(matches)[0] if matches else None
        if key is not None and key not in seen:
            seen.add(key)
            yield candidate


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--list',required=True,type=Path)
    parser.add_argument('--ratings',required=True,type=Path)
    args=parser.parse_args()
    temporary=args.list.with_name(args.list.name+'.kids.'+str(os.getpid()))
    try:
        with args.list.open(encoding='utf-8',errors='surrogateescape') as candidates,\
             args.ratings.open(encoding='utf-8') as ratings,\
             temporary.open('w',encoding='utf-8',errors='surrogateescape',newline='\n') as output:
            count=0
            for line in filter_candidates(candidates,ratings):output.write(line+'\n');count+=1
        os.replace(temporary,args.list)
        return 0 if count else 1
    except (OSError,ValueError) as error:
        print('SAM Kids filter: '+str(error),file=sys.stderr)
        return 2
    finally:temporary.unlink(missing_ok=True)


if __name__=='__main__':sys.exit(main())
