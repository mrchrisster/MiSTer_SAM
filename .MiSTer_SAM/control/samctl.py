# SPDX-License-Identifier: AGPL-3.0-or-later
"""Local SAM controls. No Monitor dependency, arbitrary command, or daemon."""
import argparse
import json
import sys
import uuid
import sam_control as transport


def main():
    parser = argparse.ArgumentParser(description='Control the active SAM selection')
    parser.add_argument('action', choices=('status',) + transport.ACTIONS)
    parser.add_argument('--request-id', default=None)
    parser.add_argument('--game-path')
    parser.add_argument('--owner-pid')
    parser.add_argument('--owner-start')
    parser.add_argument('--generation')
    args = parser.parse_args()
    if args.request_id:
        try: request_id=str(uuid.UUID(args.request_id))
        except ValueError: parser.error('request-id must be a UUID')
        # Consult accepted native IDs before checking a now-changed/dead owner.
        entry=None
        try:
            for line in (transport.STORE/'requests.jsonl').read_text().splitlines():
                try: item=json.loads(line)
                except ValueError: continue
                if item.get('id')==request_id: entry=item
        except FileNotFoundError: pass
        if entry is not None:
            prior=entry['request']
            request=dict(action=args.action, expected_seq=None,
                         game_path=args.game_path or prior['game_path'],request_id=request_id)
            code,body=transport.journal_lookup(request)
            print(json.dumps(dict(body,code=code,request_id=request_id)))
            return 0 if code==200 else 1
    current, owner = transport.status(), transport.owner()
    if args.action == 'status':
        print(json.dumps(dict(active=bool(owner), state=owner, control=current,
                              **transport.advertised()), ensure_ascii=False))
        return 0
    if not owner or not current.get('ready'):
        print(json.dumps(dict(ok=False, error='SAM is inactive or transitioning', code=409)))
        return 1
    if any(wanted is not None and wanted != actual for wanted, actual in (
        (args.owner_pid, owner['owner_pid']), (args.owner_start, owner['owner_start']),
        (args.generation, current['generation']), (args.game_path, owner['rom_path']))):
        print(json.dumps(dict(ok=False, error='SAM selection changed', code=409)))
        return 1
    try:
        request_id = str(uuid.UUID(args.request_id)) if args.request_id else str(uuid.uuid4())
    except ValueError:
        parser.error('request-id must be a UUID')
    request = dict(action=args.action, expected_seq=None, game_path=owner['rom_path'], request_id=request_id)
    transport.validate(dict(request, expected_seq=0))
    code, body = transport.submit(request, expected=current)
    print(json.dumps(dict(body, code=code, request_id=request_id), ensure_ascii=False))
    return 0 if code == 200 else 1


if __name__ == '__main__':
    sys.exit(main())
