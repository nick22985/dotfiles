#!/bin/bash
# Keeps swaync's popups on the focused monitor. Left to itself swaync opens them wherever Hyprland
# puts them, which isn't always the focused monitor, so this names it. Popups already showing move
# along with it.
#   apply    move the popups to the focused monitor
#   listen   apply whenever the focused monitor or the monitor set changes
#
# swaync forgets the monitor when it restarts, so its systemd drop-in
# (~/.config/systemd/user/swaync.service.d/monitor.conf) applies again once it is up.

position_css="$HOME/.config/swaync/position.css"
ultrawide_ratio=2.5
middle_right=0.75

focused_output() {
    hyprctl -j monitors 2>/dev/null | jq -r --argjson ratio "$ultrawide_ratio" --argjson right "$middle_right" '
        .[] | select(.focused)
        | [.name, (if .width / .height >= $ratio then (.width / .scale * (1 - $right) | floor) else 0 end)]
        | @tsv' 2>/dev/null | head -n1
}

apply_offset() {
    local css=".floating-notifications.background > scrolledwindow { margin-right: ${1}px; }"
    [[ "$(cat "$position_css" 2>/dev/null)" == "$css" ]] && return 0
    printf '%s\n' "$css" > "$position_css" && swaync-client --reload-css >/dev/null 2>&1
}

apply() {
    local output offset
    IFS=$'\t' read -r output offset < <(focused_output)
    [[ -n "$output" ]] || return 0
    apply_offset "${offset:-0}"
    swaync-client --change-noti-monitor "$output" >/dev/null 2>&1
}

listen() {
    local socket="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" line
    [[ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]] || { echo "Not running under Hyprland" >&2; exit 1; }
    apply
    while true; do
        socat -u "UNIX-CONNECT:$socket" - 2>/dev/null | while read -r line; do
            case "$line" in
                focusedmon\>\>*|monitoradded\>\>*|monitorremoved\>\>*) apply ;;
            esac
        done
        sleep 2
    done
}

case "$1" in
    apply) apply ;;
    listen) listen ;;
    *)
        echo "Usage: $0 {apply|listen}" >&2
        exit 1
        ;;
esac
