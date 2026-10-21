#!/bin/bash
# Full-screen power menu on the focused monitor, with a Hyprland submap for its keys.
#   toggle           open it, or close it if it is open
#   close            close it and leave the submap
#   pick <action>    lock and suspend run at once; logout, reboot and shutdown ask for a second press
#   confirm          run the action waiting for a second press

MONITORS_FILE=~/.cache/eww/monitors.list

is_open() {
    eww active-windows 2>/dev/null | awk -F': ' '$2 == "powermenu"' | grep -q .
}

open() {
    local name width height left top index size=""
    read -r name width height left top < <(hyprctl -j monitors 2>/dev/null \
        | jq -r '.[] | select(.focused) | "\(.name) \((.width / .scale) | floor) \((.height / .scale) | floor) \(.reserved[0]) \(.reserved[1])"')
    # GDK index of the focused monitor, as launch.sh numbered them.
    index="$(grep -nxF "$name" "$MONITORS_FILE" 2>/dev/null | cut -d: -f1)"
    # The panel is sized for regular monitors and looks lost on an ultrawide.
    if [[ -n "$width" ]] && ~/.config/eww/scripts/ultrawide-layout.sh is-ultrawide "$width" "$height"; then
        size="large"
    fi

    ~/.config/eww/scripts/control-center.sh close
    eww update pm_confirm="" pm_info="$(jq -n -c \
        --arg host "$(hostname)" \
        --arg user "$USER" \
        --arg uptime "$(uptime -p | sed 's/^up //')" \
        --arg size "$size" \
        '{host: $host, user: $user, uptime: $uptime, size: $size}')"
    # Layer surfaces are placed inside the area the bar reserves, so shift back by it to cover the whole monitor.
    eww open powermenu --screen $(( ${index:-1} - 1 )) --anchor "top left" --pos="-${left:-0}x-${top:-0}"
    hyprctl dispatch 'hl.dsp.submap("power")' >/dev/null
}

close() {
    eww close powermenu 2>/dev/null
    eww update pm_confirm=""
    hyprctl dispatch 'hl.dsp.submap("reset")' >/dev/null
}

run() {
    close
    case "$1" in
        lock)     loginctl lock-session ;;
        suspend)  playerctl -a pause 2>/dev/null; systemctl suspend ;;
        logout)   hyprctl dispatch 'hl.dsp.exit()' >/dev/null || loginctl terminate-session "${XDG_SESSION_ID:-}" ;;
        reboot)   systemctl reboot ;;
        shutdown) systemctl poweroff ;;
    esac
}

case "$1" in
    toggle)
        if is_open; then close; else open; fi
        ;;
    close)
        close
        ;;
    pick)
        case "$2" in
            lock|suspend) run "$2" ;;
            logout|reboot|shutdown)
                if [[ "$(eww get pm_confirm)" == "$2" ]]; then
                    run "$2"
                else
                    eww update pm_confirm="$2"
                fi
                ;;
            *) echo "Unknown action: $2" >&2; exit 1 ;;
        esac
        ;;
    confirm)
        action="$(eww get pm_confirm)"
        [[ -n "$action" ]] && run "$action"
        ;;
    *)
        echo "Usage: $0 {toggle|close|pick <action>|confirm}" >&2
        exit 1
        ;;
esac
