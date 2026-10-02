#!/bin/bash
# Loaded only when the user opens Settings -> Artwork.
sam_artwork_menu() {
    local choice style selected core rc
    local -a rows=() selected_cores=()
    dialog --clear --ascii-lines --no-tags --cancel-label Back \
        --backtitle "Super Attract Mode" --title "[ Artwork ]" \
        --default-item "${Artwork_source:-packs}" \
        --menu "Choose how SAM checks that a game has artwork.\nCurrent: ${Artwork_source:-packs}; filter: ${Artwork_only:-No}" 0 0 0 \
        packs "Installed packs - local images, works offline" \
        database "Lightweight database - covers fetched as needed" \
        refresh "Refresh downloaded databases" \
        off "Disable artwork-only filtering" 2> "$sam_menu_file" || return 0
    choice=$(<"$sam_menu_file")
    case "$choice" in
        packs)
            cp -p "$samini_file" "${samini_file}.artwork.bak" || return 1
            samini_mod Artwork_source packs
            samini_mod Artwork_only Yes
            read_samini
            dialog --msgbox "Installed packs selected.\n\nInstall packs through Update All -> Extra Content -> Game Artwork DBs.\nRestart SAM to apply the change." 0 0
            ;;
        off)
            cp -p "$samini_file" "${samini_file}.artwork.bak" || return 1
            samini_mod Artwork_only No
            read_samini
            dialog --msgbox "Artwork-only filtering disabled. Restart SAM to apply." 0 0
            ;;
        database)
            dialog --clear --ascii-lines --no-tags --cancel-label Back \
                --title "[ Online cover style ]" --default-item "${Artwork_style:-box2d}" \
                --menu "Use the same style on your display.\nDatabase mode needs a display with online artwork fetching.\nThe selected cover is checked before each launch; uncached covers need Internet." 0 0 0 \
                box2d "2D covers" box3d "3D box art" 2> "$sam_menu_file" || return 0
            style=$(<"$sam_menu_file")
            for core in "${corelist[@]}"; do
                case "$core" in amiga|ao486|x68k|mgls) continue ;; esac
                rows+=("$core" "${CORE_PRETTY[$core]:-$core}" on)
            done
            if (( ${#rows[@]} == 0 )); then
                dialog --msgbox "Your enabled cores have no supported artwork databases. Choose other cores or use installed packs." 0 0
                return 1
            fi
            dialog --clear --ascii-lines --separate-output --cancel-label Back \
                --title "[ Download artwork databases ]" \
                --checklist "Select from your enabled SAM systems.\nOnly small catalogs are downloaded; full image packs are not installed.\nSAM skips enabled systems without a matching database." 0 0 0 \
                "${rows[@]}" 2> "$sam_menu_file" || return 0
            mapfile -t selected_cores < "$sam_menu_file"
            if (( ${#selected_cores[@]} == 0 )); then
                dialog --msgbox "Select at least one system. Settings were not changed." 0 0
                return 0
            fi
            local IFS=,
            selected="${selected_cores[*]}"
            dialog --infobox "Downloading small artwork databases. This happens during setup, not SAM startup." 0 0
            if sam_artwork_setup setup "$selected" > "$sam_artwork_root/setup.log" 2>&1; then
                cp -p "$samini_file" "${samini_file}.artwork.bak" || return 1
                samini_mod Artwork_source database
                samini_mod Artwork_style "$style"
                samini_mod Artwork_db_cores "$selected"
                samini_mod Artwork_only Yes
                read_samini
                dialog --textbox "$sam_artwork_root/setup.log" 0 0
                dialog --msgbox "Lightweight database selected.\nA small cover verification cache is limited to 32 MB.\nExisting packs and ROMs are unchanged.\nRestart SAM to apply the settings." 0 0
            else
                dialog --textbox "$sam_artwork_root/setup.log" 0 0
                dialog --msgbox "Database setup failed. Previous settings were kept. Check Internet access or select installed packs." 0 0
                return 1
            fi
            ;;
        refresh)
            dialog --infobox "Refreshing the selected databases..." 0 0
            sam_artwork_setup refresh > "$sam_artwork_root/setup.log" 2>&1
            rc=$?
            dialog --textbox "$sam_artwork_root/setup.log" 0 0
            (( rc == 0 )) || return "$rc"
            dialog --msgbox "Databases refreshed. SAM restores candidates when each core is next selected. Cores previously skipped for no matches return after restarting SAM." 0 0
            ;;
    esac
}
