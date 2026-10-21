#!/bin/bash
# Wallpaper page of the control center, on top of ~/.local/bin/wallpaper. wp_list holds the
# wallpapers in rows of two as {id, name, thumb, kind, current}; commands carry the id, never the
# file name.
#   refresh <index>        fill wp_list for monitor <index>, then again once new thumbnails are made
#   set <index> <id>       show a wallpaper on monitor <index>
#   all <index> <id>       show a wallpaper on every monitor
#   random <index>         show a random wallpaper on monitor <index>

WALLPAPER=~/.local/bin/wallpaper
MONITORS_FILE=~/.cache/eww/monitors.list

# Output name for a GDK index, as launch.sh numbered them.
output_name() {
    sed -n "$(($1 + 1))p" "$MONITORS_FILE" 2>/dev/null
}

file_for() {
    "$WALLPAPER" list 2>/dev/null | awk -F'\t' -v id="$1" '$1 == id {print $2; exit}'
}

list_json() {
    local current id file thumb
    current="$("$WALLPAPER" get "$(output_name "$1")" 2>/dev/null)"
    while IFS=$'\t' read -r id file thumb; do
        [[ -f "$thumb" ]] || thumb=""
        printf '%s\t%s\t%s\n' "$id" "$file" "$thumb"
    done < <("$WALLPAPER" list 2>/dev/null) | jq -R -s -c --arg current "$current" '
        split("\n") | map(select(. != "") | split("\t") | {
            id: .[0],
            name: (.[1] | split("/") | last | sub("\\.[^.]+$"; "")),
            thumb: .[2],
            kind: (.[1] | ascii_downcase | if test("\\.gif$") then "gif" elif test("\\.(mp4|webm|mkv|mov)$") then "video" else "image" end),
            current: (.[1] == $current)
        }) | [range(0; length; 2) as $i | .[$i:$i + 2]]' 2>/dev/null || echo "[]"
}

refresh() {
    local list
    list="$(list_json "$1")"
    eww update wp_list="$list"
    # New wallpapers have no thumbnail yet.
    if [[ "$list" == *'"thumb":""'* ]]; then
        "$WALLPAPER" thumbs
        eww update wp_list="$(list_json "$1")"
    fi
}

set_on() {
    local file
    file="$(file_for "$2")"
    [[ -n "$file" ]] || return 1
    "$WALLPAPER" set "$file" "$1"
}

case "$1" in
    refresh) refresh "${2:-0}" ;;
    set)
        set_on "$(output_name "${2:-0}")" "$3"
        refresh "${2:-0}"
        ;;
    all)
        set_on all "$3"
        refresh "${2:-0}"
        ;;
    random)
        "$WALLPAPER" random "$(output_name "${2:-0}")"
        refresh "${2:-0}"
        ;;
    *)
        echo "Usage: $0 {refresh <index>|set <index> <id>|all <index> <id>|random <index>}" >&2
        exit 1
        ;;
esac
