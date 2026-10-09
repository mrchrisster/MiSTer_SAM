# SPDX-License-Identifier: GPL-3.0-or-later
Artwork_only=Yes
sam_artwork_root="$mrsampath/artwork"
source "$sam_artwork_root/sam_artwork.sh" || return 1

sam_artwork_mode_check() {
    case "$sam_mode" in
        m82|video|samvideo)
            sam_core_reason="Artwork-only filtering does not support $sam_mode auxiliary launches"
            printf 'SAM artwork: %s\n' "$sam_core_reason" >&2
            return 1 ;;
    esac
}

sam_artwork_prepare_candidate() { # core path; background only
    python3 "$sam_artwork_root/sam_artwork.py" \
        --source "${Artwork_source:-database}" --style "${Artwork_style:-box3d}" \
        --database "$sam_artwork_root/database" --downloads "$sam_artwork_root/downloads" \
        --cache "$sam_artwork_root/${1}_cache.json" --check "$1" "$2" \
        --cover-output "$sam_job/cover" --protected-root "$sam_session/ready" || {
        printf 'SAM artwork ERROR: cover preparation failed for %s: %s\n' "$1" "$2" >&2
        return 3
    }
    read -r sam_candidate_cover < "$sam_job/cover"
    [[ -s "$sam_candidate_cover" ]] || return 3
}

sam_artwork_validate_launch() {
    [[ -n "${sam_candidate_cover:-}" && -s "$sam_candidate_cover" ]] || {
        echo 'SAM artwork ERROR: prepared cover is unavailable; current game retained.' >&2
        return 3
    }
}

sam_register session_validate sam_artwork_mode_check
sam_register candidate_filter sam_artwork_filter
sam_register candidate_prepare sam_artwork_prepare_candidate
sam_register launch_validate sam_artwork_validate_launch
sam_register filter_stamp sam_artwork_stamp
