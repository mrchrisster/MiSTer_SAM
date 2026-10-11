# SPDX-License-Identifier: GPL-3.0-or-later
"""Fail-open, bounded RAM-only decision history; never an input-sample log."""
import datetime
import json
from itertools import islice
import os
from pathlib import Path
import stat
import tempfile
import time

try:
    import fcntl
except ImportError:
    fcntl = None

MAX_FILE_BYTES = 128 * 1024
MAX_LINE_BYTES = 4096
MAX_UPLOAD_BYTES = 512 * 1024
DEFAULT_UPLOAD_URL = 'https://0x0.st/'
FALLBACK_UPLOAD_URL = 'https://paste.rs/'


def _safe_value(value, depth=0):
    if value is None or isinstance(value, bool):
        return value
    if isinstance(value, int):
        return value if abs(value) < 10 ** 24 else str(value)[:128]
    if isinstance(value, float):
        return str(value)[:128]
    if isinstance(value, str):
        return value[:512]
    if depth < 2 and isinstance(value, dict):
        return {str(k)[:64]: _safe_value(v, depth + 1) for k, v in islice(value.items(), 16)}
    if depth < 2 and isinstance(value, (list, tuple)):
        return [_safe_value(v, depth + 1) for v in value[:16]]
    return str(value)[:512]


def _ram_path(runtime):
    resolved = os.path.realpath(os.fspath(runtime))
    base = os.path.realpath(tempfile.gettempdir()) if os.name == 'nt' else '/tmp'
    return resolved if os.path.commonpath((resolved, base)) == base else None


def _open_regular(path, flags, mode=0o600):
    fd = os.open(path, flags | getattr(os, 'O_NOFOLLOW', 0) | getattr(os, 'O_NONBLOCK', 0), mode)
    if not stat.S_ISREG(os.fstat(fd).st_mode):
        os.close(fd)
        raise OSError('diagnostic path is not regular')
    return fd


class DiagnosticLog:
    """emit(component, event, owner='', **fields) returns whether it was recorded.

    ``owner`` is the caller's captured immutable ``pid:start`` identity. A busy
    cross-process lock drops the event immediately. No worker thread is created.
    """
    def __init__(self, runtime):
        try:
            root = _ram_path(runtime)
            self.directory = Path(root) / 'diagnostics' if root else None
        except (OSError, ValueError, TypeError):
            self.directory = None

    def emit(self, component, event, owner='', **fields):
        lock = descriptor = None
        try:
            if self.directory is None or fcntl is None:
                return False
            record = dict(timestamp=int(time.time()), component=str(component)[:64],
                          event=str(event)[:96], owner=str(owner)[:64],
                          fields=_safe_value(fields))
            line = (json.dumps(record, ensure_ascii=True, separators=(',', ':'), allow_nan=False) + '\n').encode('utf-8')
            if len(line) > MAX_LINE_BYTES:
                record['fields'] = {'truncated': True}
                line = (json.dumps(record, ensure_ascii=True, separators=(',', ':')) + '\n').encode('utf-8')
            if _ram_path(self.directory) is None:
                return False
            self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
            # Recheck resolved containment after mkdir; never follow a redirected
            # diagnostics directory onto SD. Lock files are retained across rotate.
            if _ram_path(self.directory) is None:
                return False
            lock = _open_regular(self.directory / 'events.lock', os.O_RDWR | os.O_CREAT)
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            path = self.directory / 'events.jsonl'
            descriptor = _open_regular(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT)
            if os.fstat(descriptor).st_size > MAX_FILE_BYTES:
                os.ftruncate(descriptor, 0)
            if os.fstat(descriptor).st_size + len(line) > MAX_FILE_BYTES:
                os.close(descriptor)
                descriptor = None
                os.replace(path, self.directory / 'events.1.jsonl')
                descriptor = _open_regular(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT)
            return os.write(descriptor, line) == len(line)
        except Exception:
            # Diagnostics cannot interfere with lifecycle decisions or dispatch.
            return False
        finally:
            for fd in (descriptor, lock):
                if fd is not None:
                    try:
                        os.close(fd)
                    except OSError:
                        pass


