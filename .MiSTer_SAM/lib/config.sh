# SPDX-License-Identifier: GPL-3.0-or-later
# Extracted compatibility implementation; see reference and attribution.

function init_vars() {
	declare -g sam_game_log="${SAM_GAME_LOG:-/tmp/SAM_Games.log}"
	declare -g sam_display_state_file="${SAM_STATE_FILE:-/tmp/SAM_state}"
	declare -g sam_display_owner_start=""
	declare -gl monitorenable="no"
	declare -g mrsampath="${SAM_ROOT:-/media/fat/Scripts/.MiSTer_SAM}"
	declare -g misterpath="${SAM_MISTER_ROOT:-/media/fat}"
	declare -g mrsamtmp="${SAM_TMP_ROOT:-/tmp/.SAM_tmp}"
	# Save our PID and process
	declare -g sampid="${$}"
	declare -g samprocess
	samprocess="${0##*/}"
	declare -g menuonly="Yes"
	declare -g key_activity_file="/tmp/.SAM_tmp/SAM_Keyboard_Activity"
	declare -g joy_activity_file="/tmp/.SAM_tmp/SAM_Joy_Activity"
	declare -g mouse_activity_file="/tmp/.SAM_tmp/SAM_Mouse_Activity"
	declare -g sam_menu_file="/tmp/.SAMmenu"
	declare -g brfake="$mrsamtmp/brfake"
	declare -g Artwork_only="No"
	declare -g Artwork_source="database"
	declare -g Artwork_style="box3d"
	declare -g Artwork_db_cores=""
	declare -g samini_file="${SAM_INI:-/media/fat/Scripts/MiSTer_SAM.ini}"
	declare -g samini_update_file="${mrsampath}/MiSTer_SAM.default.ini"
	declare -gi inmenu=0
	declare -gi MENU_LOADED=0
	declare -gi sam_bgmmenu=0
	declare -gi shown=0
	declare -gi coreretries=3
	declare -gi romloadfails=0
	declare -g gamelistpath="${SAM_LIST_ROOT:-/media/fat/SAM}/Gamelists"
	declare -g listroot="${SAM_LIST_ROOT:-/media/fat/SAM}"
	declare -g ratedpath="$listroot/Rated" blacklistpath="$listroot/Blacklists" ignorepath="$listroot/Ignore"
	declare -g gamelistpathtmp="${SAM_SESSION_LIST_ROOT:-/tmp/.SAM_List}"
	declare -g tmpfile="$gamelistpathtmp/tmpfile"
	declare -g tmpfile2="$gamelistpathtmp/tmpfile2"
	declare -g tmpfilefilter="$gamelistpathtmp/tmpfilefilter"
	declare -g corelistfile="$gamelistpathtmp/corelist"
	declare -g core_count_file="/tmp/.SAM_tmp/sv_corecount"
	declare -gi disablecoredel="0"
	declare -gi gametimer=120
	declare -gl corelist="amiga,amigacd32,ao486,arcade,atari2600,atari5200,atari7800,atarilynx,c64,cdi,coco2,colecovision,intellivision,fds,gb,gbc,gba,genesis,gg,jaguar,megacd,n64,neogeo,neogeocd,nes,s32x,saturn,sgb,sms,snes,stv,tgfx16,tgfx16cd,3do,vectrex,wonderswan,wonderswancolor,psx,x68k,mgls"
	declare -gl corelistall="${corelist}"
	declare -gl skipmessage="Yes"
	declare -gl disablebootrom="no"
	declare -gl skiptime="10"
	declare -gl norepeat="Yes"
	declare -gl disable_blacklist="No"
    declare -gl category_preset="off"
	declare -gl amigaselect="All"
	declare -gl m82="no"
	declare -gi m82_game_timer=180      # How long (secs) user can play in M82 play mode
	declare -gl m82_muted="no"          # Whether to mute audio during M82 demo/bios
	declare -g  m82_phase_file="/tmp/.SAM_tmp/m82_phase"  # "bios" or "game"
	declare -gl sam_goat_list="no"
	declare -gl mute="No"
	declare -gi update_done=0
	declare -gl ignore_when_skip="no"
	declare -gl coreweight="No"
	declare -gi gamelists_created=0
	declare -gl playcurrentgame="No"
	declare -gl kids_safe="No"
	declare -gl rating="No"
	declare -gl dupe_mode="normal"
	declare -gl listenmouse="Yes"
	declare -gl listenkeyboard="Yes"
	declare -gl listenjoy="Yes"
	declare -gl mgls_dirs=""
	declare -g repository_url="https://github.com/mrchrisster/MiSTer_SAM"
	declare -g branch="test"
	declare -g raw_base="https://raw.githubusercontent.com/mrchrisster/MiSTer_SAM/${branch}"
	declare -gi counter=0
	declare -gA corewc
	declare -gA corep
	declare -g userstartup="/media/fat/linux/user-startup.sh"
	declare -g userstartuptpl="/media/fat/linux/_user-startup.sh"
	declare -gl useneogeotitles="Yes"
	declare -gl arcadeorient
	declare -gl checkzipsondisk="No"
	declare -gl force_zip_scan="No"
	declare -gl check_for_new_games="Yes"
    declare -gl update_gamelists_during_play="No"
	declare -gi bootsleep="60"
	declare -gi totalgamecount
	# ======== DEBUG VARIABLES ========
	declare -gl samdebug="No"
	declare -gl samdebuglog="No"
	# ======== BGM =======
	declare -gl bgm="No"
	declare -gl bgmplay="Yes"
	declare -gl bgmstop="Yes"
	declare -gi gvoladjust="0"

	# ======== TTY2OLED =======
	declare -g TTY_cmd_pipe="${mrsamtmp}/TTY_cmd_pipe"
	declare -gl ttyenable="No"
	declare -gi ttyupdate_pause=10
	declare -g tty_currentinfo_file=${mrsamtmp}/tty_currentinfo
	declare -g tty_sleepfile="/tmp/tty2oled_sleep"
	declare -gl ttyname_cleanup="no"
	declare -gA tty_currentinfo=(
		[core_pretty]=""
		[name]=""
		[core]=""
		[date]=0
		[counter]=0
		[name_scroll]=""
		[name_scroll_position]=0
		[name_scroll_direction]=1
		[update_pause]=${ttyupdate_pause}
	)

	# ======== SAMVIDEO =======
	declare -gA SV_TVC_CL
	declare -gl samvideo
	declare -gl samvideo_freq
	declare -gl samvideo_output="hdmi"
	declare -gl samvideo_source
	declare -gl samvideo_tvc_cdi
	declare -gl samvideo_tvc
	declare -gl download_manager="yes"
	declare -gl sv_aspectfix_vmode
	declare -gl sv_inimod="yes"
	declare -gl sv_inibackup="yes"
	declare -gl keep_local_copy="yes"
	declare -gl do_fast_chd_fill="no"
	declare -gl new_only_chd="no"

	declare -g sv_inibackup_file="/media/fat/MiSTer.ini.sam_backup"
	declare -g samvideo_crtmode="video_mode=640,16,64,80,240,1,3,14,12380"
	declare -g samvideo_displaywait="2"
	declare -g tmpvideo="/tmp/SAMvideo.mp4"
	declare -g ini_file="$misterpath/MiSTer.ini"
	declare -g ini_contents=""
	declare -g sv_ini_temp_file="/tmp/MiSTer.ini.samvideo"
	declare -g sv_core="/tmp/.SAM_tmp/sv_core"
	declare -g sv_gametimer_file="/tmp/.SAM_tmp/sv_gametimer"
	declare -g sv_loadcounter=0
	declare -g samvideo_path="/media/fat/video"
	declare -g sv_archive_cdi="https://archive.org/download/mister-sam-cdi-vcd-commercials/mister-sam-cdi-vcd-commercials_files.xml"
	declare -g sv_archive_hdmilist="https://archive.org/download/640x480_videogame_commercials/640x480_videogame_commercials_files.xml"
	declare -g sv_archive_crtlist="https://archive.org/download/640x240_videogame_commercials/640x240_videogame_commercials_files.xml"


	# ======== CORE PATHS RBF ========
	declare -g amigapathrbf="_Computer"
	declare -g amigacd32pathrbf="_Computer"
	declare -g arcadepathrbf="_Arcade"
	declare -g ao486pathrbf="_Computer"
	declare -g atari2600pathrbf="_Console"
	declare -g atari5200pathrbf="_Console"
	declare -g atari7800pathrbf="_Console"
	declare -g atarilynxpathrbf="_Console"
	declare -g c64pathrbf="_Computer"
	declare -g cdipathrbf="_Console"
	declare -g coco2pathrbf="_Computer"
	declare -g colecovisionpathrbf="_Console"
	declare -g intellivisionpathrbf="_Console"
	declare -g fdspathrbf="_Console"
	declare -g gbpathrbf="_Console"
	declare -g gbcpathrbf="_Console"
	declare -g gbapathrbf="_Console"
	declare -g genesispathrbf="_Console"
	declare -g ggpathrbf="_Console"
	declare -g jaguarpathrbf="_Console"
	declare -g threedopathrbf="_Console"
	declare -g megacdpathrbf="_Console"
	declare -g n64pathrbf="_Console"
	declare -g neogeopathrbf="_Console"
	declare -g neogeocdpathrbf="_Console"
	declare -g nespathrbf="_Console"
	declare -g s32xpathrbf="_Console"
	declare -g saturnpathrbf="_Console"
	declare -g sgbpathrbf="_Console"
	declare -g smspathrbf="_Console"
	declare -g snespathrbf="_Console"
	declare -g stvpathrbf="_Arcade"
	declare -g tgfx16pathrbf="_Console"
	declare -g tgfx16cdpathrbf="_Console"
    declare -g psxpathrbf="_Console"
    declare -g vectrexpathrbf="_Console"
    declare -g wonderswanpathrbf="_Console"
    declare -g wonderswancolorpathrbf="_Console"
    declare -g x68kpathrbf="_Computer"


	special_cores=(amiga ao486 x68k) #amigacd32 uses normal gamelists since it's chd files

	declare -g configpath="${SAM_CONFIG_ROOT:-/media/fat/config}"
}



