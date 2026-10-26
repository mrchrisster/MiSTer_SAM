# SPDX-License-Identifier: GPL-3.0-or-later
# Extracted compatibility implementation; see reference and attribution.

sam_launch_prepare_candidate() { # worker only; literal XML travels with its ROM
    sam_candidate_mgl= sam_candidate_setname=
    [[ "${sam_engine_adapter_verified:-0}" == 1 ]] || return 0
    case "${sam_mode:-normal}" in normal|roulette) ;; *) return 0 ;; esac
    case "$1" in
        arcade|stv)
            local line pattern='<setname[^>]*>([^<]+)</setname>'
            while IFS= read -r line || [[ -n "$line" ]]; do
                if [[ "$line" =~ $pattern ]]; then sam_candidate_setname=${BASH_REMATCH[1]}; break; fi
            done < "$2"
            return 0 ;;
        amiga|amigacd32|ao486|x68k|mgls) return 0 ;;
    esac
    local xml rc=0
    xml=$(python3 "$mrsampath/sam_mgl.py" "$1" "$2" \
        --sd-root "$misterpath" --rbf-folder "${CORE_PATH_RBF[$1]}") || rc=$?
    ((rc == 0)) || return "$rc"
    [[ -n "$xml" && "$xml" != *$'\n'* && "$xml" != *$'\r'* ]] || return 2
    sam_candidate_mgl=$xml
}

