#!/usr/bin/env python3
"""Install/update a complete SAM release; preserve user configuration and lists."""
import argparse
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
    required = ['MiSTer_SAM_on.sh', 'MiSTer_SAM.ini', 'MiSTer_SAM_install.py',
                '.MiSTer_SAM/lib/modules.sh', '.MiSTer_SAM/lib/engine.sh', '.MiSTer_SAM/lib/cores.sh',
                '.MiSTer_SAM/MiSTer_SAM_MCP.py', '.MiSTer_SAM/samindex', '.MiSTer_SAM/mbc',
                '.MiSTer_SAM/samindex.py', '.MiSTer_SAM/sam_catalog.py', '.MiSTer_SAM/sam_zip.py',
                '.MiSTer_SAM/sam_mgl.py', '.MiSTer_SAM/sam_compat.json',
                '.MiSTer_SAM/zaparoo_catalog.json', '.MiSTer_SAM/zaparoo_catalog_source.json',
                '.MiSTer_SAM/inputs/FDS_input_1234_5678_v3.map',
                '.MiSTer_SAM/modules/commercial_picker.py',
                '.MiSTer_SAM/sam_mcp_process.py', '.MiSTer_SAM/sam_bgm_client.py', '.MiSTer_SAM/lib/session.sh', '.MiSTer_SAM/samctl.py',
                '.MiSTer_SAM/sam/__init__.py', '.MiSTer_SAM/sam/session.py',
                '.MiSTer_SAM/sam/coordinator.py', '.MiSTer_SAM/sam/commands.py',
                '.MiSTer_SAM/sam/menu_session.py',
                '.MiSTer_SAM/sam/autostart.py',
                '.MiSTer_SAM/sam/input_options.py', '.MiSTer_SAM/sam/mcp_console.py',
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
                    'from sam.commands import CommandGateway',
                    str(root / '.MiSTer_SAM')], check=True)
    for path in (root / '.MiSTer_SAM').rglob('*'):
        if not path.is_file():
            continue
        if path.suffix == '.py' or (path.suffix == '.sh' and 'python' in path.read_text(encoding='utf-8').splitlines()[0]):
            ast.parse(path.read_text(encoding='utf-8'), filename=str(path))
        elif path.suffix == '.sh':
            subprocess.run(['bash', '-n', str(path)], check=True)
    subprocess.run(['bash', '-n', str(root / 'MiSTer_SAM_on.sh')], check=True)
    return root


def download_source(work, branch):
    archive = work / 'source.tar.gz'
    url = 'https://codeload.github.com/mrchrisster/MiSTer_SAM/tar.gz/refs/heads/' + branch
    subprocess.run(['curl'] + curl_ca_options() + ['--fail', '--location', '--connect-timeout', '15',
                    '--max-time', '180', '--retry', '2', '-o', str(archive), url], check=True)
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
        return
    # Compare small buffered reads rather than rewriting the entire payload on
    # every update. Never trust equal sizes alone (scripts often keep their size).
    if same_contents(source, target):
        return
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


def install(source, mister, branch):
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
        print('Configuration backup:', saved / 'MiSTer_SAM.ini', flush=True)
    live = mister.resolve() == Path('/media/fat')
    restart_mcp = live and (tmux_exists('MCP') or bool(_mcp_process.processes(payload / 'MiSTer_SAM_MCP.py')))
    if restart_mcp:
        stop_mcp()
    if live and tmux_exists('SAM'):
        subprocess.run(['bash', str(scripts / 'MiSTer_SAM_on.sh'), 'stop'], check=True)

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
        copy_file(path, target)
    for path in (source / '.MiSTer_SAM').rglob('*'):
        if path.is_file() and '__pycache__' not in path.parts and path.suffix != '.pyc':
            copy_file(path, payload / path.relative_to(source / '.MiSTer_SAM'))
    # MGL setnames select separate input profiles (e.g. FDS versus NES).
    # Seed missing mappings for SAM's virtual keyboard only. Preserve existing
    # mappings, including user customizations and physical controller profiles.
    for path in (source / '.MiSTer_SAM/inputs').glob('*_input_1234_5678_v3.map'):
        target = mister / 'config/inputs' / path.name
        if not target.exists():
            copy_file(path, target)
    for name in ['MiSTer_SAM_on.sh', 'MiSTer_SAM_install.py', 'MiSTer_SAM_start.sh', 'MiSTer_SAM_off.sh']:
        if (source / name).is_file():
            copy_file(source / name, scripts / name)
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
    if restart_mcp:
        subprocess.run(['tmux', 'new-session', '-s', 'MCP', '-d', 'exec ' + str(payload / 'MiSTer_SAM_MCP.py')], check=True)
    print('SAM installed. User INI, controller mappings, plug-ins and Ignore lists preserved.')


def main():
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
        if download:
            source = download_source(Path(temp), args.branch)
            # Run the release's installer, not this previously installed copy.
            # Pass the staged source so it does not download again or recurse.
            print('Running installer from downloaded release...', flush=True)
            subprocess.run([sys.executable, str(source / 'MiSTer_SAM_install.py'),
                            '--source-dir', str(source), '--mister-root', str(args.mister_root),
                            '--branch', args.branch], check=True)
        else:
            install(checked_source(args.source_dir), args.mister_root, args.branch)


if __name__ == '__main__':
    main()
