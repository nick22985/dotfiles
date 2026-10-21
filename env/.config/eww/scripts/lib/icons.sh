#!/bin/bash

ICON_DIRS=("$HOME/.local/share/icons" "$HOME/.local/share/flatpak/exports/share/icons" /var/lib/flatpak/exports/share/icons /usr/share/icons)
APP_DIRS=("$HOME/.local/share/applications" "$HOME/.local/share/flatpak/exports/share/applications" /var/lib/flatpak/exports/share/applications /usr/share/applications)
ICON_SIZES=(scalable 48x48 64x64 128x128 256x256 32x32 48)
ICON_KINDS=(apps status devices categories actions)

icon_theme() {
    sed -n 's/^gtk-icon-theme-name[[:space:]]*=[[:space:]]*"\?\([^"]*\)"\?[[:space:]]*$/\1/p' \
        ~/.config/gtk-3.0/settings.ini /etc/gtk-3.0/settings.ini 2>/dev/null | head -n1
}

# A file for an icon given as a path, a file:// url or a theme icon name. Icons are shown through a
# CSS url(), so only plain names and paths are taken.
find_icon() {
    local name="${1#file://}" theme base size kind extension
    [[ -n "$name" ]] || return 1
    if [[ "$name" == /* ]]; then
        [[ "$name" =~ ^[[:alnum:]_./+\ -]+$ && -f "$name" ]] && printf '%s\n' "$name"
        return
    fi
    [[ "$name" =~ ^[[:alnum:]_.+-]+$ ]] || return 1
    for theme in $(icon_theme) hicolor Adwaita; do
        for base in "${ICON_DIRS[@]}"; do
            for size in "${ICON_SIZES[@]}"; do
                for kind in "${ICON_KINDS[@]}"; do
                    for extension in svg png; do
                        [[ -f "$base/$theme/$size/$kind/$name.$extension" ]] && { printf '%s\n' "$base/$theme/$size/$kind/$name.$extension"; return; }
                    done
                done
            done
        done
    done
    for extension in svg png; do
        [[ -f "/usr/share/pixmaps/$name.$extension" ]] && { printf '%s\n' "/usr/share/pixmaps/$name.$extension"; return; }
    done
    return 1
}

desktop_value() {
    local name="$1" key="$2" dir file
    [[ "$name" =~ ^[[:alnum:]_.+-]+$ ]] || return 1
    for dir in "${APP_DIRS[@]}"; do
        for file in "$dir/$name.desktop" "$dir/${name,,}.desktop"; do
            [[ -f "$file" ]] && { sed -n "s/^$key=//p" "$file" | head -n1; return; }
        done
    done
    return 1
}

desktop_icon() {
    desktop_value "$1" Icon
}

first_icon() {
    local candidate icon
    while IFS= read -r -d $'\x1f' candidate; do
        find_icon "$candidate" && return
        icon="$(desktop_icon "$candidate")" && find_icon "$icon" && return
    done <<< "$1"$'\x1f'
}