sam_arcade_rbf_exists() { # tag and installed RBF search root
    local tag="$1" directory="$2" item had_case=0 had_fail=0 matches=()
    if [[ "$tag" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
        # Standard arcade RBFs live in cores/; flat installations work too.
        # Probe these verified paths before traversing thousands of MRA folders.
        shopt -q nocaseglob && had_case=1
        shopt -q failglob && had_fail=1
        shopt -s nocaseglob
        shopt -u failglob
        matches=("$directory/cores/$tag"*.rbf "$directory/$tag"*.rbf)
        ((had_case)) || shopt -u nocaseglob
        ((had_fail == 0)) || shopt -s failglob
        for item in "${matches[@]}"; do [[ ! -f "$item" ]] || return 0; done
    fi
    # Retain nonstandard layouts and the previous wildcard semantics.
    [[ -n "$(find "$directory" -iname "${tag}*.rbf" -print -quit 2>/dev/null)" ]]
}

function check_rom() { # background candidate validation, no nested indexing job
    local core="$1" path="${rompath:-}" ext
    [[ -n "$path" && "$path" != *$'\n'* && "$path" != *$'\r'* ]] || return 1
    if [[ "$core" == amiga ]]; then
        sam_adapter_paths amiga || return 1
        [[ -f "$amigapath/MegaAGS.hdf" || -f "$amigapath/AmigaVision.hdf" ]] || return 1
        [[ -f "$misterpath/_Computer/Amiga.mgl" || -f "$amigacore" ]] || return 1
        sam_amiga_stage
        return $?
    fi
    while [[ ! -f "$path" && "$path" == */* && "${path,,}" != *.zip ]]; do path="${path%/*}"; done
    [[ -f "$path" ]] || return 1
    ext="${rompath##*.}" ext="${ext,,}"
    if [[ -n "${CORE_EXT[$core]-}" ]]; then
        [[ ",${CORE_EXT[$core],,}," == *",$ext,"* ]] || return 1
    fi
    if [[ "$core" == ao486 || "$core" == x68k || "$core" == mgls ]]; then
        [[ "${rompath,,}" == *.mgl ]] || return 1
    fi
    if [[ "$core" == amigacd32 ]]; then
        [[ -f "$misterpath/_Console/Amiga CD32.mgl" && -f "$configpath/AmigaCD32.cfg" ]] || return 1
    fi
    if [[ "$core" == arcade || "$core" == stv ]]; then
        local tag checks="$misterpath/${CORE_PATH_RBF[$core]}"
        # Stop at the tag instead of reading an MRA's embedded ROM payload.
        tag=$(sed -n 's/.*<[rR][bB][fF]>\([^<]*\)<\/[rR][bB][fF]>.*/\1/p; /<[rR][bB][fF]>/q' "$rompath")
        tag="${tag//[[:space:]]/}"
        [[ -z "$tag" ]] || sam_arcade_rbf_exists "$tag" "$checks" || return 1
    fi
    romname="${rompath##*/}"
}

sam_xml_escape() {
    sam_xml="$1"; sam_xml="${sam_xml//&/\&amp;}"; sam_xml="${sam_xml//</\&lt;}"
    sam_xml="${sam_xml//>/\&gt;}"; sam_xml="${sam_xml//\"/\&quot;}"
    sam_xml="${sam_xml//\'/\&apos;}"
}

sam_amiga_stage() { # copy only in background, before publishing the candidate
    local destination="${sam_session:-$mrsamtmp}/Amiga_shared" size
    [[ ! -f "$destination/.sam-ready" ]] || return 0
    mkdir -p "$destination"
    if [[ -d "$amigapath/shared" ]]; then
        read -r size _ < <(du -sm "$amigapath/shared")
        if ((size < 30)); then cp -a "$amigapath/shared/." "$destination/" || return 1
        else echo 'SAM: Amiga shared exceeds 30 MiB; using temporary shared directory.' >&2; fi
    fi
    : > "$destination/.sam-ready"
}

sam_amiga_mount() {
    [[ "${sam_amiga_mounted:-0}" != 1 ]] || return 0
    local destination="${sam_session:-$mrsamtmp}/Amiga_shared"
    # Compatibility modes may select in the foreground; normal mode always
    # arrives here with the data already staged by its preparer.
    [[ -f "$destination/.sam-ready" ]] || sam_amiga_stage || return 1
    mkdir -p "$amigapath/shared"
    if mountpoint -q "$amigapath/shared"; then return 0; fi
    sam_mount_bind "$destination" "$amigapath/shared" || return 1
    sam_amiga_mounted=1
}

sam_cancel_launch_job() {
    [[ -n "${sam_launch_pid:-}" ]] || return 0
    if [[ -n "${sam_launch_group:-}" ]]; then
        sam_job_cancel "$sam_launch_pid" "$sam_launch_start" "$sam_launch_group" "$sam_launch_sid" || return 1
    elif sam_pid_start "$sam_launch_pid" && [[ "$sam_proc_start" == "$sam_launch_start" ]]; then sam_kill_tree "$sam_launch_pid" "$sam_launch_start"; fi
    if sam_pid_start "$sam_launch_pid" && [[ "$sam_proc_start" == "$sam_launch_start" ]]; then
        sam_job_error='Launch process did not exit'; return 1
    fi
    wait "$sam_launch_pid" 2>/dev/null || true
    sam_launch_pid= sam_launch_start= sam_launch_group= sam_launch_sid=
}

sam_run_owned_command() { # cancellable foreground setup work for a mode
    sam_cancel_launch_job || return 1
    sam_job_spawn sam_launch "$@" || return 1
    local command_rc=0
    # Registration deliberately STOPs/CONTinues the child. A queued stop-state
    # notification is not the command's exit status; wait for termination.
    wait -f "$sam_launch_pid" || command_rc=$?
    sam_cancel_launch_job || return 1
    return "$command_rc"
}

sam_cd32_start() {
    sam_cancel_launch_job || return 1
    sam_job_spawn sam_launch sam_cd32_job
}

sam_cd32_job() { sleep 10; "$mrsampath/mbc" raw_seq :30; }

sam_start_bios_skip() { # asynchronous, owned by this launch and cancelled on Next
    local skip_core="$1" callback=skipmessage
    if [[ "$skip_core" == ao486 ]]; then callback=skipmessage_ao486
    elif [[ "$skipmessage" != yes || "${CORE_SKIP[$skip_core]-}" != yes ]]; then return 0; fi
    sam_cancel_launch_job || return 1
    sam_job_spawn sam_launch "$callback" "$skip_core"
}

function load_core() { # load_core core [/path/to/rom] [name_of_rom]
    sam_cancel_launch_job || return 1
    local core=${1}
    configpath="${cfgcore_configpath:-${SAM_CONFIG_ROOT:-$misterpath/config}}"
    local rompath_arg=${2}
    local romname_arg=${3}
    local display_core="${4:-$core}" display_rompath="${5:-$rompath_arg}" display_setname=""
    sam_core_require "$display_core" || { local rule_rc=$?; printf 'SAM: %s\n' "$sam_core_reason" >&2; return "$rule_rc"; }
    sam_is_excluded "$display_core" "$display_rompath" && return 1
    sam_emit launch_validate "$display_core" "$display_rompath" || return $?

    # Refuse hardware dispatch if this session has lost ownership.
    sam_publish_phase loading || return 2

    # --- Local variables for unified logic ---
    local gamename tty_corename launch_cmd streamtitle mute_target rompath romname post_launch_hook

    # This is the primary router for all core-specific logic.
    case "${core}" in
        "arcade"|"stv")
            ### MRA Core Loader (Arcade, ST-V) ###
            # --- Prerequisite Check ---
            if [[ -n "$cfgarcade_configpath" ]]; then
                configpath="$cfgarcade_configpath"
            fi
            # --- End Prerequisite Check ---

            rompath="${rompath_arg}"
            : # Path is literal data, never shell-unescaped.

            if [ ! -f "${rompath}" ]; then
                echo "ERROR: MRA file not found after pick and sanitize: '${rompath}'" >&2
                return 1
            fi

            gamename="${rompath##*/}"; gamename="${gamename%.*}"
            if [[ "${sam_prepared_core:-}:${sam_prepared_path:-}" == "$core:$rompath" && -n "${sam_candidate_setname:-}" ]]; then
                tty_corename=${sam_candidate_setname//[^[:alnum:]]/}
            else
                tty_corename=$(grep "<setname>" "${rompath}" | sed -e 's/<setname>//' -e 's/<\/setname>//' | tr -cd '[:alnum:]')
            fi
            mute_target="${tty_corename:-$gamename}"
            launch_cmd="load_core ${rompath}"
            ;;

        "ao486")
            ### ao486 MGL Loader ###


            rompath="${rompath_arg}"
            romname="${rompath##*/}"
            gamename="${romname%.*}"; gamename="${gamename//_/ }"
            tty_corename="${core}"
            mute_target="${core}"
            launch_cmd="load_core ${rompath}"
            post_launch_hook=sam_start_bios_skip
            ;;

        "x68k")
            ### x68k MGL Loader ###


            rompath="${rompath_arg}"
            romname="${rompath##*/}"
            gamename="${romname%.*}"; gamename="${gamename//_/ }"
            tty_corename="${core}"
            mute_target="${core}"
            launch_cmd="load_core ${rompath}"
            ;;

        "mgls")
           rompath="${rompath_arg}"
           romname="${rompath##*/}"
           gamename="${romname_arg:-${romname%.*}}"
           tty_corename=$(grep -oP '(?<=<rbf>)[^<]+' "${rompath}" 2>/dev/null | xargs -r basename | cut -d. -f1)
           mute_target="${tty_corename}"
           [ -f "${rompath}" ] && cp "${rompath}" /tmp/SAM_Game.mgl
           launch_cmd="load_core ${rompath}"
           post_launch_hook=sam_start_bios_skip
           ;;

        "amiga")
            ### Amiga (MegaAGS) Loader ###
            # --- Prerequisite Check ---
            if ! [ -f "${amigapath}/MegaAGS.hdf" ] && ! [ -f "${amigapath}/AmigaVision.hdf" ]; then
                echo "ERROR - MegaAGS/AmigaVision pack not found. Skipping core..." >&2
                delete_from_corelist amiga
                return 1
            fi
            # --- End Prerequisite Check ---

            sam_amiga_mount || return 1
            gamename="${rompath_arg}"

            if [ -z "${gamename}" ]; then
                echo "ERROR: Failed to pick an Amiga game from the list." >&2
                return 1
            fi

			# Create the directory if it doesn't exist
			mkdir -p "${amigapath}/shared"

            local ags_boot_title="${gamename//Demo: /}"
            echo "${ags_boot_title}" > "${amigapath}/shared/ags_boot"

            tty_corename="Minimig"
            mute_target="Minimig"
            if [ -f "/media/fat/_Computer/Amiga.mgl" ]; then
                launch_cmd="load_core /media/fat/_Computer/Amiga.mgl"
                mute_target="Amiga"
            else
                launch_cmd="load_core ${amigacore}"
            fi
            ;;

        "amigacd32")
            ### Amiga CD32 Loader ###
            # --- Prerequisite Check ---
            if ! [ -f "/media/fat/_Console/Amiga CD32.mgl" ]; then
                echo "ERROR - /media/fat/_Console/Amiga CD32.mgl not found. Skipping core..." >&2
                delete_from_corelist amigacd32
                return 1
            fi
            # --- End Prerequisite Check ---

            gamename="${romname_arg%.*}"
            mute_target="amigacd32"

            local CONFIG_FILE="/media/fat/config/AmigaCD32.cfg"
            if [ ! -f "$CONFIG_FILE" ]; then
                echo "ERROR - /media/fat/config/AmigaCD32.cfg not found. Skipping core." >&2
                delete_from_corelist amigacd32; return 1
            fi
            local new_path=$(echo "$rompath_arg" | sed -e 's|^/media||' -e 's|^/||')
            if [[ "$new_path" != ../* ]]; then new_path="../$new_path"; fi
            dd if=/dev/zero bs=1 count=108 seek=3100 of="$CONFIG_FILE" conv=notrunc &>/dev/null
            echo -n "$new_path" | dd of="$CONFIG_FILE" bs=1 seek=3100 conv=notrunc &>/dev/null

            launch_cmd="load_core /media/fat/_Console/Amiga CD32.mgl"
            post_launch_hook=sam_cd32_start
            ;;

        *)
            ### Default ROM-based MGL Loader (Consoles, NeoGeo, etc.) ###
            rompath="${rompath_arg}"
            romname="${romname_arg}"
            gamename="${romname_arg}"

            if [ "${core}" == "neogeo" ] && [ "${useneogeotitles}" == "yes" ]; then
                for e in "${!NEOGEO_PRETTY_ENGLISH[@]}"; do
                    if [[ "$rompath" == *"$e"* ]]; then gamename="${NEOGEO_PRETTY_ENGLISH[$e]}"; break; fi
                done
            fi

            tty_corename="${TTY2OLED_PIC_NAME[${core}]}"
            mute_target="${CORE_LAUNCH[${core}]}"

            local mgl_file=${sam_launch_mgl_path:-/tmp/SAM_Game.mgl}
            local previous_mgl=${sam_launch_previous_mgl_path:-/tmp/SAM_game.previous.mgl}
            if [ -s "$mgl_file" ]; then cp "$mgl_file" "$previous_mgl" || return 1; fi
            if [[ "${sam_engine_adapter_verified:-0}" == 1 &&
                  "${sam_prepared_core:-}" == "$core" && "${sam_prepared_path:-}" == "$rompath" &&
                  -n "${sam_candidate_mgl:-}" ]]; then
                printf '%s\n' "$sam_candidate_mgl" > "$mgl_file" || return 1
            else
                sam_run_owned_command python3 "$mrsampath/sam_mgl.py" "$core" "$rompath" \
                    --sd-root "$misterpath" --rbf-folder "${CORE_PATH_RBF[$core]}" -o "$mgl_file" || return $?
            fi

            launch_cmd="load_core $mgl_file"

            post_launch_hook=sam_start_bios_skip
            ;;
    esac

    # --- Common Execution Block ---

    sam_exit_trace launch_audio_begin
    if [[ -n "${mute_target}" ]] && ! mute "${mute_target}"; then
        sam_core_reason="Audio protection failed for ${mute_target}; refusing core launch"
        printf 'SAM: %s\n' "$sam_core_reason" >&2
        return 2
    fi
    sam_exit_trace launch_audio_end
    sam_emit launch_info

    echo -n "Starting now on the "; echo -ne "\e[4m${CORE_PRETTY[${core}]}\e[0m: "; echo -e "\e[1m${gamename}\e[0m"
    [[ -n "$streamtitle" ]] && echo -e "BGM playing: \e[1m${streamtitle}\e[0m"

    echo "${gamename} (${core})" >/tmp/SAM_Game.txt
    echo "${gamename}" >/tmp/ACTIVEGAME

    sam_exit_trace launch_dispatch_begin
    timeout 1s bash -c 'printf "%s\n" "$1" > /dev/MiSTer_cmd' _ "$launch_cmd" || return 1
    sam_exit_trace launch_dispatch_end
    # Reporting observes a delivered launch. Keep optional display work and log
    # formatting out of the path before Main receives the prepared command.
    local log_stamp
    printf -v log_stamp '%(%H:%M:%S)T' -1
    printf '%s - %s - %s\n' "$log_stamp" "$core" "${rompath:-$gamename}" >> "$sam_game_log"
    sam_emit launch_observe
    if [[ "${mute}" == core && -n "${sam_session:-}" && -d "$sam_session" ]]; then
        printf '%s\n' "${launch_cmd#load_core }" > "$sam_session/launch-path"
    fi
    if [[ "$display_core" == arcade || "$display_core" == stv ]]; then
        if [[ "${sam_prepared_core:-}:${sam_prepared_path:-}" == "$display_core:$display_rompath" && -n "${sam_candidate_setname:-}" ]]; then
            display_setname=$sam_candidate_setname
        else
            display_setname=$(sed -n 's/.*<setname[^>]*>\([^<]*\)<\/setname>.*/\1/p' "$display_rompath" | head -n 1)
        fi
    fi
    sam_emit display_launch "$gamename" "$display_rompath" "$display_core" "$display_setname"

    if [ -n "${post_launch_hook}" ]; then
        "$post_launch_hook" "$core"
    fi

    # The resident engine sequences launch and countdown through acknowledged
    # adapter operations. A fixed sleep adds latency without proving that Main
    # finished loading; BIOS skips already have their own owned delayed job.
    # Keep the compatibility loop's historical settling delay.
    [[ "${sam_engine_adapter_verified:-0}" == 1 ]] || sleep 1
    return 0
}

function skipmessage() {
    local core=${1}

    # Exit immediately if the core argument is missing, for safety.
    if [ -z "${core}" ]; then
        return
    fi

    # Check the global 'skipmessage' setting AND the core-specific setting from the CORE_SKIP array.
    if [ "${skipmessage}" == "yes" ] && [ "${CORE_SKIP[${core}]}" == "yes" ]; then
        # Preserve the global delay, with a core-specific readiness minimum.
        local skip_delay="$skiptime" minimum="${CORE_SKIP_MIN_DELAY[$core]:-0}" whole
        if [[ "$skip_delay" =~ ^([0-9]+)(\.[0-9]+)?$ ]]; then
            whole=${BASH_REMATCH[1]}
            ((10#$whole >= minimum)) || skip_delay=$minimum
        fi
        sleep "$skip_delay"
        samdebug "Button push sent for '${core}' to skip BIOS"
        if [ "${core}" == "intellivision" ]; then
            "${mrsampath}/mbc" raw_seq :1C
            sleep 1
            "${mrsampath}/mbc" raw_seq :02
            sleep 1
            "${mrsampath}/mbc" raw_seq :1C
            sleep 1
            "${mrsampath}/mbc" raw_seq :02
            sleep 1
            "${mrsampath}/mbc" raw_seq :1C
            sleep 1
            "${mrsampath}/mbc" raw_seq :03
            sleep 1
            "${mrsampath}/mbc" raw_seq :1C
        else
            "${mrsampath}/mbc" raw_seq :31
            sleep 1
            "${mrsampath}/mbc" raw_seq :31
        fi
    fi
}

function skipmessage_ao486() {
		sleep "$skiptime"
		samdebug "Button pushes sent to (hopefully) skip past selection screens"
		"${mrsampath}/mbc" raw_seq :02
		sleep 1
		"${mrsampath}/mbc" raw_seq :22
		sleep 1
		"${mrsampath}/mbc" raw_seq :1C
		sleep 1
		"${mrsampath}/mbc" raw_seq :19
		sleep 1
		"${mrsampath}/mbc" raw_seq :32
		sleep 1
		"${mrsampath}/mbc" raw_seq :3B

}

function mglfavorite() {
	# Add current game to _Favorites folder

	if [ ! -d "${misterpath}/_Favorites" ]; then
		mkdir -p "${misterpath}/_Favorites"
	fi
	cp /tmp/SAM_Game.mgl "${misterpath}/_Favorites/$(cat /tmp/SAM_Game.txt).mgl"

}

function core_error_checklist() { # core_error core /path/to/ROM
		delete_from_corelist "${1}"
		echo " List of cores is now: ${corelist[*]}"
		declare -g romloadfails=0
		# Load a different core
		next_core

}

declare -ga SAM_OWNED_MOUNTS=()
sam_mount_bind() {
    mountpoint -q "$2" && return 0
    mount --bind "$1" "$2" || return 1
    SAM_OWNED_MOUNTS+=("$2")
}
function disable_bootrom() {
    [[ "$disablebootrom" == yes ]] || return 0
    mkdir -p "$gamelistpathtmp/Bootrom"
    [[ ! -d "$misterpath/Bootrom" ]] || sam_mount_bind "$gamelistpathtmp/Bootrom" "$misterpath/Bootrom" || return 1
    local number
    for number in 1 2 3; do
        [[ -f "$misterpath/Games/NES/boot$number.rom" ]] || continue
        : > "$brfake"
        sam_mount_bind "$brfake" "$misterpath/Games/NES/boot$number.rom" || return 1
    done
}
