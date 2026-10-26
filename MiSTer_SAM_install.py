#!/usr/bin/env python3
"""Install/update a complete SAM release; preserve user configuration and lists."""
import argparse
from contextlib import contextmanager
import importlib.util
import ast
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time


class UpdateFailure(RuntimeError):
    def __init__(self, message, hints=()):
        super().__init__(message)
        self.hints = hints


class UpdateUI:
    """Short-lived terminal presentation; no log files or background service."""
    def __init__(self, out=None, err=None):
        self.out = out if out is not None else sys.stdout
        self.err = err if err is not None else sys.stderr
        self.live = self.out.isatty() and os.environ.get('TERM', '') != 'dumb'
        self.colour = self.live and 'NO_COLOR' not in os.environ
        self.operation = 'Install'
        self.phase = ''
        self.writes_started = False
        self.sessions_stopped = False
        self.handoff_started = False
        self.frame = False

    def paint(self, text, code):
        return '\033[' + code + 'm' + text + '\033[0m' if self.colour else text

    def begin(self, operation, branch):
        self.operation = operation
        print('\n' + self.paint('MiSTer SAM  |  ' + operation + ' / ' + branch, '1;36'),
              file=self.out, flush=True)

    def stage(self, number, message):
        self.clear()
        self.phase = message.rstrip('.')
        print(self.paint('[%d/4]' % number, '1;36') + '  ' + message, file=self.out, flush=True)

    def note(self, message):
        print('       ' + message, file=self.out, flush=True)

    def downloading(self, archive, elapsed):
        if not self.live:
            return
        try:
            size = archive.stat().st_size
        except OSError:
            size = 0
        spin = '|/-\\'[int(elapsed * 4) % 4]
        print('\r\033[2K       %s  %s received  |  %.0fs' % (spin, format_size(size), elapsed),
              end='', file=self.out, flush=True)
        self.frame = True

    def clear(self):
        if self.frame:
            print('\r\033[2K', end='', file=self.out, flush=True)
            self.frame = False

    def done(self):
        self.clear()
        print('\n' + self.paint(self.operation + ' complete.', '1;32'), file=self.out, flush=True)
        self.note('Your INI, controller mappings, plug-ins and custom lists were preserved.')

    def error(self, error):
        self.clear()
        detail = ' '.join(str(error).split())[:300]
        print('\nSAM %s failed: %s' % (self.operation.lower(), detail), file=self.err, flush=True)
        for hint in getattr(error, 'hints', ()):
            print('  ' + hint, file=self.err)
        if self.writes_started or self.handoff_started:
            print('  The update may be incomplete. Rerun m update to finish.', file=self.err)
        else:
            print('  Installed SAM files were not changed.', file=self.err)
            if self.sessions_stopped:
                print('  SAM/MCP may be stopped; retry the update before restarting.', file=self.err)
        self.err.flush()


def format_size(size):
    return '%.1f MiB' % (size / 1048576) if size >= 1048576 else '%.0f KiB' % (size / 1024)


def download_failure(result, branch):
    code = result.returncode
    detail = (result.stderr or '').lower()
    if code == 60:
        message = 'HTTPS certificate verification failed.'
        if 'not yet valid' in detail:
            message = 'The HTTPS certificate is not yet valid.'
        elif 'expired' in detail:
            message = 'The HTTPS certificate has expired.'
        return UpdateFailure(message, (
            'Device time: ' + time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime()),
            'Check date -u; if the clock is wrong, allow network time to synchronize.',
            'If time is correct, check the trusted CA bundle. Then retry m update.'))
    messages = {5: 'The network proxy could not be resolved.',
                6: 'GitHub could not be resolved. Check the network and DNS.',
                7: 'Could not connect to GitHub. Check the network connection.',
                18: 'The release download was incomplete. Please retry.',
                23: 'Cannot write the temporary download. Check free space in /tmp.',
                28: 'The GitHub download timed out. Check the connection and retry.',
                35: 'Could not establish a secure connection to GitHub.',
                77: 'Cannot read the trusted CA certificates. Check the CA bundle.'}
    if code == 22:
        http = (result.stdout or '').strip()
        status = 'HTTP ' + http if re.fullmatch(r'[1-5][0-9]{2}', http) else 'an HTTP error'
        return UpdateFailure('GitHub returned ' + status + '.', ('Check that branch "' + branch + '" exists, then retry. ',))
    return UpdateFailure(messages.get(code, 'Release download failed (curl exit %s).' % code))


