"""Entrypoint timing diagnostics use fixture libraries and no hardware commands."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from paths import ROOT


class ExitTrace(unittest.TestCase):
    def run_entry(self, trace, restore=False):
        with tempfile.TemporaryDirectory(prefix='sam-exit-trace-') as directory:
            root = Path(directory)
            library = root / 'lib'
            library.mkdir()
            (library / 'runtime.sh').write_text((ROOT / '.MiSTer_SAM/lib/runtime.sh').read_text())
            for name in ('modules', 'config', 'common', 'diagnostics', 'cores', 'state', 'session', 'config-reload',
                         'audio', 'catalog', 'filter', 'launch', 'lifecycle',
                         'catalog-runtime', 'policy', 'engine', 'dispatch'):
                (library / (name + '.sh')).write_text('')
            (library / 'config.sh').write_text(
                'init_vars(){ :; }; read_samini(){ :; }; init_data(){ :; }\n')
            (library / 'common.sh').write_text('init_paths(){ :; }\n')
            (library / 'modules.sh').write_text('sam_load_modules(){ :; }\n')
            if restore:
                for name in ('modules', 'cores', 'common', 'catalog', 'engine'):
                    (library / (name + '.sh')).write_text('exit 91\n')
                (library / 'config.sh').write_text(
                    'init_vars(){ mrsamtmp="$SAM_ROOT/tmp"; }; '
                    'read_samini(){ :; }; init_data(){ exit 92; }; '
                    'mkdir(){ [[ "$*" == "-p $mrsamtmp" ]]; }\n')
                (library / 'lifecycle.sh').write_text(
                    'sam_menu_audio_restore(){ [[ "$*" == "123 45" ]]; }\n')
            env = dict(os.environ, SAM_ROOT=root.as_posix())
            env.pop('SAM_EXIT_TRACE', None)
            if trace:
                env['SAM_EXIT_TRACE'] = (root / trace).as_posix()
            arguments = ['--gateway-backend', 'menu_audio_restore', '123', '45'] if restore else ['--source-only']
            result = subprocess.run([os.environ.get('SAM_TEST_BASH', 'bash'),
                                     (ROOT / 'MiSTer_SAM_on.sh').as_posix(),
                                     *arguments], env=env, text=True,
                                    capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, '')
            self.assertEqual(result.stderr, '')
            output = root / (trace or 'trace')
            return output.read_text() if output.is_file() else ''

    def test_enabled_records_initialization_in_order(self):
        lines = self.run_entry('trace').splitlines()
        self.assertEqual([line.split()[1] for line in lines], [
            'entry', 'backend_entry', 'libs_loaded', 'vars_initialized',
            'config_loaded', 'data_initialized', 'paths_initialized',
            'modules_loaded', 'dispatch'])
        self.assertTrue(all(float(line.split()[0]) > 0 for line in lines))
        self.assertTrue(all(line.split()[2].startswith('pid=') for line in lines))

    def test_disabled_produces_no_trace(self):
        self.assertEqual(self.run_entry(None), '')

    def test_bad_diagnostic_destination_does_not_block_startup(self):
        self.assertEqual(self.run_entry('missing/trace'), '')

    def test_menu_acknowledgement_skips_gameplay_and_module_initialization(self):
        lines = self.run_entry('trace', restore=True).splitlines()
        self.assertEqual([line.split()[1] for line in lines], [
            'entry', 'backend_entry', 'libs_loaded', 'vars_initialized',
            'config_loaded', 'paths_initialized', 'dispatch'])


if __name__ == '__main__':
    unittest.main()
