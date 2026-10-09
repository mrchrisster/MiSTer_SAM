# SPDX-License-Identifier: GPL-3.0-or-later
m82=yes
sam_mode=m82
source "$mrsampath/modules/m82-functions.sh"
source "$mrsampath/modules/compat-selection.sh"
source "$mrsampath/modules/compat-catalog.sh"
source "$mrsampath/modules/compat-loop.sh"
sam_bind session_loop loop_core
sam_m82_requested_cores() {
    local -n sam_m82_requested="$1"
    sam_m82_requested=(nes)
}
sam_m82_core_allowed() {
    [[ "$1" == nes ]] && return 0
    sam_core_reason="M82 requires the NES core ($1 requested)"; return 1
}
sam_m82_configure() {
    [[ "$m82_muted" != yes ]] && mute=no || mute=global
    gametimer=21
}
sam_register core_requested sam_m82_requested_cores
sam_register core_allowed sam_m82_core_allowed
sam_register config_loaded sam_m82_configure
sam_register session_setup build_m82_list
sam_register session_stop sam_m82_cleanup_index