def run_download(command, archive, progress):
    started = time.monotonic()
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        while True:
            try:
                out, err = process.communicate(timeout=.25 if progress.live else 190)
                return subprocess.CompletedProcess(command, process.returncode, out, err)
            except subprocess.TimeoutExpired:
                elapsed = time.monotonic() - started
                if elapsed >= 190:
                    process.kill()
                    out, err = process.communicate(timeout=5)
                    return subprocess.CompletedProcess(command, 28, out, err)
                progress.downloading(archive, elapsed)
    finally:
        if process.poll() is None:
            process.kill()
            process.communicate(timeout=5)
        progress.clear()


_mcp_process = None

def mcp_helper(root=None):
    global _mcp_process
    if _mcp_process is None or root is not None:
        path = (root or Path(__file__).parent) / '.MiSTer_SAM/sam_mcp_process.py'
        spec = importlib.util.spec_from_file_location('sam_mcp_process', path)
        _mcp_process = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(_mcp_process)
    return _mcp_process

CA_BUNDLES = ('/media/fat/Scripts/.config/downloader/cacert.pem',
              '/etc/ssl/cert.pem', '/etc/ssl/certs/cacert.pem')


def curl_ca_options():
    # MiSTer's curl defaults to a certificate directory without hashed links.
    # Prefer its maintained Downloader bundle, and respect an explicit override.
    if os.environ.get('CURL_CA_BUNDLE'):
        return []
    for name in CA_BUNDLES:
        if Path(name).is_file() and os.access(name, os.R_OK):
            return ['--cacert', name]
    return []


