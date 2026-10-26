# SPDX-License-Identifier: GPL-3.0-or-later
# Foreground engines and explicit maintenance actions own this initialization.
# Loading this file defines functions; it does not initialize or dispatch SAM.
sam_load_runtime() {
    [[ "${sam_runtime_loaded:-0}" != 1 ]] || return 0
    source "$sam_root/lib/modules.sh" || return 1
    source "$sam_root/lib/config.sh" || return 1
    source "$sam_root/lib/common.sh" || return 1
    source "$sam_root/lib/diagnostics.sh" || return 1
    source "$sam_root/lib/cores.sh" || return 1
    source "$sam_root/lib/core-registry.sh" || return 1
    source "$sam_root/lib/state.sh" || return 1
    source "$sam_root/lib/session.sh" || return 1
    source "$sam_root/lib/config-reload.sh" || return 1
    source "$sam_root/lib/audio.sh" || return 1
    source "$sam_root/lib/catalog.sh" || return 1
    source "$sam_root/lib/filter.sh" || return 1
    source "$sam_root/lib/launch.sh" || return 1
    source "$sam_root/lib/lifecycle.sh" || return 1
    source "$sam_root/lib/catalog-runtime.sh" || return 1
    source "$sam_root/lib/bootstrap.sh" || return 1
    source "$sam_root/lib/policy.sh" || return 1
    source "$sam_root/lib/engine.sh" || return 1
    source "$sam_root/lib/dispatch.sh" || return 1
    sam_register candidate_prepare sam_launch_prepare_candidate || return 1
    sam_exit_trace libs_loaded
    if [[ "${sam_ui_initialized:-0}" == 1 ]]; then
        sam_config_paths
    else
        init_vars
        sam_exit_trace vars_initialized
        read_samini || return 1
        sam_exit_trace config_loaded
    fi
    init_data
    sam_exit_trace data_initialized
    # A hosted adapter validates configuration while an old game may still be
    # running. Create scratch/catalogue directories only after activation.
    if [[ "${sam_engine_hosted:-0}" != 1 ]]; then
        init_paths
        sam_exit_trace paths_initialized
    fi
    if [[ "${sam_engine_adapter_verified:-0}" == 1 ]]; then
        source "$sam_root/lib/engine-modes.sh" || return 1
        sam_bind engine_take sam_engine_normal_take || return 1
        sam_bind engine_launch sam_engine_normal_launch || return 1
        sam_bind engine_timer_begin sam_engine_mode_timer_begin || return 1
        sam_bind engine_timer_tick sam_engine_mode_timer_tick || return 1
        sam_bind engine_key sam_engine_mode_timer_key || return 1
    fi
    sam_load_modules || return 1
    sam_exit_trace modules_loaded
    sam_runtime_loaded=1
}

sam_runtime_dispatch() {
    sam_exit_trace backend_entry
    # MCP can retry the Menu acknowledgement frequently. This command uses only
    # ownership and audio state; it never invokes optional module hooks or gameplay.
    if [[ "$sam_gateway_backend" == 1 && "${1,,}" == menu_audio_restore ]]; then
        source "$sam_root/lib/config.sh" || return 1
        source "$sam_root/lib/state.sh" || return 1
        source "$sam_root/lib/session.sh" || return 1
        source "$sam_root/lib/audio.sh" || return 1
        source "$sam_root/lib/lifecycle.sh" || return 1
        sam_exit_trace libs_loaded
        init_vars
        sam_exit_trace vars_initialized
        read_samini || exit 1
        sam_exit_trace config_loaded
        mkdir -p "$mrsamtmp" || exit 1
        sam_exit_trace paths_initialized
        shift
        sam_exit_trace dispatch
        sam_menu_audio_restore "$@"
        exit $?
    fi
    sam_load_runtime || return $?
    sam_exit_trace dispatch
    [[ "${1:-}" == --source-only ]] || parse_cmd "$@"
}
