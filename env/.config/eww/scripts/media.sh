#!/bin/bash
# Now playing, for the control center's media card.
#   listen              {"present", "player", "status", "title", "artist", "art"} as JSON on every change,
#                       plus a notification whenever a new track starts playing
#   prev|toggle|next    control the player shown on the card

ART_DIR=~/.cache/eww/media-art
SEP=$'\x1f'

# Local copy of a track's cover (mpris:artUrl is a file:// or http(s) URL), or "" if there is none.
art_path() {
    local url="$1" file path
    [[ -n "$url" ]] || return
    mkdir -p "$ART_DIR"
    file="$ART_DIR/$(printf '%s' "$url" | md5sum | cut -d' ' -f1)"
    if [[ ! -s "$file" ]]; then
        case "$url" in
            file://*)
                path="${url#file://}"
                cp -- "$(printf '%b' "${path//%/\\x}")" "$file" 2>/dev/null
                ;;
            http://* | https://*)
                curl -fsSL --max-time 5 -o "$file.part" -- "$url" 2>/dev/null && mv -f -- "$file.part" "$file"
                rm -f -- "$file.part"
                ;;
        esac
    fi
    [[ -s "$file" ]] && printf '%s' "$file"
}

# Each one replaces the last, so skipping through tracks leaves a single notification.
notify_track() {
    notify-send -a "Now playing" -u low -t 4000 -i "${3:-audio-x-generic}" \
        -h string:x-canonical-private-synchronous:now-playing -- "$1" "$2"
}

listen() {
    local player status title artist url art track notified="" first=true
    find "$ART_DIR" -type f -mtime +7 -delete 2>/dev/null
    # An empty line means the last player went away.
    playerctl --follow metadata \
        --format "{{playerName}}${SEP}{{status}}${SEP}{{title}}${SEP}{{artist}}${SEP}{{mpris:artUrl}}" 2>/dev/null \
        | while IFS="$SEP" read -r player status title artist url; do
            art="$(art_path "$url")"
            jq -n -c --arg player "$player" --arg status "$status" --arg title "$title" \
                --arg artist "$artist" --arg art "$art" \
                '{present: ($player != ""), player: $player, status: $status, title: $title, artist: $artist, art: $art}'
            # Not for whatever was already playing when eww started, nor for pausing and resuming.
            track="$player$SEP$title$SEP$artist"
            if [[ "$status" == "Playing" && -n "$title" && "$track" != "$notified" ]]; then
                [[ "$first" == true ]] || notify_track "$title" "${artist:-$player}" "$art"
                notified="$track"
            fi
            first=false
        done
}

case "$1" in
    listen) listen ;;
    prev) playerctl previous ;;
    toggle) playerctl play-pause ;;
    next) playerctl next ;;
    *)
        echo "Usage: $0 {listen|prev|toggle|next}" >&2
        exit 1
        ;;
esac