def _bounded_read(path, maximum):
    fd = None
    try:
        fd = _open_regular(path, os.O_RDONLY)
        return os.read(fd, maximum)
    except OSError:
        return b''
    finally:
        if fd is not None:
            os.close(fd)


def render_history(runtime, limit=40, verbose=False):
    """Read only bounded literal RAM diagnostics, returning human-readable lines."""
    root = _ram_path(runtime)
    if not root:
        return 'Diagnostics unavailable: runtime must be in RAM temporary storage.'
    directory = Path(root) / 'diagnostics'
    if _ram_path(directory) is None:
        return 'Diagnostics unavailable: history directory is outside RAM storage.'
    output = []
    for name in ('last-exit.json', 'last-failure.json'):
        data = _bounded_read(directory / name, MAX_LINE_BYTES)
        if data:
            try:
                value = json.loads(data.decode('utf-8', 'replace'))
                fields = value.get('fields', {})
                stamp = datetime.datetime.fromtimestamp(int(value['timestamp']), datetime.timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')
                output.append('{}: {} owner={} status={} cleanup={} reason={}'.format(
                    name, stamp, value.get('owner', ''), fields.get('status', '?'),
                    fields.get('cleanup_status', '?'), fields.get('reason', '?')))
                output.append('  mode={} phase={} core={} game={}'.format(fields.get('mode', ''),
                    fields.get('phase', ''), fields.get('core', ''), fields.get('game', '')))
                if fields.get('rom_path'):
                    output.append('  ROM: ' + str(fields['rom_path']))
            except (OSError, ValueError, KeyError, TypeError, AttributeError, OverflowError, UnicodeError):
                output.append(name + ': invalid or truncated record')
    events = []
    invalid = 0
    for name in ('events.1.jsonl', 'events.jsonl'):
        data = _bounded_read(directory / name, MAX_FILE_BYTES)
        for raw in data.splitlines(keepends=True):
            try:
                if len(raw) > MAX_LINE_BYTES or not raw.endswith(b'\n'):
                    raise ValueError('truncated')
                record = json.loads(raw.decode('utf-8', 'replace'))
                timestamp = datetime.datetime.fromtimestamp(int(record['timestamp']), datetime.timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')
                events.append('{} {} {} owner={} {}'.format(timestamp, record['component'], record['event'], record.get('owner', ''), json.dumps(record.get('fields', {}), ensure_ascii=True)))
            except (OSError, ValueError, TypeError, KeyError, OverflowError, UnicodeError):
                invalid += 1
    output.extend(events[-max(1, min(int(limit), 200)):])
    if invalid:
        output.append('{} invalid/truncated diagnostic lines ignored'.format(invalid))
    if verbose:
        debug = []
        for name in ('debug.1.log', 'debug.log'):
            debug.extend(_bounded_read(directory/name, MAX_FILE_BYTES).decode('utf-8', 'replace').splitlines())
        if debug:
            output.append('Recent verbose SAM debug:')
            output.extend(debug[-40:])
        else:
            output.append('No verbose SAM debug recorded; set samdebuglog="Yes" to enable it.')
    return '\n'.join(output) or 'No diagnostic history recorded this boot.'


def build_upload_log(runtime):
    """One bounded, readable log; no INI dump or ROM-content inspection."""
    import hashlib
    import platform
    import re
    root = Path(__file__).resolve().parents[1]
    lines = ['MiSTer SAM diagnostics', 'Captured: ' + datetime.datetime.now(datetime.timezone.utc).isoformat(),
             'Platform: ' + platform.machine() + ' / ' + platform.release()]
    for name, path in (('MiSTer_SAM_on.sh', root.parent/'MiSTer_SAM_on.sh'),
                       ('MiSTer_SAM_install.py', root.parent/'MiSTer_SAM_install.py'),
                       ('MiSTer_SAM_MCP.py', root/'MiSTer_SAM_MCP.py')):
        try:
            with path.open('rb') as source:
                data = source.read(512 * 1024 + 1)
            if len(data) <= 512 * 1024:
                lines.append(name + ' SHA256: ' + hashlib.sha256(data).hexdigest())
        except OSError:
            pass
    lines.append('INI contents omitted. Storage paths and credential-like values are filtered.')
    text = render_history(runtime, 200, verbose=True)
    # Reports are plain text, never evaluated. Do not expose mounted collection
    # paths or obvious credentials from an optional debug/error message.
    text = re.sub(r'/(?:media|home|root|mnt|tmp)/[^\n\r,;]*', '[path omitted]', text)
    text = re.sub(r'''(?ix)((?:password|passwd|token|secret|api[_-]?key|authorization)\s*["']?\s*[=:]\s*)
                  (?:(?:Bearer|Basic)\s+[^\s,;]+|"(?:\\.|[^"\\\r\n])*"|'(?:\\.|[^'\\\r\n])*'|[^\s,;]+)''',
                  r'\1[redacted]', text)
    lines.extend(('', text))
    data = ('\n'.join(lines) + '\n').encode('utf-8', 'replace')
    return data[:MAX_UPLOAD_BYTES].decode('utf-8', 'ignore').encode('utf-8')


class UploadFailure(RuntimeError):
    """Only availability failures allow trying the default backup service."""
    def __init__(self, message, unavailable=False):
        super().__init__(message)
        self.unavailable = unavailable


def upload_log(runtime, endpoint, data=None):
    """Verified HTTPS upload, using each provider's actual wire protocol."""
    import re
    import secrets
    import ssl
    from urllib.error import HTTPError, URLError
    from urllib.request import Request, urlopen
    from urllib.parse import urlsplit
    parsed = urlsplit(endpoint)
    loopback = parsed.hostname in ('127.0.0.1', 'localhost', '::1')
    if (parsed.scheme != 'https' and not (parsed.scheme == 'http' and loopback)) or not parsed.hostname:
        raise ValueError('Use an HTTPS log-upload URL.')
    if parsed.username or parsed.password or parsed.fragment or parsed.query:
        raise ValueError('Upload URL must not contain credentials, query parameters or fragments.')
    if data is None:
        data = build_upload_log(runtime)
    ca = os.environ.get('CURL_CA_BUNDLE')
    if not ca:
        for path in ('/media/fat/Scripts/.config/downloader/cacert.pem', '/etc/ssl/cert.pem', '/etc/ssl/certs/cacert.pem'):
            if os.path.isfile(path) and os.access(path, os.R_OK):
                ca = path; break
    raw_paste = parsed.hostname == 'paste.rs' and parsed.path in ('', '/')
    body, content_type = data, 'text/plain; charset=utf-8'
    if not raw_paste:
        boundary = 'sam-' + secrets.token_hex(16)
        prefix = '--' + boundary + '\r\n'
        parts = [(prefix + 'Content-Disposition: form-data; name="file"; filename="sam-diagnostics.log"\r\n'
                  'Content-Type: text/plain\r\n\r\n').encode('ascii') + data + b'\r\n']
        if parsed.hostname == '0x0.st':
            for name, value in (('secret', ''), ('expires', '168')):
                parts.append((prefix + 'Content-Disposition: form-data; name="' + name + '"\r\n\r\n' + value + '\r\n').encode('ascii'))
        body = b''.join(parts) + ('--' + boundary + '--\r\n').encode('ascii')
        content_type = 'multipart/form-data; boundary=' + boundary
    request = Request(endpoint, data=body, headers={
        'Content-Type': content_type,
        'User-Agent': 'MiSTer-SAM-diagnostics (+https://github.com/mrchrisster/MiSTer_SAM)'}, method='POST')
    try:
        # No insecure SSL context and no temporary upload file. Only the response
        # prefix is read, even if a misconfigured endpoint returns a large body.
        with urlopen(request, context=ssl.create_default_context(cafile=ca), timeout=30) as response:
            final = urlsplit(response.geturl())
            if final.scheme != 'https' and not (loopback and final.hostname in ('127.0.0.1', 'localhost', '::1')):
                raise RuntimeError('Upload service redirected outside secure transport.')
            if raw_paste and response.status != 201:
                raise UploadFailure('Upload service did not store the complete log (HTTP %s); local history was retained.' % response.status)
            reply = response.read(8193)
    except HTTPError as error:
        error.close()
        raise UploadFailure('Upload service returned HTTP %s; local history was retained.' % error.code,
                            unavailable=500 <= error.code <= 599) from None
    except (ssl.SSLError, URLError, TimeoutError) as error:
        if 'certificate' in str(error).lower():
            raise UploadFailure('HTTPS certificate check failed. Check date -u and the CA bundle; local history was retained.') from None
        tls_error = isinstance(error, ssl.SSLError) or isinstance(getattr(error, 'reason', None), ssl.SSLError)
        raise UploadFailure('Could not reach the upload service; local history was retained.', unavailable=not tls_error) from None
    if len(reply) > 8192:
        raise RuntimeError('Upload service returned an oversized response.')
    url = reply.decode('utf-8').strip()
    link = urlsplit(url)
    if len(url) > 2048 or re.search(r'\s', url) or link.username or link.password or not link.hostname:
        raise RuntimeError('Upload service did not return a valid log URL.')
    if link.scheme != 'https' and not (loopback and link.scheme == 'http' and link.hostname in ('127.0.0.1', 'localhost', '::1')):
        raise RuntimeError('Upload service did not return a secure log URL.')
    return url


def main(argv=None):
    import argparse
    parser = argparse.ArgumentParser(description='Show bounded SAM RAM diagnostic history.')
    parser.add_argument('--runtime', default='/tmp/.SAM_tmp')
    parser.add_argument('--limit', type=int, default=40)
    parser.add_argument('--verbose', action='store_true')
    parser.add_argument('--preview', action='store_true', help='Show the exact filtered upload content without sending it.')
    parser.add_argument('--upload', nargs='?', const='', metavar='URL',
                        help='Upload filtered logs to 0x0.st, with paste.rs as an outage fallback (or use a custom URL).')
    args = parser.parse_args(argv)
    if args.preview:
        print(build_upload_log(args.runtime).decode('utf-8'))
        return 0
    if args.upload is not None:
        endpoint = args.upload or os.environ.get('SAM_LOG_UPLOAD_URL', DEFAULT_UPLOAD_URL)
        use_fallback = not args.upload and 'SAM_LOG_UPLOAD_URL' not in os.environ
        try:
            print('Uploading filtered diagnostics. Anyone with the returned link can read them.', flush=True)
            print('INI contents omitted; storage paths filtered. Use --preview to review without uploading.', flush=True)
            # Snapshot once so a failed attempt and its fallback share exactly
            # the same filtered contents; everything stays in RAM.
            data = build_upload_log(args.runtime)
            try:
                url = upload_log(args.runtime, endpoint, data=data)
            except UploadFailure as error:
                if not use_fallback or not error.unavailable:
                    raise
                print('0x0.st is unavailable. Trying paste.rs once; this service has no requested automatic expiry.', flush=True)
                url = upload_log(args.runtime, FALLBACK_UPLOAD_URL, data=data)
            print('Log URL: ' + url)
        except (OSError, RuntimeError, ValueError, UnicodeError) as error:
            print('Unable to upload log: ' + str(error))
            return 1
        return 0
    try:
        print(render_history(args.runtime, args.limit, args.verbose))
        print('\nUpload log: m diagnostics --upload | Review first: m diagnostics --preview')
    except (OSError, ValueError, TypeError):
        print('Diagnostic history unavailable.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
