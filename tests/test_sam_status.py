import ast
import copy
import os
from pathlib import Path
import tempfile
import threading
import types
import unittest
from unittest.mock import patch
from urllib.parse import urlparse

import sys
from paths import PACKAGE, MONITOR_SERVER
sys.path.insert(0,str(PACKAGE/'.MiSTer_SAM/control'))
from sam_status import inactive, parse_sam_state, read_sam_status


class SamTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.file = self.root / 'SAM_state'
        self.proc = self.root / 'proc'
        (self.proc / '42').mkdir(parents=True)
        self.statfile = self.proc / '42/stat'
        self.statfile.write_text('42 (SAM worker (a) ) tricky) ' + ' '.join(['S'] + ['0']*18 + ['1234']))
        self.payload = ('active=yes\nmode=normal\ngame=Pokémon = $(command) \\ USA\n'
                        'rom_path=/games/a=b.zip/Game.nes\ncore=nes\nsetname=\n'
                        'start_time=1790921350\ntimer=181\ngame_kept=no\n'
                        'owner_pid=42\nowner_start=1234\n')
        self.file.write_text(self.payload, encoding='utf-8')

    def read(self): return read_sam_status(self.file, self.proc)

    def test_active_and_owner_with_spaces_parentheses(self):
        self.assertEqual(self.read(), dict(active=True, mode='attract', gametimer=181, next_game_at=1790921531))

    def test_literal_unknown_keys_ignored(self):
        self.file.write_text(self.payload + 'unknown=a=b\\c\nunknown=anything\n', encoding='utf-8')
        self.assertTrue(self.read()['active'])
        self.assertEqual(parse_sam_state(b'active=yes\nunknown=$(command)=\\x\n')['active'], 'yes')

    def test_modes(self):
        for mode, expected in [('normal', 'attract'), ('roulette', 'roulette'), ('m82', 'm82'), ('samvideo', 'video')]:
            self.file.write_text(self.payload.replace('mode=normal', 'mode='+mode))
            self.assertEqual(self.read()['mode'], expected)

    def test_zero_timer_active(self):
        self.file.write_text(self.payload.replace('timer=181', 'timer=0'))
        self.assertEqual(self.read(), dict(active=True, mode='attract', gametimer=0, next_game_at=None))

    def test_extension_preserves_start(self):
        self.file.write_text(self.payload.replace('timer=181', 'timer=300'))
        self.assertEqual(self.read()['next_game_at'], 1790921650)

    def test_expired_still_active(self):
        self.file.write_text(self.payload.replace('start_time=1790921350', 'start_time=1'))
        self.assertTrue(self.read()['active'])

    def test_inactive_kept_game(self):
        self.file.write_text(self.payload.replace('active=yes', 'active=no').replace('game_kept=no', 'game_kept=yes'))
        self.assertEqual(self.read(), inactive())

    def test_dead_zombie_reused_owner(self):
        original = self.statfile.read_text()
        for bad in [original.replace(') S ', ') Z '), original.replace('1234', '1235'), 'garbage']:
            self.statfile.write_text(bad)
            self.assertEqual(self.read(), inactive())
        self.statfile.unlink()
        self.assertEqual(self.read(), inactive())

    def test_missing_malformed_unreadable(self):
        for payload in [b'\xff', b'x'*4097, b'not_a_pair',
                        self.payload.replace('timer=181', 'timer=-1').encode(),
                        self.payload.replace('owner_pid=42', 'owner_pid=0').encode(),
                        self.payload.replace('mode=normal', 'mode=unknown').encode(),
                        (self.payload+'active=no\n').encode()]:
            self.file.write_bytes(payload)
            self.assertEqual(self.read(), inactive())
        with patch('sam_status.os.open', side_effect=PermissionError('unreadable')):
            self.assertEqual(self.read(), inactive())
        self.file.unlink()
        self.assertEqual(self.read(), inactive())

    def test_fifo_does_not_block(self):
        self.file.unlink()
        os.mkfifo(self.file)
        self.assertEqual(self.read(), inactive())

    def test_actual_owner(self):
        if not Path('/proc/self/stat').exists(): self.skipTest('Requires Linux procfs')
        fields = Path('/proc/self/stat').read_text().rsplit(')', 1)[1].split()
        payload = self.payload.replace('owner_pid=42', 'owner_pid='+str(os.getpid())).replace('owner_start=1234', 'owner_start='+fields[19])
        self.file.write_text(payload)
        self.assertTrue(read_sam_status(self.file)['active'])

    def test_real_snapshot_methods_fresh_and_preserve_identity(self):
        # Execute the actual installed handler methods, without importing server
        # startup code or changing live game/SAM files.
        tree = ast.parse(MONITOR_SERVER.read_text())
        cls = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == 'MiSTerStatusHandler')
        methods = [n for n in cls.body if isinstance(n, ast.FunctionDef) and n.name in {'do_GET','get_state_snapshot'}]
        shell = ast.ClassDef(name='Handler', bases=[], keywords=[], body=methods, decorator_list=[])
        keys = ['core','core_raw','system_name','game_system','game','game_path','last_event']
        state = {k: 'original-'+k for k in keys}
        state.update(seq=17, is_arcade=False, rom_details_stale=True, rom_details=None, updated_at=12)
        before = copy.deepcopy(state)
        clock = [1000]
        ns = dict(_state=state, _state_lock=threading.Lock(), SERVER_VERSION='2.11.1',
                  read_sam_status=self.read, time=types.SimpleNamespace(time=lambda:clock[0]),
                  urlparse=urlparse, _requests_count=0, sam_control=types.SimpleNamespace(advertised=lambda:dict(controls=[], paused=False)))
        exec(compile(ast.fix_missing_locations(ast.Module(body=[shell], type_ignores=[])), 'handler', 'exec'), ns)
        handler = ns['Handler']()
        result = []
        handler.send_json_response = result.append
        handler.path = '/status/snapshot'
        handler.do_GET()
        self.assertEqual(result[-1]['sam']['next_game_at'], 1790921531)
        for key, value in before.items(): self.assertEqual(result[-1][key], value)
        handler.path = '/status/snapshot?seq=17'
        handler.do_GET()
        self.assertTrue(result[-1]['unchanged'])
        self.file.write_text(self.payload.replace('timer=181','timer=300'))
        clock[0] = 1002
        handler.do_GET()
        self.assertEqual(result[-1]['timestamp'], 1002)
        self.assertEqual(result[-1]['sam']['next_game_at'], 1790921650)
        self.file.write_text(self.payload.replace('active=yes','active=no'))
        handler.do_GET()
        self.assertEqual(result[-1]['sam'], dict(inactive(), controls=[], paused=False))
        self.assertEqual(state, before)


