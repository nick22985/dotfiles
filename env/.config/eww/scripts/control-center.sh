#!/bin/bash
# Opens/closes the control center dropdown under the status pill.
#   toggle <index>   open on monitor <index>, or close if already open there
#   close            close it on every monitor
#   close-later      close after a short delay unless the pointer came back
#   page <n>         show a page (0 main, 1 Wi-Fi, 2 Bluetooth, 3 clipboard, 4 audio, 5 wallpaper, 6 notifications) and refresh it
#   offset <index>   print the right margin that puts a panel under the pill

MONITORS_FILE=~/.cache/eww/monitors.list
PANEL_WIDTH=330
BAND_WIDTH=2560
EDGE_GAP=20

close_all() {
    local w
    for w in $(eww active-windows 2>/dev/null | awk -F': ' '$2 ~ /^control-center[0-9]+$/ {print $2}'); do
        eww close "$w" 2>/dev/null
    done
    eww update cc_open="" cc_page=0
}

# Pages poll only while shown, so fetch fresh data the moment one opens.
show_page() {
    local scripts=~/.config/eww/scripts
    eww update cc_page="$1"
    case "$1" in
        1) eww update wifi_enabled="$(nmcli radio wifi 2>/dev/null)"; "$scripts/wifi.sh" rescan ;;
        2) eww update bt_devices="$("$scripts/bluetooth.sh" list)" ;;
        3) eww update clip_entries="$("$scripts/clipboard.sh" list)" ;;
        4) eww update audio_devices="$("$scripts/audio-devices.sh" list)" ;;
        5) "$scripts/wallpaper.sh" refresh "$(eww get cc_open 2>/dev/null)" ;;
    esac
}

# Right margin that puts the panel under the pill for the monitor's layout.
panel_offset() {
    local name size width height scale layout
    name=$(sed -n "$(($1 + 1))p" "$MONITORS_FILE" 2>/dev/null)
    size=$(hyprctl -j monitors 2>/dev/null \
        | jq -r --arg n "$name" '.[] | select(.name == $n) | "\(.width) \(.height) \(.scale)"')
    read -r width height scale <<< "$size"

    if [[ -z "$width" ]]; then
        echo "$EDGE_GAP"
        return
    fi
    width=$(awk -v w="$width" -v s="$scale" 'BEGIN { printf "%d", w / s }')
    height=$(awk -v h="$height" -v s="$scale" 'BEGIN { printf "%d", h / s }')

    if ! ~/.config/eww/scripts/ultrawide-layout.sh is-ultrawide "$width" "$height"; then
        echo "$EDGE_GAP"
        return
    fi

    layout=$(~/.config/eww/scripts/ultrawide-layout.sh get)
    case "$layout" in
        band)   echo $(( (width - BAND_WIDTH) / 2 + EDGE_GAP )) ;;
        thirds) echo $(( width / 6 - PANEL_WIDTH / 2 )) ;;
        *)      echo "$EDGE_GAP" ;;
    esac
}

case "$1" in
    toggle)
        index="${2:-0}"
        if [[ "$(eww get cc_open 2>/dev/null)" == "$index" ]]; then
            close_all
            exit 0
        fi
        close_all
        ~/.config/eww/scripts/calendar.sh close
        x=$(panel_offset "$index")
        eww open "control-center${index}" --anchor "top right" --pos "${x}x6"
        eww update cc_open="$index" cc_hover=false cc_page=0
        ;;
    close)
        close_all
        ;;
    page)
        show_page "${2:-0}"
        ;;
    offset)
        panel_offset "${2:-0}"
        ;;
    close-later)
        sleep 0.8
        [[ "$(eww get cc_hover 2>/dev/null)" == "true" ]] || close_all
        ;;
    *)
        echo "Usage: $0 {toggle <index>|close|close-later|page <n>|offset <index>}" >&2
        exit 1
        ;;
esac
