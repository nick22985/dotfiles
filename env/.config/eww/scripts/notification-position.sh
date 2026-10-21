#!/bin/bash
# Keeps swaync's popups on the focused monitor. Left to itself swaync opens them wherever Hyprland
# puts them, which isn't always the focused monitor, so this names it. Popups already showing move
# along with it. On 4K-tall monitors (2000+ logical pixels high) the popups are drawn larger, since
# swaync's sizes are fixed pixels.
#   apply    move the popups to the focused monitor
#   listen   apply whenever the focused monitor or the monitor set changes
#
# swaync forgets the monitor when it restarts, so its systemd drop-in
# (~/.config/systemd/user/swaync.service.d/monitor.conf) applies again once it is up.

position_css="$HOME/.config/swaync/position.css"
ultrawide_ratio=2.5
middle_right=0.75
large_height=2000

focused_output() {
    hyprctl -j monitors 2>/dev/null | jq -r --argjson ratio "$ultrawide_ratio" --argjson right "$middle_right" '
        .[] | select(.focused)
        | [.name, (if .width / .height >= $ratio then (.width / .scale * (1 - $right) | floor) else 0 end), (.height / .scale | floor)]
        | @tsv' 2>/dev/null | head -n1
}

# style.css imports position.css before its own rules, so the large sizes repeat a class to win.
large_css() {
    local card=".floating-notifications.floating-notifications.background .notification-row .notification-background"
    cat <<EOF
$card { min-width: 470px; }
$card label { font-size: 17px; }
$card .summary { font-size: 17px; }
$card .time { font-size: 14px; }
$card .body { font-size: 16px; }
$card .notification-action button label { font-size: 16px; }
$card .image { -gtk-icon-size: 52px; min-width: 52px; min-height: 52px; }
EOF
}

apply_css() {
    local css
    css=".floating-notifications.background > scrolledwindow { margin-right: ${1}px; }"
    (( $2 >= large_height )) && css+=$'\n'"$(large_css)"
    [[ "$(cat "$position_css" 2>/dev/null)" == "$css" ]] && return 0
    printf '%s\n' "$css" > "$position_css" && swaync-client --reload-css >/dev/null 2>&1
}

apply() {
    local output offset height
    IFS=$'\t' read -r output offset height < <(focused_output)
    [[ -n "$output" ]] || return 0
    apply_css "${offset:-0}" "${height:-0}"
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
