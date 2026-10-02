# SPDX-License-Identifier: GPL-3.0-or-later
sam_status_enabled=yes
source "$mrsampath/control/state.sh"
source "$mrsampath/control/handler.sh"
for event in read start launch publish off exit; do
    sam_register "display_$event" "sam_display_$event" || return 1
done
sam_register countdown_tick sam_control_tick
sam_register controls_ready sam_control_publish

sam_monitor_timer_begin() {
    sam_control_generation=$sam_generation
    sam_control_publish 1
}
sam_register countdown_start sam_monitor_timer_begin
