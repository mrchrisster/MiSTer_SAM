# SPDX-License-Identifier: GPL-3.0-or-later
ttyenable=yes
source "$mrsampath/modules/tty-functions.sh"
sam_register display_startup tty_start
sam_register display_shutdown tty_exit

sam_tty_game_info() { # called with loader locals in scope
    local tty_gamename="$gamename"
    if [[ "$ttyname_cleanup" == yes ]]; then tty_gamename="$(printf '%s\n' "$tty_gamename" | sed 's/ *([^)]*) *$//')"; fi
    [[ -z "$streamtitle" ]] || tty_gamename+=" - BGM: $streamtitle"
    tty_currentinfo=(
        [core_pretty]="${CORE_PRETTY[$core]}" [name]="$tty_gamename" [core]="$tty_corename"
        [date]=$EPOCHSECONDS [counter]=$gametimer [name_scroll]="${tty_gamename:0:21}"
        [name_scroll_position]=0 [name_scroll_direction]=1 [update_pause]=$ttyupdate_pause
    )
    declare -p tty_currentinfo | sed 's/declare -A/declare -gA/' > "$tty_currentinfo_file"
    write_to_TTY_cmd_pipe display_info &
}
sam_register launch_observe sam_tty_game_info