def checked_source(root):
    required = ['MiSTer_SAM_on.sh', 'MiSTer_SAM_start.sh', 'MiSTer_SAM.ini', 'MiSTer_SAM_install.py',
                '.MiSTer_SAM/lib/modules.sh', '.MiSTer_SAM/lib/engine.sh', '.MiSTer_SAM/lib/cores.sh',
                '.MiSTer_SAM/lib/core-registry.sh', '.MiSTer_SAM/lib/bootstrap.sh',
                '.MiSTer_SAM/lib/controller-client.sh', '.MiSTer_SAM/lib/engine-hosted.sh',
                '.MiSTer_SAM/lib/engine-adapter.sh', '.MiSTer_SAM/lib/session-view.sh',
                '.MiSTer_SAM/sam/controller.py', '.MiSTer_SAM/sam/controller_guardian.py',
                '.MiSTer_SAM/sam/session_engine.py',
                '.MiSTer_SAM/MiSTer_SAM_MCP.py', '.MiSTer_SAM/samindex', '.MiSTer_SAM/mbc',
                '.MiSTer_SAM/samindex.py', '.MiSTer_SAM/sam_catalog.py', '.MiSTer_SAM/sam_zip.py',
                '.MiSTer_SAM/sam_mgl.py', '.MiSTer_SAM/sam_compat.json',
                '.MiSTer_SAM/zaparoo_catalog.json', '.MiSTer_SAM/zaparoo_catalog_source.json',
                '.MiSTer_SAM/inputs/FDS_input_1234_5678_v3.map',
                '.MiSTer_SAM/modules/commercial_picker.py',
                '.MiSTer_SAM/sam_mcp_process.py', '.MiSTer_SAM/sam_bgm_client.py', '.MiSTer_SAM/lib/session.sh', '.MiSTer_SAM/samctl.py',
                '.MiSTer_SAM/sam/__init__.py', '.MiSTer_SAM/sam/session.py',
                '.MiSTer_SAM/sam/coordinator.py', '.MiSTer_SAM/sam/commands.py',
                '.MiSTer_SAM/sam/menu_session.py', '.MiSTer_SAM/sam/ui_start.py',
                '.MiSTer_SAM/lib/caller.sh', '.MiSTer_SAM/lib/runtime.sh',
                '.MiSTer_SAM/lib/monitor.sh', '.MiSTer_SAM/lib/core-names.sh',
                '.MiSTer_SAM/lib/data.sh',
                '.MiSTer_SAM/sam/autostart.py',
                '.MiSTer_SAM/sam/input_options.py', '.MiSTer_SAM/sam/mcp_console.py',
                '.MiSTer_SAM/sam/input_display.py',
                '.MiSTer_SAM/sam/diagnostics.py', '.MiSTer_SAM/lib/diagnostics.sh',
                '.MiSTer_SAM/lib/config-reload.sh', '.MiSTer_SAM/sam/config_reload.py',
                '.MiSTer_SAM/modules/category.sh', '.MiSTer_SAM/modules/category_filter.py',
                '.MiSTer_SAM/modules/category-aliases.json',
                '.MiSTer_SAM/sam_titles.py', '.MiSTer_SAM/sam_kids_filter.py']
    if not all((root / name).is_file() for name in required):
        raise RuntimeError('Release is incomplete; installed files were not changed.')
    # Validate the exact catalog/policy bundle before backing up configuration
    # or stopping sessions. Import from this release in a fresh interpreter.
    subprocess.run([sys.executable, '-c',
                    'import sys; sys.path.insert(0, sys.argv[1]); '
                    'from sam_catalog import Catalog; Catalog(); '
                    'from sam.session import SessionSnapshot; '
                    'from sam.coordinator import LifecycleCoordinator; '
                    'from sam.ui_start import blocked; '
                    'from sam.commands import CommandGateway',
                    str(root / '.MiSTer_SAM')], check=True, capture_output=True, text=True)
    for path in (root / '.MiSTer_SAM').rglob('*'):
        if not path.is_file():
            continue
        if path.suffix == '.py' or (path.suffix == '.sh' and 'python' in path.read_text(encoding='utf-8').splitlines()[0]):
            ast.parse(path.read_text(encoding='utf-8'), filename=str(path))
        elif path.suffix == '.sh':
            subprocess.run(['bash', '-n', str(path)], check=True, capture_output=True, text=True)
    subprocess.run(['bash', '-n', str(root / 'MiSTer_SAM_on.sh')], check=True, capture_output=True, text=True)
    return root


def download_source(work, branch, progress=None):
    progress = progress or UpdateUI()
    archive = work / 'source.tar.gz'
    url = 'https://codeload.github.com/mrchrisster/MiSTer_SAM/tar.gz/refs/heads/' + branch
    progress.stage(1, 'Downloading the latest release from GitHub...')
    started = time.monotonic()
    command = ['curl'] + curl_ca_options() + ['--silent', '--show-error', '--fail', '--location',
               '--proto', '=https', '--proto-redir', '=https', '--connect-timeout', '15',
               '--max-time', '180', '--retry', '2', '--retry-max-time', '180',
               '--write-out', '%{http_code}', '-o', str(archive), url]
    result = run_download(command, archive, progress)
    if result.returncode:
        archive.unlink(missing_ok=True)
        raise download_failure(result, branch)
    progress.note('%s downloaded in %.1fs.' % (format_size(archive.stat().st_size), time.monotonic() - started))
    progress.stage(2, 'Checking the archive and validating scripts...')
    with tarfile.open(archive) as bundle:
        for item in bundle.getmembers():
            parts = Path(item.name).parts
            if item.name.startswith('/') or '..' in parts or not (item.isfile() or item.isdir()):
                raise RuntimeError('Invalid release archive; installed files were not changed.')
        bundle.extractall(work)
    roots = [p for p in work.iterdir() if p.is_dir() and (p / 'MiSTer_SAM_on.sh').is_file()]
    if len(roots) != 1:
        raise RuntimeError('Release archive has no unique SAM source directory.')
    return checked_source(roots[0])


