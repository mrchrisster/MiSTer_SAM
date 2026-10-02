# SPDX-License-Identifier: GPL-3.0-or-later
samvideo=yes
sam_mode=samvideo
source "$mrsampath/modules/video-functions.sh"
source "$mrsampath/modules/compat-selection.sh"
source "$mrsampath/modules/compat-catalog.sh"
source "$mrsampath/modules/compat-loop.sh"
sam_bind session_loop loop_core
declare -A SAMVC=()
SAMVTOTAL=0
SAMVIDEO_INIT_SENTINEL="$mrsamtmp/samvideo_init"
sam_video_setup() {
    ini_contents=$(<"$ini_file")
    source "$mrsampath/lib/downloads.sh"
    echo -e '\033[2J' > /dev/tty1
    echo 0 > /sys/class/graphics/fbcon/cursor_blink
    echo -e '\033[?17;0;0c' > /dev/tty1
    misterini_apply_temp
    get_dlmanager
    [[ -x "$mrsampath/mplayer" ]] || get_samvideo || return 1
    if [[ "$samvideo_tvc_cdi" == yes && ! -f "$configpath/cdi_sam.cfg" ]]; then
        echo 'd008 0100 0000 0000 0000 0000 0000 0000' | xxd -r -p > "$configpath/cdi_sam.cfg"
    fi
}
sam_register session_setup sam_video_setup

sam_video_cleanup() {
    local pid
    for pid in $(jobs -pr); do sam_kill_tree "$pid"; done
    echo 1 > /sys/class/graphics/fbcon/cursor_blink
    rm -f "$mrsamtmp/sv_corecount"
    misterini_restore
}
sam_register session_stop sam_video_cleanup

sam_video_assets() {
    local result=0
    check_and_update "$raw_base/.MiSTer_SAM/mplayer.zip" /tmp/sam-mplayer.zip "$mrsampath/mplayer.zip" mplayer || result=$?
    ((result == 0 || result == 2)) || return 1
    if ((result == 2)) || [[ ! -x "$mrsampath/mplayer" ]]; then
        unzip -ojq "$mrsampath/mplayer.zip" -d "$mrsampath" || return 1
        chmod +x "$mrsampath/mplayer"
    fi
}
get_samvideo() { sam_video_assets; }
sam_register update_assets sam_video_assets
