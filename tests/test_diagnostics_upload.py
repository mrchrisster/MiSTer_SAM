"""Upload fixtures use temporary data and localhost only; never public uploads."""
import contextlib
import io
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import ssl
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError
from paths import PACKAGE
sys.path.insert(0, str(PACKAGE / '.MiSTer_SAM'))
from sam import diagnostics


class Reply(io.BytesIO):
    def __init__(self, value, url='https://logs.example.test/result'):
        super().__init__(value)
        self.url = url
        self.read_sizes = []

    def geturl(self):
        return self.url

    def read(self, size=-1):
        self.read_sizes.append(size)
        return super().read(size)


class UploadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.runtime = self.temp.name
        self.directory = Path(self.runtime) / 'diagnostics'
        self.directory.mkdir()
        self.record = dict(timestamp=0, component='SAM', event='exit', owner='12:34', fields=dict(status='success', reason='requested', phase='playing'))
        (self.directory / 'events.jsonl').write_text(json.dumps(self.record) + '\n', encoding='utf-8')
        # Disable host/real MiSTer CA probing. HTTPS tests use the host's default
        # trust store; no actual request leaves the process except localhost.
        self.addCleanup(patch.stopall)
        patch('sam.diagnostics.os.path.isfile', return_value=False).start()
        patch.dict('os.environ', {'CURL_CA_BUNDLE': ''}).start()

    def test_actual_local_multipart_upload(self):
        captured = {}

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                length = int(self.headers['Content-Length'])
                captured['body'] = self.rfile.read(length)
                captured['type'] = self.headers['Content-Type']
                captured['path'] = self.path
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'https://logs.example.test/local-fixture\n')

            def log_message(self, *args):
                pass

        server = HTTPServer(('127.0.0.1', 0), Handler)
        server.timeout = 1
        thread = threading.Thread(target=server.serve_forever, kwargs={'poll_interval': 0.05}, daemon=True)
        thread.start()
        try:
            endpoint = 'http://127.0.0.1:%d/upload' % server.server_port
            result = diagnostics.upload_log(self.runtime, endpoint)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
        self.assertFalse(thread.is_alive())
        self.assertEqual(result, 'https://logs.example.test/local-fixture')
        self.assertEqual(captured['path'], '/upload')
        self.assertIn('multipart/form-data; boundary=sam-', captured['type'])
        self.assertIn(b'name="file"; filename="sam-diagnostics.log"', captured['body'])
        self.assertIn(b'Content-Type: text/plain', captured['body'])
        self.assertIn(b'MiSTer SAM diagnostics', captured['body'])
        self.assertIn(b'owner=12:34', captured['body'])
        self.assertLessEqual(len(captured['body']), diagnostics.MAX_UPLOAD_BYTES + 2048)

    def test_response_read_is_bounded_and_readable(self):
        response = Reply(b'https://logs.example.test/log\n')
        with patch('urllib.request.urlopen', return_value=response) as opened:
            self.assertEqual(diagnostics.upload_log(self.runtime, 'https://logs.example.test/upload'), 'https://logs.example.test/log')
        self.assertEqual(response.read_sizes, [8193])
        self.assertEqual(opened.call_args.kwargs['timeout'], 30)
        context = opened.call_args.kwargs['context']
        self.assertEqual(context.verify_mode, ssl.CERT_REQUIRED)
        self.assertTrue(context.check_hostname)

    def test_oversized_response_is_rejected(self):
        with patch('urllib.request.urlopen', return_value=Reply(b'x' * 8193)):
            with self.assertRaisesRegex(RuntimeError, 'oversized'):
                diagnostics.upload_log(self.runtime, 'https://logs.example.test/upload')

    def test_invalid_and_insecure_returned_links_are_rejected(self):
        for value in (b'not-a-url', b'https://logs.example.test/a b', b'http://logs.example.test/log', b'ftp://logs.example.test/log', b'https://user:password@logs.example.test/log'):
            with self.subTest(value=value), patch('urllib.request.urlopen', return_value=Reply(value)):
                with self.assertRaises(RuntimeError):
                    diagnostics.upload_log(self.runtime, 'https://logs.example.test/upload')

    def test_https_redirect_to_public_http_is_rejected(self):
        with patch('urllib.request.urlopen', return_value=Reply(b'https://logs.example.test/log', 'http://logs.example.test/insecure')):
            with self.assertRaisesRegex(RuntimeError, 'secure transport'):
                diagnostics.upload_log(self.runtime, 'https://logs.example.test/upload')

    def test_http_rejection_preserves_local_history(self):
        before = (self.directory / 'events.jsonl').read_bytes()
        error = HTTPError('https://logs.example.test/upload', 403, 'Forbidden', {}, io.BytesIO(b'Forbidden'))
        self.addCleanup(error.close)
        with patch('urllib.request.urlopen', side_effect=error):
            with self.assertRaisesRegex(RuntimeError, 'HTTP 403.*retained'):
                diagnostics.upload_log(self.runtime, 'https://logs.example.test/upload')
        self.assertEqual((self.directory / 'events.jsonl').read_bytes(), before)

    def test_ssl_url_and_timeout_failures_are_readable(self):
        failures = ((ssl.SSLError('certificate verify failed'), 'certificate check failed'),
                    (URLError('connection refused'), 'Could not reach'),
                    (URLError(ssl.SSLError('certificate verify failed')), 'certificate check failed'),
                    (TimeoutError('timeout'), 'Could not reach'))
        for error, message in failures:
            with self.subTest(error=error), patch('urllib.request.urlopen', side_effect=error):
                with self.assertRaisesRegex(RuntimeError, message):
                    diagnostics.upload_log(self.runtime, 'https://logs.example.test/upload')

    def test_unsafe_endpoints_are_rejected_before_network(self):
        for endpoint in ('http://logs.example.test/upload', 'https://user:pass@logs.example.test/upload', 'https://logs.example.test/upload?token=secret', 'https://logs.example.test/upload#fragment', 'file:///tmp/log', 'https:///missing-host'):
            with self.subTest(endpoint=endpoint), patch('urllib.request.urlopen') as opened:
                with self.assertRaises(ValueError):
                    diagnostics.upload_log(self.runtime, endpoint)
                opened.assert_not_called()

    def test_default_cli_upload_uses_free_service_and_secret_expiry_fields(self):
        output = io.StringIO()
        with patch.dict('os.environ', {}, clear=True), patch.object(diagnostics, 'upload_log', return_value='https://0x0.st/example') as upload, contextlib.redirect_stdout(output):
            self.assertEqual(diagnostics.main(['--runtime', self.runtime, '--upload']), 0)
        upload.assert_called_once_with(self.runtime, 'https://0x0.st/')
        self.assertIn('Log URL: https://0x0.st/example', output.getvalue())
        response = Reply(b'https://0x0.st/example', 'https://0x0.st/')
        with patch('urllib.request.urlopen', return_value=response) as opened:
            diagnostics.upload_log(self.runtime, diagnostics.DEFAULT_UPLOAD_URL)
        body = opened.call_args.args[0].data
        self.assertIn(b'name="secret"', body)
        self.assertIn(b'name="expires"\r\n\r\n168\r\n', body)

    def test_preview_never_uploads_and_matches_filtered_payload(self):
        output = io.StringIO()
        with patch.object(diagnostics, 'build_upload_log', return_value=b'exact filtered fixture\n') as build, patch.object(diagnostics, 'upload_log') as upload, contextlib.redirect_stdout(output):
            self.assertEqual(diagnostics.main(['--runtime', self.runtime, '--preview', '--upload']), 0)
        build.assert_called_once_with(self.runtime)
        upload.assert_not_called()
        self.assertEqual(output.getvalue(), 'exact filtered fixture\n\n')

    def test_upload_omits_ini_and_redacts_storage_paths_and_credentials(self):
        # These are synthetic strings in temporary files, never real paths read.
        (Path(self.runtime) / 'MiSTer_SAM.ini').write_text('full_ini_private_fixture=never_uploaded\n', encoding='utf-8')
        (self.directory / 'debug.log').write_text('ROM /media/fat/games/private-fixture/game.chd\nINI /home/private-fixture/MiSTer_SAM.ini\npassword=credential_one token=credential_two api_key=credential_three\n', encoding='utf-8')
        payload = diagnostics.build_upload_log(self.runtime).decode('utf-8')
        for private in ('full_ini_private_fixture', '/media/fat/games/private-fixture/game.chd', '/home/private-fixture/MiSTer_SAM.ini', 'credential_one', 'credential_two', 'credential_three'):
            self.assertNotIn(private, payload)
        self.assertIn('[path omitted]', payload)
        self.assertIn('[redacted]', payload)

    def test_json_event_credential_values_are_redacted(self):
        self.record['fields'] = {'token': 'json_private_credential', 'api_key': 'json_api_credential'}
        (self.directory / 'events.jsonl').write_text(json.dumps(self.record) + '\n', encoding='utf-8')
        payload = diagnostics.build_upload_log(self.runtime).decode('utf-8')
        self.assertNotIn('json_private_credential', payload)
        self.assertNotIn('json_api_credential', payload)

    def test_authorization_bearer_value_is_redacted(self):
        (self.directory / 'debug.log').write_text('Authorization: Bearer bearer_private_credential\n', encoding='utf-8')
        payload = diagnostics.build_upload_log(self.runtime).decode('utf-8')
        self.assertNotIn('bearer_private_credential', payload)

    def test_upload_payload_is_capped_at_512_kib_and_valid_utf8(self):
        with patch.object(diagnostics, 'render_history', return_value='\u2603' * diagnostics.MAX_UPLOAD_BYTES):
            payload = diagnostics.build_upload_log(self.runtime)
        self.assertLessEqual(len(payload), 512 * 1024)
        self.assertGreater(len(payload), 500 * 1024)
        payload.decode('utf-8')

    def test_cli_failure_returns_nonzero_with_readable_error(self):
        output = io.StringIO()
        with patch.object(diagnostics, 'upload_log', side_effect=RuntimeError('HTTP 403; local history retained')), contextlib.redirect_stdout(output):
            result = diagnostics.main(['--runtime', self.runtime, '--upload'])
        self.assertEqual(result, 1)
        self.assertIn('Unable to upload log: HTTP 403', output.getvalue())
