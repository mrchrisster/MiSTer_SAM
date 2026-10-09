# SPDX-License-Identifier: GPL-3.0-or-later
bgm=yes
mute=core
source "$mrsampath/modules/bgm-functions.sh"
sam_register session_start bgm_start
sam_register audio_stop bgm_stop
sam_bgm_game_info() {
    streamtitle=$(awk -F"'" '/StreamTitle=/{title=$2} END{print title}' /tmp/bgm.log 2>/dev/null)
}
sam_register launch_info sam_bgm_game_info
sam_bgm_core_allowed() {
    case "$1" in
        n64|psx|saturn) sam_core_reason="BGM requires per-core volume control ($1)"; return 1 ;;
        *) return 0 ;;
    esac
}
sam_register core_allowed sam_bgm_core_allowed
