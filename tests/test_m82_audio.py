"""M82 restores SAM-owned audio and acknowledges play only after activation."""
import unittest
import test_shell as fixture


class M82Audio(unittest.TestCase):
    setUp = fixture.Shell.setUp
    shell = fixture.Shell.shell
    assertShell = fixture.Shell.assertShell
    def test_play_restores_audio_then_publishes_owner_bound_ack(self):
        self.assertShell('''sam_load_module m82
sam_session="$mrsamtmp/m82-test"; mkdir -p "$sam_session"
sam_launch_serial=7; rompath=/games/A.nes; m82_bios_path=/games/Bios.nes
gametimer=1; m82_game_timer=3; samvideo=no
sam_publish_phase(){ :; }; sam_config_timer_update(){ :; }
sam_emit(){ :; }
sam_restore_audio(){ printf restored >> "$sam_session/restored"; }
reads=0
read(){ reads=$((reads+1)); if ((reads==1)); then key=y; return 0; fi; SECONDS=$((SECONDS+4)); return 1; }
run_countdown_timer || exit $?
[[ $(<"$sam_session/restored") == restored ]]
grep -q '^launch=7$' "$sam_session/m82-phase"
grep -q '^phase=play$' "$sam_session/m82-phase"
''')

    def test_audio_failure_does_not_acknowledge_play_or_prevent_retry(self):
        self.assertShell('''sam_load_module m82
sam_session="$mrsamtmp/m82-test"; mkdir -p "$sam_session"
sam_launch_serial=8; rompath=/games/A.nes; m82_bios_path=/games/Bios.nes
gametimer=1; m82_game_timer=3; samvideo=no
sam_publish_phase(){ :; }; sam_config_timer_update(){ :; }; sam_emit(){ :; }
restores=0; reads=0
sam_restore_audio(){ restores=$((restores+1)); ((restores>1)); }
read(){ reads=$((reads+1)); if ((reads<=2)); then key=y; return 0; fi; SECONDS=$((SECONDS+4)); return 1; }
run_countdown_timer || exit $?
[[ "$restores" == 2 ]]
grep -q '^phase=play$' "$sam_session/m82-phase"
''')
