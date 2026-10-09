"""Input and lifecycle regressions; no MiSTer hardware commands in fixtures."""
import asyncio, importlib.util, os, struct, subprocess, tempfile, threading, time, unittest
from pathlib import Path
from unittest.mock import patch
from paths import PACKAGE
SOURCE=PACKAGE/'.MiSTer_SAM/MiSTer_SAM_MCP.py'
spec=importlib.util.spec_from_file_location('sam_mcp',SOURCE);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def event(kind,number,value):return dict(type=kind,number=number,value=value,timestamp=0)
OWNER=dict(pid='321',start='77',phase='playing',launch='1')
class Input(unittest.TestCase):
    def test_original_js_button_and_axis_mapping(self):
        prev=[event(1,5,0)];current=[event(1,5,1)]
        self.assertEqual(m.get_js_activity(prev,current,{'button':{'start':5}}),'start')
        self.assertEqual(m.get_js_activity(prev,current,{'button':{'next':5}}),'next')
        self.assertEqual(m.get_js_activity(prev,current,{'button':{'exit':5}}),'exit')
        self.assertEqual(m.get_js_activity(prev,current,{}),'default')
        self.assertEqual(m.get_js_activity([event(2,0,0)],[event(2,0,32767)],{'axis':{'next':{'code':0,'value':32767}}}),'next')
    def test_original_js_batch_and_release_handling(self):
        self.assertIsNone(m.get_js_activity([], [event(1,5,1)],{}))
        self.assertIsNone(m.get_js_activity([event(1,5,1)],[event(1,5,0)],{}))

    def test_session_mode_updates_and_rejects_stale_state(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'state'
            with patch.object(m,'SAM_STATE_FILE',str(path)):
                path.write_text('active=yes\nmode=m82\nowner_pid=321\nowner_start=77\n')
                self.assertTrue(m.session_is_m82(OWNER,False))
                path.write_text('active=yes\nmode=normal\nowner_pid=321\nowner_start=77\n')
                self.assertFalse(m.session_is_m82(OWNER,True))
                path.write_text('active=yes\nmode=m82\nowner_pid=321\nowner_start=78\n')
                self.assertFalse(m.session_is_m82(OWNER,False))

    def test_menu_loading_slow_start_and_new_selection(self):
        state=m.SamState();loading=dict(OWNER,phase='loading')
        for sec in (0,15,60):self.assertFalse(m.menu_requires_stop(state,loading,True,sec))
        self.assertFalse(m.menu_requires_stop(state,OWNER,True,65)) # not yet seen a game
        self.assertFalse(m.menu_requires_stop(state,OWNER,False,66))
        self.assertFalse(m.menu_requires_stop(state,OWNER,True,67))
        self.assertFalse(m.menu_requires_stop(state,OWNER,False,68)) # brief Menu
        self.assertFalse(m.menu_requires_stop(state,OWNER,True,70))
        self.assertTrue(m.menu_requires_stop(state,OWNER,True,72))
        self.assertFalse(m.menu_requires_stop(state,dict(OWNER,launch='2'),True,74))
    def test_unknown_core_and_video_menu_do_not_arm_shutdown(self):
        state=m.SamState()
        self.assertFalse(m.menu_requires_stop(state,OWNER,None,0))
        self.assertFalse(m.menu_requires_stop(state,OWNER,True,10))
        self.assertFalse(m.menu_requires_stop(state,OWNER,True,13))
        self.assertFalse(m.menu_requires_stop(state,OWNER,False,14))
        for sec in (15,18,60):
            self.assertFalse(m.menu_requires_stop(state,dict(OWNER,phase='video'),True,sec))

    def test_owner_dead_zombie_reused_and_process_name_spaces(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'321').mkdir();owner=root/'owner';owner.write_text('pid=321\nstart=77\nphase=playing\n')
            stat=root/'321/stat'
            with patch.object(m,'SAM_OWNER_FILE',str(owner)),patch.object(m,'PROC_ROOT',tmp):
                self.assertIsNone(m.read_sam_owner())
                fields=['S']+['0']*18+['77']+['0']*10
                stat.write_text('321 (SAM worker (with) spaces) '+' '.join(fields));self.assertTrue(m.is_sam_running())
                fields[0]='Z';stat.write_text('321 (SAM) '+' '.join(fields));self.assertFalse(m.is_sam_running())
                fields[0]='S';fields[19]='78';stat.write_text('321 (SAM) '+' '.join(fields));self.assertFalse(m.is_sam_running())
                owner.write_text('pid=no\nstart=77\n');self.assertFalse(m.is_sam_running())
    def test_original_hid_keyboard_reader_routes_report_to_action(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'hidraw';path.write_bytes(b'\x01')
            calls=[];stop=threading.Event()
            class Loop:
                def call_soon_threadsafe(self,*args):calls.append(args);stop.set()
            with patch.object(m.time,'sleep'):
                m.keyboard_poller_thread(str(path),m.SamState(),Loop(),stop)
            self.assertEqual(len(calls),1);self.assertEqual(calls[0][1],'default')
    def test_original_discovery_retains_hidraw_for_existing_usb_remote(self):
        from io import StringIO
        text='N: Name="123 COM Smart Control"\nP: Phys=usb-1/input2\nS: Sysfs=/devices/platform/usb/input0\nH: Handlers=kbd event0\n\n'
        with patch('builtins.open',return_value=StringIO(text)),patch.object(m,'get_hidraw_for_keyboard',return_value='/dev/hidraw0'):
            devices=m.get_input_devices()
        self.assertEqual(devices['keyboards'][0]['hidraw_path'],'/dev/hidraw0')


class Lifecycle(unittest.IsolatedAsyncioTestCase):
    async def drain(self,state):
        for _ in range(100):
            await asyncio.sleep(.01)
            if not state.is_stopping():return
        self.fail('Action failed to finish')
    async def test_joy_disabled_does_not_disable_keyboard_or_zaparoo(self):
        state=m.SamState();state.listenjoy=False;loop=asyncio.get_running_loop()
        with patch.object(m,'read_sam_owner',return_value=OWNER),patch.object(m,'is_in_menu',return_value=False),patch.object(m,'stop_sam') as stop,patch.object(m,'unmute_sam'):
            m.handle_action('default',state,loop,'joystick');await asyncio.sleep(.01);stop.assert_not_called()
            m.handle_action('default',state,loop);await self.drain(state);self.assertEqual(stop.call_count,1)
            m.handle_action('zaparoo',state,loop);await self.drain(state);self.assertTrue(stop.call_args.kwargs['play_current'])
    async def test_next_in_menu_does_not_stop_loading_owner(self):
        state=m.SamState()
        with patch.object(m,'read_sam_owner',return_value=dict(OWNER,phase='loading')),patch.object(m,'is_in_menu',return_value=True),patch.object(m,'skip_game') as skip,patch.object(m,'stop_sam') as stop:
            m.handle_action('next',state,asyncio.get_running_loop(),'joystick');await self.drain(state)
            skip.assert_called_once();stop.assert_not_called()
    async def test_exit_storm_only_stops_once_and_pins_owner(self):
        state=m.SamState()
        async def delay(*args,**kwargs):await asyncio.sleep(.03)
        with patch.object(m,'read_sam_owner',return_value=OWNER),patch.object(m,'is_in_menu',return_value=False),patch.object(m,'stop_sam',side_effect=delay) as stop:
            for _ in range(40):m.handle_action('default',state,asyncio.get_running_loop())
            await self.drain(state);stop.assert_called_once();self.assertEqual(stop.call_args.kwargs['owner'],OWNER)
    async def test_replaced_owner_rejects_old_input(self):
        state=m.SamState()
        with patch.object(m,'read_sam_owner',side_effect=[OWNER,dict(OWNER,start='78')]),patch.object(m,'is_in_menu',return_value=False),patch.object(m,'stop_sam') as stop:
            m.handle_action('start',state,asyncio.get_running_loop(),'joystick');await self.drain(state);stop.assert_not_called()
    async def test_m82_bios_ignores_play_and_next_still_works(self):
        state=m.SamState();state.m82=True
        with patch.object(m,'read_sam_owner',return_value=OWNER),patch.object(m,'is_in_menu',return_value=False),patch.object(m,'read_m82_phase',return_value='bios'),patch.object(m,'play_m82_game') as play,patch.object(m,'skip_game') as skip:
            m.handle_action('default',state,asyncio.get_running_loop(),'joystick');await self.drain(state);play.assert_not_called()
            m.handle_action('next',state,asyncio.get_running_loop(),'joystick');await self.drain(state);skip.assert_called_once()
    async def test_m82_input_cancels_preparation_instead_of_sending_play(self):
        for phase in ('preparing','loading'):
            state=m.SamState();state.m82=True;owner=dict(OWNER,phase=phase)
            with patch.object(m,'read_sam_owner',return_value=owner),patch.object(m,'is_in_menu',return_value=False),patch.object(m,'session_is_m82',return_value=True),patch.object(m,'read_m82_phase',return_value='game'),patch.object(m,'play_m82_game') as play,patch.object(m,'stop_sam') as stop:
                m.handle_action('default',state,asyncio.get_running_loop(),'joystick');await self.drain(state)
                play.assert_not_called();stop.assert_called_once()
                self.assertEqual(stop.call_args.kwargs['owner'],owner)
    async def test_m82_next_during_preparation_keeps_the_skip_path(self):
        state=m.SamState();state.m82=True;owner=dict(OWNER,phase='preparing')
        with patch.object(m,'read_sam_owner',return_value=owner),patch.object(m,'is_in_menu',return_value=False),patch.object(m,'session_is_m82',return_value=True),patch.object(m,'skip_game') as skip,patch.object(m,'stop_sam') as stop:
            m.handle_action('next',state,asyncio.get_running_loop(),'joystick');await self.drain(state)
            skip.assert_called_once();stop.assert_not_called()
    async def test_failed_start_returns_without_timeout_or_stopping_another_owner(self):
        with tempfile.TemporaryDirectory() as tmp:
            script=Path(tmp)/'refused';script.write_text('#!/bin/sh\nexit 1\n');script.chmod(0o755)
            state=m.SamState()
            with patch.object(m,'SAM_ON_SCRIPT',str(script)),patch.object(m,'read_sam_owner',return_value=None),patch.object(m,'kill_sam_processes') as kill:
                await asyncio.wait_for(m.launch_and_confirm(state),timeout=2)
                self.assertIsNone(state.launcher);self.assertFalse(state.is_sam_starting())
                kill.assert_not_called()
    async def test_input_cancels_delayed_launcher_no_late_session(self):
        with tempfile.TemporaryDirectory() as tmp:
            marker=Path(tmp)/'late';script=Path(tmp)/'launcher'
            script.write_text('#!/bin/sh\nsleep .5\nprintf ghost > "'+str(marker)+'"\n');script.chmod(0o755)
            state=m.SamState();stops=[]
            def cleanup(*args):stops.append(state.launcher);marker.unlink(missing_ok=True)
            with patch.object(m,'SAM_ON_SCRIPT',str(script)),patch.object(m,'read_sam_owner',return_value=None),patch.object(m,'kill_sam_processes',side_effect=cleanup):
                task=asyncio.create_task(m.launch_and_confirm(state));await asyncio.sleep(.05)
                m.handle_action('default',state,asyncio.get_running_loop(),'joystick');await task
                await asyncio.sleep(.6);self.assertFalse(marker.exists());self.assertEqual(stops,[None]);self.assertFalse(state.is_sam_starting())
    async def test_input_arriving_during_owner_read_is_not_lost(self):
        state=m.SamState()
        process=subprocess.Popen(['sh','-c','exit 0'],start_new_session=True);process.wait()
        def start(s):s.launcher=process
        def owner():state.set_pending_action('default');return OWNER
        with patch.object(m,'start_sam',side_effect=start),patch.object(m,'read_sam_owner',side_effect=owner),patch.object(m,'kill_sam_processes') as stop:
            await m.launch_and_confirm(state);stop.assert_called_once_with(OWNER);self.assertFalse(state.is_sam_running())
    async def test_startup_next_coalesces(self):
        state=m.SamState();process=subprocess.Popen(['sh','-c','exit 0'],start_new_session=True);process.wait()
        def start(s):s.launcher=process;s.set_pending_action('next')
        with patch.object(m,'start_sam',side_effect=start),patch.object(m,'read_sam_owner',return_value=OWNER),patch.object(m,'skip_game') as skip,patch.object(m,'kill_sam_processes') as stop:
            await m.launch_and_confirm(state);skip.assert_called_once();stop.assert_not_called();self.assertTrue(state.is_sam_running())
    async def test_readers_cannot_exhaust_command_executor(self):
        from concurrent.futures import ThreadPoolExecutor
        loop=asyncio.get_running_loop()
        # On MiSTer the default is only six workers. A single available worker
        # here makes this regression deterministic regardless of host CPU count.
        executor=ThreadPoolExecutor(max_workers=1);loop.set_default_executor(executor)
        def read(stop):stop.wait(10)
        events=[threading.Event() for _ in range(8)]
        readers=[asyncio.create_task(m.run_input_reader(read,(),event)) for event in events]
        try:
            await asyncio.sleep(.05)
            result=await asyncio.wait_for(asyncio.to_thread(lambda:'responsive'),.5)
            self.assertEqual(result,'responsive')
        finally:
            for event in events:event.set()
            await asyncio.gather(*readers)

    async def test_concurrent_hotplug_rescans_use_current_loop(self):
        m.rescan_lock=None
        async def scan(*args):await asyncio.sleep(.03)
        with patch.object(m,'_rescan_devices_impl',side_effect=scan) as implementation:
            await asyncio.gather(m.rescan_devices(None,None,None,None),m.rescan_devices(None,None,None,None))
            self.assertEqual(implementation.call_count,2)
        m.rescan_lock=None

    async def test_cancelled_checker_reaps_launcher(self):
        state=m.SamState();state.launcher=subprocess.Popen(['sleep','10'],start_new_session=True)
        process=state.launcher
        await m.cancel_launcher(state);self.assertIsNotNone(process.poll());self.assertIsNone(state.launcher)

if __name__=='__main__':unittest.main(verbosity=2)
