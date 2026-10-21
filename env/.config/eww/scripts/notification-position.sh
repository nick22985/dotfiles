#!/bin/bash
# Keeps swaync's popups on the focused monitor. Left to itself swaync opens them wherever Hyprland
# puts them, which isn't always the focused monitor, so this names it. Popups already showing move
# along with it.
#   apply    move the popups to the focused monitor
#   listen   apply whenever the focused monitor or the monitor set changes
#
# swaync forgets the monitor when it restarts, so its systemd drop-in
# (~/.config/systemd/user/swaync.service.d/monitor.conf) applies again once it is up.

focused_output() {
    hyprctl -j monitors 2>/dev/null | jq -r '.[] | select(.focused) | .name' 2>/dev/null | head -n1
}

apply() {
    local output
    output=$(focused_output)
    [[ -n "$output" ]] && swaync-client --change-noti-monitor "$output" >/dev/null 2>&1
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