function read_samini() {
	if [ ! -f "${samini_file}" ]; then
        echo "Creating SAM INI from installed defaults."
        cp "$samini_update_file" "$samini_file" || return 1
	fi
    # Capture the trusted INI baseline around startup. The later RAM
    # baseline is comparison data and is never sourced by the reload protocol.
    sam_config_ini_snapshot=$(cat "$samini_file") || return 1
	source "${samini_file}"
    sam_config_category_snapshot= sam_config_roulette_snapshot=
    [[ ! -f "$mrsamtmp/category-preset" ]] || sam_config_category_snapshot=$(cat "$mrsamtmp/category-preset")
    [[ ! -f "$mrsamtmp/gameroulette.ini" ]] || sam_config_roulette_snapshot=$(cat "$mrsamtmp/gameroulette.ini")
    [[ "${sam_modules_loaded:-0}" != 1 ]] || sam_module_config_dirty=1
    [[ "${1:-}" == --ui ]] || sam_config_paths

	declare -g raw_base="https://raw.githubusercontent.com/mrchrisster/MiSTer_SAM/${branch}"

	#corelist=("$(echo "${corelist[@]}" | tr ',' ' ' | tr -s ' ')")
	IFS=',' read -ra corelist <<< "${corelist}"
	IFS=',' read -ra corelistall <<< "${corelistall}"

	#BGM mode
	if [ "${bgm}" == "yes" ]; then
		mute="core"
	fi

    # These modes use explicit commercial/M82 mappings rather than ordinary
    # artwork eligibility. Reading configuration never rewrites the user's INI.
    if [[ "${m82,,}" == yes || "${samvideo,,}" == yes ]]; then Artwork_only=No; fi


}

