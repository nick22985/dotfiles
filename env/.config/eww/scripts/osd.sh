#!/bin/bash
# Media-key popup: changes a level, then shows it on the focused monitor for a moment.
#   volume up|down|mute   output volume
#   mic mute              microphone mute
#   brightness up|down    screen backlight

MONITORS_FILE=~/.cache/eww/monitors.list
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/eww-osd"
SHOW_SECONDS=1.5

# "<percent> <muted>" for a wpctl device.
wpctl_level() {
    wpctl get-volume "$1" 2>/dev/null \
        | awk '{ printf "%d %s\n", $2 * 100 + 0.5, ($3 == "[MUTED]" ? "true" : "false") }'
}

brightness_level() {
    brightnessctl -m 2>/dev/null | awk -F, '{ sub(/%/, "", $4); print $4 + 0, "false" }'
}

# show <kind> <percent> <muted>
show() {
    local name index screen token open_screen current
    name="$(hyprctl -j monitors 2>/dev/null | jq -r '.[] | select(.focused) | .name')"
    # GDK index of the focused monitor, as launch.sh numbered them.
    index="$(grep -nxF "$name" "$MONITORS_FILE" 2>/dev/null | cut -d: -f1)"
    screen=$(( ${index:-1} - 1 ))

    # Each press replaces the token, so only the last press's timer closes the popup.
    token="$(date +%s%N)"
    read -r _ open_screen 2>/dev/null < "$STATE_FILE"
    printf '%s %s\n' "$token" "$screen" > "$STATE_FILE"

    eww update osd="$(jq -n -c --arg kind "$1" --argjson value "${2:-0}" --argjson muted "${3:-false}" \
        '{kind: $kind, value: $value, muted: $muted}')"
    # Reopening an open window makes it flicker, so only open it when it is shut or on another monitor.
    if [[ "$open_screen" != "$screen" ]] || ! eww active-windows 2>/dev/null | grep -q ': osd$'; then
        eww open osd --screen "$screen"
    fi

    (
        sleep "$SHOW_SECONDS"
        read -r current _ < "$STATE_FILE"
        [[ "$current" == "$token" ]] && eww close osd
    ) >/dev/null 2>&1 &
}

case "$1 $2" in
    "volume up")       wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ ;;
    "volume down")     wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
    "volume mute")     wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
    "mic mute")        wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle ;;
    "brightness up")   brightnessctl -q s 10%+ ;;
    "brightness down") brightnessctl -q s 10%- ;;
    *)
        echo "Usage: $0 {volume up|down|mute|mic mute|brightness up|down}" >&2
        exit 1
        ;;
esac

case "$1" in
    volume)     read -r value muted < <(wpctl_level @DEFAULT_AUDIO_SINK@) ;;
    mic)        read -r value muted < <(wpctl_level @DEFAULT_AUDIO_SOURCE@) ;;
    brightness) read -r value muted < <(brightness_level) ;;
esac
show "$1" "$value" "$muted"