def tmux_exists(name):
    return subprocess.run(['tmux', 'has-session', '-t', name], stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode == 0


def stop_mcp(script=Path('/media/fat/Scripts/.MiSTer_SAM/MiSTer_SAM_MCP.py')):
    mcp_helper().stop(script)
    # MCP can exit between any two tmux commands. A vanished session means
    # shutdown succeeded; only a session that remains running blocks the update.
    subprocess.run(['tmux', 'send-keys', '-t', 'MCP', 'C-c'], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    until = time.monotonic() + 2
    while time.monotonic() < until and tmux_exists('MCP'):
        time.sleep(.1)
    if not tmux_exists('MCP'):
        return
    stopped = subprocess.run(['tmux', 'kill-session', '-t', 'MCP'], check=False,
                             stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    if tmux_exists('MCP'):
        detail = stopped.stderr.strip() or 'session is still running'
        raise RuntimeError('Cannot stop MCP for update: ' + detail)


def copy_file(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    if source.resolve() == target.resolve():
        return False
    # Compare small buffered reads rather than rewriting the entire payload on
    # every update. Never trust equal sizes alone (scripts often keep their size).
    if same_contents(source, target):
        return False
    # Publish each complete file on its target filesystem. A failed copy leaves
    # the previous file intact; ownership changes are unsupported by FAT.
    fd, name = tempfile.mkstemp(prefix='.' + target.name + '.', dir=target.parent)
    staged = Path(name)
    try:
        with os.fdopen(fd, 'wb') as output, source.open('rb') as incoming:
            shutil.copyfileobj(incoming, output, 65536)
        staged.chmod(source.stat().st_mode & 0o777)
        os.replace(staged, target)
    finally:
        staged.unlink(missing_ok=True)
    return True


def same_contents(source, target):
    if not target.is_file() or source.stat().st_size != target.stat().st_size:
        return False
    with source.open('rb') as left, target.open('rb') as right:
        while True:
            chunk = left.read(65536)
            if chunk != right.read(65536):
                return False
            if not chunk:
                return True


def write_changed(target, contents):
    if target.is_file() and target.read_text(encoding='utf-8') == contents:
        return
    target.write_text(contents, encoding='utf-8')


def live_session(runtime=Path('/tmp/.SAM_tmp'), proc=Path('/proc')):
    owner = runtime / 'session-owner'
    if owner.is_symlink():
        raise UpdateFailure('Cannot verify the SAM owner for update.')
    if not owner.exists():
        return False
    if owner.is_symlink() or not owner.is_file() or owner.stat().st_size > 4096:
        raise UpdateFailure('Cannot verify the SAM owner for update.')
    try:
        fields = dict(line.split('=', 1) for line in owner.read_text().splitlines())
        pid, start = fields['pid'], fields['start']
        if not re.fullmatch(r'[1-9][0-9]*', pid) or not start.isascii() or not start.isdigit():
            raise ValueError('Invalid owner identity')
        current = (proc / pid / 'stat').read_text().rsplit(') ', 1)[1].split()
        return current[0] not in ('Z', 'X', 'x') and current[19] == start
    except FileNotFoundError:
        return False
    except (OSError, ValueError, KeyError, IndexError):
        raise UpdateFailure('Cannot verify the SAM owner for update.')


@contextmanager
def update_admission(live, runtime=None):
    if not live:
        yield
        return
    import fcntl
    runtime = Path(runtime or os.environ.get('SAM_TMP_ROOT', '/tmp/.SAM_tmp'))
    runtime.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(runtime / 'session-start.lock', os.O_CREAT | os.O_RDWR |
                         getattr(os, 'O_NOFOLLOW', 0), 0o600)
    deadline = time.monotonic() + 15
    try:
        while True:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise UpdateFailure('SAM startup is still busy; retry the update when it finishes.')
                time.sleep(.05)
        yield
    finally:
        os.close(descriptor)


def install(source, mister, branch, progress=None):
    progress = progress or UpdateUI()
    progress.stage(3, 'Protecting your settings and installing the update...')
    mcp_helper(source)
    scripts = mister / 'Scripts'
    scripts.mkdir(parents=True, exist_ok=True)
    payload = scripts / '.MiSTer_SAM'
    ini = scripts / 'MiSTer_SAM.ini'
    # Only configuration needs an automatic backup. Do not walk installed
    # caches, generated lists, binaries or historical backup directories.
    # Finish this copy before stopping sessions or changing installed files.
    if ini.is_file():
        backup_root = scripts / '.SAM_refactor_backups'
        backup_root.mkdir(parents=True, exist_ok=True)
        saved = Path(tempfile.mkdtemp(prefix='install-' + time.strftime('%Y%m%d-%H%M%S') + '-',
                                      dir=backup_root))
        copy_file(ini, saved / 'MiSTer_SAM.ini')
        progress.note('INI backup: ' + str(saved / 'MiSTer_SAM.ini'))
    live = mister.resolve() == Path('/media/fat')
    # Stop cannot race MCP's next automatic admission. Menu updates already
    # own menu.lock; this separate short transition lock works for both callers.
    with update_admission(live):
        restart_mcp = live and (tmux_exists('MCP') or bool(_mcp_process.processes(payload / 'MiSTer_SAM_MCP.py')))
        if live and (live_session() or tmux_exists('SAM')):
            progress.note('Stopping SAM and returning to Menu before replacing files...')
            progress.sessions_stopped = True
            subprocess.run(['bash', str(scripts / 'MiSTer_SAM_on.sh'), 'stop'], check=True,
                           capture_output=True, text=True, timeout=45)
        if restart_mcp:
            progress.note('Stopping the input/idle monitor safely...')
            progress.sessions_stopped = True
            stop_mcp()
        if live and (live_session() or Path('/tmp/.SAM_tmp/cleanup-failure').exists()):
            raise UpdateFailure('SAM cleanup is still pending; retry when it finishes.')

    progress.writes_started = True
    progress.note('Updating scripts and shipped lists; keeping custom files...')
    updated = unchanged = 0
    public = mister / 'SAM'
    for name in ['Gamelists', 'Rated', 'Blacklists', 'Ignore']:
        (public / name).mkdir(parents=True, exist_ok=True)
    legacy = payload / 'SAM_Gamelists'
    for old in legacy.glob('*_excludelist.txt'):
        destination = public / 'Ignore' / old.name
        existing = destination.read_text(encoding='utf-8') if destination.exists() else ''
        lines = existing.splitlines()
        for line in old.read_text(encoding='utf-8').splitlines():
            if line not in lines:
                lines.append(line)
        write_changed(destination, '\n'.join(lines) + '\n')
    for name in ['m82_list.txt', 'sam_goat_list_custom.txt']:
        old, target = legacy / name, public / 'Gamelists' / name
        if old.is_file() and not target.exists():
            copy_file(old, target)
    for path in (source / 'SAM').rglob('*'):
        if not path.is_file():
            continue
        relative = path.relative_to(source / 'SAM')
        target = public / relative
        if relative.parts[0] in {'Ignore', 'Gamelists'} and target.exists():
            continue
        if copy_file(path, target): updated += 1
        else: unchanged += 1
    for path in (source / '.MiSTer_SAM').rglob('*'):
        if path.is_file() and '__pycache__' not in path.parts and path.suffix != '.pyc':
            if copy_file(path, payload / path.relative_to(source / '.MiSTer_SAM')): updated += 1
            else: unchanged += 1
    # MGL setnames select separate input profiles (e.g. FDS versus NES).
    # Seed missing mappings for SAM's virtual keyboard only. Preserve existing
    # mappings, including user customizations and physical controller profiles.
    for path in (source / '.MiSTer_SAM/inputs').glob('*_input_1234_5678_v3.map'):
        target = mister / 'config/inputs' / path.name
        if not target.exists():
            copy_file(path, target)
    for name in ['MiSTer_SAM_on.sh', 'MiSTer_SAM_install.py', 'MiSTer_SAM_start.sh', 'MiSTer_SAM_off.sh']:
        if (source / name).is_file():
            if copy_file(source / name, scripts / name): updated += 1
            else: unchanged += 1
            (scripts / name).chmod(0o755)
    if not ini.exists():
        copy_file(source / 'MiSTer_SAM.ini', ini)
    contents = ini.read_text(encoding='utf-8')
    contents, changed = re.subn(r'^branch=.*$', 'branch="' + branch + '"', contents, flags=re.M)
    if not changed:
        contents += '\nbranch="' + branch + '"\n'
    write_changed(ini, contents)
    write_changed(payload / 'release-branch', branch + '\n')
    for name in ['samindex', 'mbc', 'mplayer', 'MiSTer_SAM_init', 'MiSTer_SAM_MCP.py']:
        path = payload / name
        if path.is_file():
            path.chmod(0o755)
    (payload / 'partun').unlink(missing_ok=True)
    progress.note('%d files updated; %d already current.' % (updated, unchanged))
    progress.stage(4, 'Finishing up...')
    if restart_mcp:
        progress.note('Restarting the input/idle monitor...')
        subprocess.run(['tmux', 'new-session', '-s', 'MCP', '-d', 'exec ' + str(payload / 'MiSTer_SAM_MCP.py')], check=True)
    progress.done()
    if live:
        progress.note('Start SAM: MiSTer_SAM_on.sh start')


def main(progress=None):
    progress = progress or UpdateUI()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--download', action='store_true', help='Fetch a complete release from GitHub')
    parser.add_argument('--branch', default=os.environ.get('SAM_INSTALL_BRANCH', 'test'))
    parser.add_argument('--source-dir', type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument('--mister-root', type=Path, default=Path('/media/fat'))
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_-][A-Za-z0-9_./-]*', args.branch) or '..' in args.branch:
        parser.error('Invalid branch name')
    with tempfile.TemporaryDirectory(prefix='sam-install-') as temp:
        download = args.download or not (args.source_dir / '.MiSTer_SAM/lib/modules.sh').is_file()
        handoff = os.environ.get('SAM_INSTALL_HANDOFF') == '1'
        progress.operation = 'Update' if download or handoff else 'Install'
        if not handoff:
            progress.begin(progress.operation, args.branch)
        if download:
            source = download_source(Path(temp), args.branch, progress)
            # Run the release's installer, not this previously installed copy.
            # Pass the staged source so it does not download again or recurse.
            progress.handoff_started = True
            result = subprocess.run([sys.executable, str(source / 'MiSTer_SAM_install.py'),
                            '--source-dir', str(source), '--mister-root', str(args.mister_root),
                            '--branch', args.branch], env=dict(os.environ, SAM_INSTALL_HANDOFF='1'),
                            stderr=subprocess.PIPE, text=True)
            if result.returncode and 'Traceback (most recent call last)' in (result.stderr or ''):
                raise UpdateFailure('The downloaded installer failed (exit %s).' % result.returncode)
            if result.stderr:
                print(result.stderr, end='', file=progress.err, flush=True)
            return result.returncode
        else:
            if not handoff:
                progress.stage(1, 'Using the local release; no download needed.')
                progress.stage(2, 'Validating the release and scripts...')
            install(checked_source(args.source_dir), args.mister_root, args.branch, progress)
    return 0


def cli():
    progress = UpdateUI()
    try:
        return main(progress)
    except KeyboardInterrupt:
        progress.error(UpdateFailure('Cancelled.'))
        return 130
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or '').strip().splitlines()
        summary = detail[-1] if detail else 'command exited with status %s' % error.returncode
        progress.error(UpdateFailure('%s: %s' % (progress.phase or 'Installer command failed', summary)))
    except subprocess.TimeoutExpired:
        progress.error(UpdateFailure('Timed out waiting for SAM cleanup.',
                                     ('Run MiSTer_SAM_on.sh diagnostics, then retry the update.',)))
    except (OSError, RuntimeError, tarfile.TarError, SyntaxError, UnicodeError, ValueError) as error:
        progress.error(error)
    return 1


if __name__ == '__main__':
    raise SystemExit(cli())