function update_samini() {
	[ ! -f /media/fat/Scripts/.config/downloader/downloader.log ] && return
	[ ! -f ${samini_file} ] && return
	if [[ "$(cat /media/fat/Scripts/.config/downloader/downloader.log | grep -c "MiSTer_SAM.default.ini")" != "0" ]] && [ "${samini_update_file}" -nt "${samini_file}" ]; then
		echo "New MiSTer_SAM.ini version downloaded from update_all. Merging with new ini."
		echo "Backing up MiSTer_SAM.ini to MiSTer_SAM.ini.bak"
		cp "${samini_file}" "${samini_file}".bak
		echo -n "Merging ini values.."
		# In order for the following awk script to replace variable values, we need to change our ASCII art from "=" to "-"
		sed -i 's/==/--/g' "${samini_file}"
		sed -i 's/-=/--/g' "${samini_file}"
		#awk -F= 'NR==FNR{a[$1]=$0;next}($1 in a){$0=a[$1]}1' "${samini_file}" "${samini_update_file}" >/tmp/MiSTer_SAM.tmp && cp -f --force /tmp/MiSTer_SAM.tmp "${samini_file}"

		echo "Done."
	fi

}

samini_mod() {
  local key="$1"
  local value="$2"
  local file="${3:-${samini_file:-${SAM_INI:-/media/fat/Scripts/MiSTer_SAM.ini}}}"
  local formatted="${key}=\"${value}\""

  if grep -q "^${key}=" "$file"; then
    sed -i "/^${key}=/c\\${formatted}" "$file"
  else
    echo "$formatted" >> "$file"
  fi
}

# MiSTer.ini subfolders are literal configuration, never shell text.
sam_config_paths() {
    local line key value base="${SAM_CONFIG_ROOT:-$misterpath/config}"
    cfgcore_configpath= cfgarcade_configpath=
    if [[ -r "$ini_file" ]]; then
        while IFS= read -r line; do
            [[ "$line" == *=* ]] || continue
            key="${line%%=*}" key="${key//[[:space:]]/}"
            case "$key" in cfgcore_subfolder|cfgarcade_subfolder) ;;
                *) continue ;; esac
            value="${line#*=}" value="${value//\"/}"
            value="${value#"${value%%[![:space:]]*}"}" value="${value%"${value##*[![:space:]]}"}"
            [[ -n "$value" ]] || continue
            if [[ "$key" == cfgcore_subfolder && -z "$cfgcore_configpath" ]]; then cfgcore_configpath="$base/$value"; fi
            if [[ "$key" == cfgarcade_subfolder && -z "$cfgarcade_configpath" ]]; then cfgarcade_configpath="$base/$value"; fi
        done < "$ini_file"
    fi
    configpath="${cfgcore_configpath:-$base}"
}

# Keep source-only and library callers compatible while deferring runtime tables.
sam_config_library_root=${BASH_SOURCE[0]%/*}
init_core_names() {
    source "$sam_config_library_root/core-names.sh" || return 1
    init_core_names "$@"
}
init_data() {
    source "$sam_config_library_root/core-names.sh" || return 1
    source "$sam_config_library_root/data.sh" || return 1
    init_data "$@"
}
