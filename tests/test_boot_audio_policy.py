"""Boot starts the idle monitor without changing the user's audio settings."""
import unittest
import test_shell


class BootAudioPolicy(unittest.TestCase):
    setUp = test_shell.Shell.setUp
    shell = test_shell.Shell.shell
    assertShell = test_shell.Shell.assertShell

    def test_manual_toggle_does_not_write_after_failed_command(self):
        self.assertShell(r'''
mkdir -p "$configpath"
printf '\x05' > "$configpath/Volume.dat"
sam_audio_set_live(){ [[ "$1" == mute ]]; return 1; }
! toggle_mute
[[ $(od -An -tx1 "$configpath/Volume.dat" | tr -d ' \n') == 05 ]]
''')

    def test_manual_toggle_uses_shared_live_control_and_preserves_level(self):
        self.assertShell(r'''
mkdir -p "$configpath"
printf '\x05' > "$configpath/Volume.dat"
sam_audio_set_live(){ printf '%s\n' "$1" >> "$mrsamtmp/audio-actions"; }
toggle_mute
[[ $(od -An -tx1 "$configpath/Volume.dat" | tr -d ' \n') == 15 ]]
toggle_mute
[[ $(od -An -tx1 "$configpath/Volume.dat" | tr -d ' \n') == 05 ]]
[[ $(<"$mrsamtmp/audio-actions") == $'mute\nunmute' ]]
''')

    def test_legacy_unmute_option_cannot_change_boot_audio(self):
        self.assertShell(r'''
mkdir -p "$configpath"
printf '\x14' > "$configpath/Volume.dat"
unmute_on_boot=yes
env_check(){ :; }
boot_sleep(){ :; }
mcp_start(){ printf started > "$mrsamtmp/mcp-started"; }
unmute_with_retry(){ printf changed > "$mrsamtmp/audio-changed"; }
sam_restore_audio(){ printf changed > "$mrsamtmp/audio-changed"; }
timeout(){ printf changed > "$mrsamtmp/audio-changed"; }
parse_cmd bootstart
[[ $(<"$mrsamtmp/mcp-started") == started ]]
[[ ! -e "$mrsamtmp/audio-changed" ]]
[[ $(od -An -tx1 "$configpath/Volume.dat" | tr -d ' \n') == 14 ]]
''')