class ArcadeDetection(unittest.TestCase):
    def test_sam_arcade_classification(self):
        source=MONITOR_SERVER
        tree=ast.parse(source.read_text())
        branch=next(node for node in ast.walk(tree) if isinstance(node,ast.If) and isinstance(node.test,ast.Call) and isinstance(node.test.func,ast.Name) and node.test.func.id=='_sam_is_current')
        fn=ast.FunctionDef(name='evaluate_sam',args=ast.arguments(posonlyargs=[],args=[],kwonlyargs=[],kw_defaults=[],defaults=[]),body=branch.body,decorator_list=[])
        module=ast.fix_missing_locations(ast.Module(body=[fn],type_ignores=[]))
        for raw,path,expected in [('arcade','/games/A.mra',True),('stv','/games/B.mra',True),('other','/games/C.mra',True),('snes','/games/D.sfc',False)]:
            calls=[]
            ns=dict(_sam_get_current=lambda:(True,raw,'Friendly','Title',path),_read_file=lambda _:raw,_commit_state=lambda *a,**k:calls.append((a,k)))
            exec(compile(module,str(source),'exec'),ns);ns['evaluate_sam']()
            self.assertEqual(calls[0][1]['is_arcade'],expected)
            self.assertEqual(calls[0][0][0],'Arcade' if expected else 'Friendly')

if __name__ == '__main__': unittest.main(verbosity=2)
