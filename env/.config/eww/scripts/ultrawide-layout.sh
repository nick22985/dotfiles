#!/bin/bash
# Bar layout for ultrawide monitors: edges | band | thirds.
#   get              print the saved layout (default band)
#   set <layout>     save it, push it to eww and move an open control center
#   is-ultrawide W H exit 0 when W:H is wider than 2.4:1
#   margin <output> <width>
#                    print the right margin that puts a panel of that width under the status pill

STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/eww/ultrawide-layout"
DEFAULT_LAYOUT="band"
BAND_WIDTH=2560
EDGE_GAP=20

valid_layout() {
    [[ "$1" == "edges" || "$1" == "band" || "$1" == "thirds" ]]
}

get_layout() {
    local layout
    layout=$(cat "$STATE_FILE" 2>/dev/null)
    valid_layout "$layout" && echo "$layout" || echo "$DEFAULT_LAYOUT"
}

is_ultrawide() {
    (( $1 > 0 && $2 > 0 && $1 * 10 / $2 >= 24 ))
}

# In logical pixels, so scaled monitors line up with the bar.
panel_margin() {
    local size width height
    size=$(hyprctl -j monitors 2>/dev/null \
        | jq -r --arg n "$1" '.[] | select(.name == $n) | "\((.width / .scale) | floor) \((.height / .scale) | floor)"')
    read -r width height <<< "$size"

    if [[ -z "$width" ]] || ! is_ultrawide "$width" "$height"; then
        echo "$EDGE_GAP"
        return
    fi
    case "$(get_layout)" in
        band)   echo $(( (width - BAND_WIDTH) / 2 + EDGE_GAP )) ;;
        thirds) echo $(( width / 6 - $2 / 2 )) ;;
        *)      echo "$EDGE_GAP" ;;
    esac
}

case "$1" in
    get)
        get_layout
        ;;
    set)
        if ! valid_layout "$2"; then
            echo "Usage: $0 set {edges|band|thirds}" >&2
            exit 1
        fi
        mkdir -p "$(dirname "$STATE_FILE")"
        echo "$2" > "$STATE_FILE"
        eww update uw_layout="$2"

        # The control center is positioned at open time, so reopen it under the moved pill.
        open_on=$(eww get cc_open 2>/dev/null)
        if [[ -n "$open_on" ]]; then
            ~/.config/eww/scripts/control-center.sh close
            ~/.config/eww/scripts/control-center.sh toggle "$open_on"
        fi
        ;;
    is-ultrawide)
        is_ultrawide "${2:-0}" "${3:-0}"
        ;;
    margin)
        panel_margin "$2" "${3:-0}"
        ;;
    *)
        echo "Usage: $0 {get|set <edges|band|thirds>|is-ultrawide <width> <height>|margin <output> <width>}" >&2
        exit 1
        ;;
esac
