# Filter only the selected core's current list; never scan at initialization.
sam_artwork_root="$mrsampath/artwork"
sam_artwork_resolver="$sam_artwork_root/sam_artwork_resolver.py"

sam_artwork_setup() {
    local IFS=,
    local cores="${2:-${Artwork_db_cores:-${corelist[*]}}}" options=()
    [[ "${1:-}" == refresh ]] && options+=(--refresh)
    python3 "$sam_artwork_root/sam_artwork_database.py" --root "$sam_artwork_root/database" \
        --cores "$cores" "${options[@]}"
}

sam_artwork_prepare_list() {
    # Runs for this selected core before normal list preparation/deduplication.
    # Changing source or explicitly refreshing the DB restores pruned candidates.
    local core="$1" marker="$gamelistpathtmp/${1}.artwork-source" generation=""
    local token="${Artwork_only,,}:${Artwork_source:-packs}:${Artwork_style:-box2d}"
    if [[ "${Artwork_source:-packs}" == database ]]; then
        [[ ! -r "$sam_artwork_root/database/.generation" ]] || read -r generation < "$sam_artwork_root/database/.generation" || true
        token+=":$generation"
    fi
    if [[ ! -f "$marker" || "$(cat "$marker")" != "$token" ]]; then
        if [[ -f "$marker" || "${Artwork_only,,}" == yes ]]; then
            rm -f "$gamelistpathtmp/${core}_gamelist.txt"
        fi
        printf '%s\n' "$token" > "$marker"
    fi
}

sam_artwork_stamp() {
    local core="$1" folders=() folder mount paths=()
    case "$core" in
        nes) folders=(NES FDS);; fds) folders=(FDS NES);;
        snes) folders=(SNES Satellaview);; n64) folders=(N64);;
        gb|gbc|sgb) folders=(GAMEBOY GBC);; gba) folders=(GBA);;
        genesis) folders=(Genesis SMS);; sms) folders=(SMS);; gg) folders=(GameGear);;
        megacd) folders=(MegaCD);; saturn) folders=(Saturn);;
        tgfx16) folders=(TGFX16);; tgfx16cd) folders=(TGFX16-CD);;
        psx) folders=(PSX);; atari2600) folders=(Atari2600);;
        atari5200) folders=(ATARI5200);; atari7800) folders=(ATARI7800 Atari2600);;
        atarilynx) folders=(AtariLynx);; jaguar) folders=(Jaguar);;
        neogeo) folders=(NEOGEO NeoGeo-CD);; neogeocd) folders=(NeoGeo-CD);;
        s32x) folders=(S32X);; colecovision) folders=(Coleco);;
        intellivision) folders=(Intellivision);; vectrex) folders=(VECTREX);;
        wonderswan) folders=(WonderSwan);; wonderswancolor) folders=(WonderSwanColor);;
        amigacd32) folders=(AmigaCD32);; cdi) folders=(CD-i);;
        arcade|stv) folders=(Arcade);; 3do) folders=(3DO);;
    esac
    printf 'source=%s style=%s\n' "${Artwork_source:-packs}" "${Artwork_style:-box2d}"
    paths=("$sam_artwork_resolver" "$sam_artwork_root/sam_artwork.py" "$gamelistpath/${core}_gamelist.txt")
    if [[ "${Artwork_source:-packs}" == database ]]; then
        paths+=("$sam_artwork_root/sam_artwork_database.py")
    fi
    for folder in "${folders[@]}"; do
        if [[ "${Artwork_source:-packs}" == database ]]; then
            paths+=("$sam_artwork_root/database/docs/$folder/Artwork/index.tsv" "$sam_artwork_root/database/docs/$folder/Artwork/gameinfo.tsv")
            continue
        fi
        for mount in /media/fat /media/usb{0..7}; do
            if [[ -d "$mount/docs/$folder/Artwork" ]]; then
                paths+=("$mount/docs/$folder/Artwork" "$mount/docs/$folder/Artwork/index.tsv")
                break
            fi
        done
    done
    # Directory timestamps reflect image additions/removals; index/master changes
    # invalidate matching. The launch guard checks overwritten image contents.
    stat -c '%n:%s:%y' "${paths[@]}" 2>/dev/null
}

sam_artwork_filter() {
    [[ "${Artwork_only,,}" == "yes" ]] || return 0
    local core="${1:-$nextcore}"
    local list="$gamelistpathtmp/${core}_gamelist.txt"
    local eligible="$sam_artwork_root/eligible/${core}_gamelist.txt"
    local known="$sam_artwork_root/eligible/${core}_known.txt"
    local marker="$sam_artwork_root/eligible/${core}.stamp"
    local stamp
    mkdir -p "$sam_artwork_root/eligible"
    stamp="$(sam_artwork_stamp "$core")"
    if [[ -f "$marker" && -f "$known" && -f "$eligible" && "$(cat "$marker")" == "$stamp" ]]; then
        # One AWK pass preserves SAM's post-deduplication order and norepeat list.
        # Unseen candidates trigger matching only for this newly changed list.
        if awk 'FILENAME==ARGV[1]{known[$0]=1;next}
                FILENAME==ARGV[2]{allowed[$0]=1;next}
                {if (!($0 in known)) unknown=1; if ($0 in allowed) print}
                END{if(unknown)exit 2}' "$known" "$eligible" "$list" > "$list.artwork"; then
            mv "$list.artwork" "$list"
            [[ -s "$list" ]]
            return $?
        fi
    fi
    cp "$list" "$known.tmp"
    python3 "$sam_artwork_root/sam_artwork.py" \
        --source "${Artwork_source:-packs}" --style "${Artwork_style:-box2d}" \
        --database "$sam_artwork_root/database" --downloads "$sam_artwork_root/downloads" \
        --cache "$sam_artwork_root/${core}_cache.json" --lists "$gamelistpathtmp" \
        --cores "$core" --output "$sam_artwork_root/eligible" --names-only >&2 || {
        local artwork_rc=$?
        rm -f "$known.tmp" "$list.artwork"
        if [[ "$artwork_rc" == 3 ]]; then
            echo "SAM artwork ERROR: cannot download $core catalogs; stopping before launch. Restart SAM to retry." >&2
            return 3
        fi
        echo "SAM artwork: skipping $core (no matching artwork)." >&2
        return 1
    }
    mv "$known.tmp" "$known"
    if [[ "${Artwork_source:-packs}" == database && -r "$sam_artwork_root/database/.generation" ]]; then
        local generation
        read -r generation < "$sam_artwork_root/database/.generation" || true
        printf '%s\n' "${Artwork_only,,}:${Artwork_source:-packs}:${Artwork_style:-box2d}:$generation" > "$gamelistpathtmp/${core}.artwork-source"
    fi
    # If artwork changed during the scan, the next pick must rebuild.
    [[ "$(sam_artwork_stamp "$core")" == "$stamp" ]] && printf '%s\n' "$stamp" > "$marker"
    rm -f "$list.artwork"
    cp "$eligible" "$list"
    [[ -s "$list" ]]
}

sam_artwork_guard() {
    [[ "${Artwork_only,,}" == "yes" ]] || return 0
    # Decode the chosen image before launching, rather than every image in a pack.
    python3 "$sam_artwork_root/sam_artwork.py" \
        --source "${Artwork_source:-packs}" --style "${Artwork_style:-box2d}" \
        --database "$sam_artwork_root/database" --downloads "$sam_artwork_root/downloads" \
        --cache "$sam_artwork_root/${1}_cache.json" --check "$1" "$2" || {
        echo "SAM artwork: launch refused ($1): $2. Stopping." >&2
        exit 1
    }
}
