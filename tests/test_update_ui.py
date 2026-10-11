"""Updater output, checked downloads and failure boundaries; no network/hardware."""
import contextlib
import io
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import Mock, patch
from test_install import installer


class Terminal(io.StringIO):
    def isatty(self):
        return True


class UpdatePresentation(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sam-update-ui-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def run_cli(self, failure=None, result=None):
        out, err = io.StringIO(), io.StringIO()
        argv = ['installer.py', '--download', '--branch', 'test', '--mister-root', str(self.root)]
        with patch.object(sys, 'argv', argv), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            if failure is not None:
                with patch.object(installer, 'download_source', side_effect=failure), patch.object(installer, 'install') as install:
                    code = installer.cli()
                    install.assert_not_called()
            else:
                with patch.object(installer, 'run_download', return_value=result), patch.object(installer, 'install') as install:
                    code = installer.cli()
                    install.assert_not_called()
        return code, out.getvalue(), err.getvalue()

    def test_certificate_error_is_actionable_without_traceback_or_changes(self):
        result = subprocess.CompletedProcess([], 60, '000',
            'curl: (60) SSL certificate problem: certificate is not yet valid\nMore details here...')
        code, out, err = self.run_cli(result=result)
        self.assertEqual(code, 1)
        self.assertIn('[1/4]', out)
        self.assertIn('certificate is not yet valid', err)
        self.assertIn('Device time:', err)
        self.assertIn('date -u', err)
        self.assertIn('Installed SAM files were not changed', err)
        self.assertNotIn('Traceback', out + err)
        self.assertNotIn('More details here', out + err)
        self.assertFalse((self.root/'Scripts').exists())

    def test_dns_timeout_http_and_ca_errors_have_short_guidance(self):
        for code, http, expected in ((6, '000', 'DNS'), (28, '000', 'timed out'),
                                     (22, '404', 'HTTP 404'), (77, '000', 'CA')):
            with self.subTest(code=code):
                error = installer.download_failure(subprocess.CompletedProcess([], code, http, ''), 'test')
                self.assertIn(expected, str(error))

    def test_invalid_release_and_validation_traceback_are_not_dumped(self):
        error = subprocess.CalledProcessError(1, ['python3'], stderr='Traceback\nValueError: bad catalogue\n')
        code, out, err = self.run_cli(failure=error)
        self.assertEqual(code, 1)
        self.assertIn('ValueError: bad catalogue', err)
        self.assertNotIn('Traceback', out + err)
        self.assertIn('Installed SAM files were not changed', err)

    def test_interrupted_download_returns_130_without_installing(self):
        code, _, err = self.run_cli(failure=KeyboardInterrupt())
        self.assertEqual(code, 130)
        self.assertIn('Cancelled', err)
        self.assertIn('Installed SAM files were not changed', err)

    def test_partial_install_and_handoff_never_claim_unchanged(self):
        for flag in ('writes_started', 'handoff_started'):
            out, err = io.StringIO(), io.StringIO()
            ui = installer.UpdateUI(out, err)
            setattr(ui, flag, True)
            ui.error(OSError('disk full'))
            self.assertIn('may be incomplete', err.getvalue())
            self.assertNotIn('files were not changed', err.getvalue())

    def test_redirected_output_has_no_animation_or_colour(self):
        out = io.StringIO(); ui = installer.UpdateUI(out, io.StringIO())
        ui.begin('Update', 'test'); ui.stage(1, 'Downloading...')
        ui.downloading(self.root/'missing', 1); ui.clear()
        self.assertNotIn('\033', out.getvalue())
        self.assertNotIn('\r', out.getvalue())

    def test_no_colour_and_dumb_terminal_are_respected(self):
        with patch.dict(os.environ, {'NO_COLOR': '', 'TERM': 'linux'}):
            ui = installer.UpdateUI(Terminal(), io.StringIO())
            self.assertTrue(ui.live)
            self.assertFalse(ui.colour)
        with patch.dict(os.environ, {'TERM': 'dumb'}):
            self.assertFalse(installer.UpdateUI(Terminal(), io.StringIO()).live)

    def test_download_uses_verified_https_and_validates_before_install(self):
        content = self.root/'fixture.tar.gz'
        with tarfile.open(content, 'w:gz') as bundle:
            item = tarfile.TarInfo('release/MiSTer_SAM_on.sh'); data = b'#!/bin/bash\n'
            item.size = len(data); bundle.addfile(item, io.BytesIO(data))
        work = self.root/'work'; work.mkdir()
        commands = []
        def receive(command, archive, ui):
            commands.append(command); archive.write_bytes(content.read_bytes())
            return subprocess.CompletedProcess(command, 0, '200', '')
        out = io.StringIO(); ui = installer.UpdateUI(out, io.StringIO())
        with patch.object(installer, 'run_download', side_effect=receive), \
             patch.object(installer, 'checked_source', side_effect=lambda source: source) as validate:
            result = installer.download_source(work, 'test', ui)
        validate.assert_called_once_with(work/'release')
        self.assertEqual(result, work/'release')
        command = commands[0]
        self.assertIn('--silent', command); self.assertIn('--show-error', command)
        self.assertEqual(command[command.index('--proto')+1], '=https')
        self.assertEqual(command[command.index('--proto-redir')+1], '=https')
        self.assertNotIn('--insecure', command); self.assertNotIn('-k', command)
        self.assertIn('downloaded in', out.getvalue()); self.assertIn('[2/4]', out.getvalue())

    def test_handoff_failure_is_once_and_legacy_traceback_is_hidden(self):
        source = self.root/'release'; source.mkdir()
        argv = ['installer.py', '--download', '--mister-root', str(self.root)]
        for message, expected in (('SAM update failed: no space\n', 'no space'),
                                  ('Traceback (most recent call last)\nold traceback', 'downloaded installer failed')):
            out, err = io.StringIO(), io.StringIO()
            with patch.object(sys, 'argv', argv), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err), \
                 patch.object(installer, 'download_source', return_value=source), \
                 patch.object(installer.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, stderr=message)):
                code = installer.cli()
            self.assertEqual(code, 1)
            self.assertIn(expected, err.getvalue())
            self.assertNotIn('Traceback', out.getvalue() + err.getvalue())

    def test_download_polling_and_cancel_reap_only_the_owned_curl(self):
        archive = self.root/'download'
        ui = installer.UpdateUI(io.StringIO(), io.StringIO())
        result = installer.run_download([sys.executable, '-c', 'print("200",end="")'], archive, ui)
        self.assertEqual(result.returncode, 0); self.assertEqual(result.stdout, '200')
        process = Mock(); process.communicate.side_effect = [KeyboardInterrupt(), ('', '')]
        process.poll.return_value = None
        with patch.object(installer.subprocess, 'Popen', return_value=process):
            with self.assertRaises(KeyboardInterrupt):
                installer.run_download(['curl'], archive, ui)
        process.kill.assert_called_once()
        self.assertEqual(process.communicate.call_count, 2)

    def test_total_download_deadline_is_bounded_across_retries(self):
        process = Mock(); process.communicate.side_effect = [subprocess.TimeoutExpired(['curl'], 190), ('000', '')]
        process.poll.return_value = 0
        with patch.object(installer.subprocess, 'Popen', return_value=process), \
             patch.object(installer.time, 'monotonic', side_effect=[0, 191]):
            result = installer.run_download(['curl'], self.root/'download', installer.UpdateUI(io.StringIO(), io.StringIO()))
        self.assertEqual(result.returncode, 28)
        process.kill.assert_called_once()


if __name__ == '__main__':
    unittest.main()
