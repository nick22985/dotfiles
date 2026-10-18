#!/bin/bash

# Watchdog for the colorpicker popup: keeps running while the popup is open and
# closes it once we're no longer hovering. Catches missed/raced hoverlost events
# by also checking the cursor is still near the top of a monitor.

exec 9>"${XDG_RUNTIME_DIR:-/tmp}/eww-colorpicker-watch.lock"
flock -n 9 || exit 0

cursor_near_top() {
    local pos
    pos=$(hyprctl cursorpos 2>/dev/null | tr -d ',') || return 0
    [[ -z "$pos" ]] && return 0
    read -r cx cy <<<"$pos"
    hyprctl monitors -j 2>/dev/null | jq -e --argjson x "$cx" --argjson y "$cy" \
        'any(.[]; $x >= .x and $x < .x + .width / .scale and $y >= .y and $y < .y + 200)' \
        >/dev/null || return 1
}

close_all() {
    monitor_count=$(hyprctl -j monitors | jq '. | length')
    for ((i=0; i<monitor_count; i++)); do
        eww close colorpicker-popup${i} 2>/dev/null
    done
}

misses=0
while sleep 0.25; do
    if [ "$(eww get colorpicker_hover)" = "true" ] && cursor_near_top; then
        misses=0
    else
        ((misses++))
    fi
    ((misses >= 3)) && break
done

eww update colorpicker_hover=false
close_all
