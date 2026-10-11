# SPDX-License-Identifier: GPL-3.0-or-later
"""Short-lived menu pause lease and kernel-owned menu visibility checks.

The shell owns menu.lock for its entire dialog lifecycle. Readers never create
or unlink it. A pause lease belongs to one owner and countdown selection only.
"""
import argparse
import base64
import contextlib
import fcntl
import io
import json
import os
from pathlib import Path
import stat
import sys

# Support the installed shell's direct script invocation as well as -m.
if __package__ in (None, ''):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from sam.commands import CommandGateway
from sam.session import owner_key


def active(path=None):
    """Inspect an existing regular lock once; uncertain access blocks actions."""
    path = path or Path(os.environ.get('SAM_MENU_TMP_ROOT', '/tmp/.SAM_menu')) / 'menu.lock'
    descriptor = None
    try:
        descriptor = os.open(path, os.O_RDONLY | getattr(os, 'O_NONBLOCK', 0) | getattr(os, 'O_NOFOLLOW', 0))
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            return True
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
        return False
    except FileNotFoundError:
        return False
    except OSError:
        return True
    finally:
        if descriptor is not None:
            os.close(descriptor)


class MenuSessionError(RuntimeError):
    pass


class MenuSession:
    def __init__(self, gateway=None, read_owner=None, read_status=None):
        self.gateway = gateway or CommandGateway()
        self.read_owner = read_owner or self.gateway.read_owner
        self.read_status = read_status or self._status

    def _status(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            success = self.gateway.execute('control', 'status')
        if not success:
            return {}
        try:
            return json.loads(output.getvalue())
        except (ValueError, TypeError):
            return {}

    @staticmethod
    def selection(owner, status):
        state, control = status.get('state') or {}, status.get('control') or {}
        if (not owner or not status.get('active') or not control.get('ready')
                or owner.get('phase') != 'playing'
                or state.get('mode') not in {'normal', 'roulette'}
                or (state.get('owner_pid'), state.get('owner_start')) != owner_key(owner)):
            return None
        fields = ('owner_pid', 'owner_start', 'start_time', 'rom_path')
        identity = {key: state.get(key) for key in fields}
        if (any(not isinstance(value, str) or not value for value in identity.values())
                or any(control.get(key) != value for key, value in identity.items())
                or not isinstance(control.get('generation'), str) or not control['generation']):
            return None
        return dict(identity, generation=control['generation'])

    def _command(self, action, selection):
        # samctl prints its acknowledgement; the shell must see only the lease.
        with contextlib.redirect_stdout(io.StringIO()):
            return self.gateway.execute('control', action,
                                        '--generation', selection['generation'],
                                        '--game-path', selection['rom_path'],
                                        owner={'pid': selection['owner_pid'], 'start': selection['owner_start']})

    def hold(self):
        owner = self.read_owner()
        if owner is None:
            return '-'
        status = self.read_status()
        if (status.get('state') or {}).get('mode') not in {'normal', 'roulette'}:
            raise MenuSessionError('This active mode cannot pause for a menu. Stop SAM first with "m stop", then open the menu.')
        selection = self.selection(owner, status)
        if selection is None:
            raise MenuSessionError('SAM is preparing, loading, or cannot pause this mode. Retry the menu once the game is ready.')
        if status['control'].get('paused') is True:
            return '-'
        if not self._command('pause', selection):
            raise MenuSessionError('SAM did not acknowledge the menu pause. Retry once its current game is ready.')
        after = self.read_status()
        if (self.selection(self.read_owner(), after) != selection
                or after.get('control', {}).get('paused') is not True):
            raise MenuSessionError('SAM changed while pausing the menu; pause state is uncertain. Retry the menu.')
        payload = json.dumps(selection, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
        return base64.urlsafe_b64encode(payload).decode('ascii').rstrip('=')

    def release(self, token):
        if token == '-':
            return
        try:
            if len(token) > 8192:
                raise ValueError('oversized token')
            selection = json.loads(base64.b64decode(token + '=' * (-len(token) % 4), altchars=b'-_', validate=True))
            if (not isinstance(selection, dict)
                    or set(selection) != {'owner_pid', 'owner_start', 'start_time', 'rom_path', 'generation'}
                    or any(not isinstance(value, str) or not value for value in selection.values())):
                raise ValueError('invalid identity')
        except (ValueError, UnicodeError, TypeError):
            raise MenuSessionError('Invalid SAM menu pause token.') from None
        status = self.read_status()
        if (self.selection(self.read_owner(), status) != selection
                or status.get('control', {}).get('paused') is not True):
            return
        if not self._command('resume', selection):
            # A selection change is harmless, but a still-current failed resume
            # needs a clear error so a paused owner is not silently stranded.
            after = self.read_status()
            if (self.selection(self.read_owner(), after) == selection
                    and after.get('control', {}).get('paused') is True):
                raise MenuSessionError('SAM did not acknowledge resume after the menu; use Resume to continue the game.')


def main(argv=None):
    parser = argparse.ArgumentParser(description='Hold or release the current SAM countdown for a menu')
    parser.add_argument('action', choices=('hold', 'release', 'active'))
    parser.add_argument('token', nargs='?')
    args = parser.parse_args(argv)
    if (args.action == 'release') != (args.token is not None):
        parser.error('release requires a token; hold and active take no token')
    if args.action == 'active':
        return 0 if active() else 1
    try:
        session = MenuSession()
        if args.action == 'hold':
            print(session.hold())
        else:
            session.release(args.token)
        return 0
    except (MenuSessionError, OSError) as error:
        print('SAM menu: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
