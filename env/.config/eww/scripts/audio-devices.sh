#!/bin/bash
# Audio page of the control center.
#   list               {"sinks": [...], "sources": [...]} with {"id", "name", "default"}
#   set-sink <id>      make an output the default
#   set-source <id>    make an input the default

# shellcheck source=lib/icons.sh
source "$(dirname "$0")/lib/icons.sh"

devices() {
    local kind="$1" default="$2"
    pactl -f json list "$kind" 2>/dev/null | jq -c --arg default "$default" '
        map(select((.name | endswith(".monitor") | not) and ((.monitor_of_sink // "n/a") == "n/a"))
            | {id: .index, name: (.description // .name), default: (.name == $default)})'
}

apps() {
    local icons app
    pactl -f json list sink-inputs 2>/dev/null | jq -r '
        .[] | .properties as $p
        | {id: (.index | tostring),
           name: ($p["application.name"] // $p["application.process.binary"] // $p["media.name"] // "Unknown"),
           media: ($p["media.name"] // ""),
           muted: .mute} as $app
        | [$p["application.icon_name"], $p["pipewire.access.portal.app_id"], $p["application.process.binary"],
           ($p["application.name"] // "" | ascii_downcase | gsub(" "; "-"))]
        | map(select(. != null and . != "")) | join("\u001f") + "\u001e" + ($app | tojson)' \
    | while IFS=$'\x1e' read -r icons app; do
        jq -c --arg icon "$(first_icon "$icons")" '.icon = $icon' <<< "$app"
    done | jq -s -c 'sort_by(.name | ascii_downcase)'
}

volumes() {
    pactl -f json list sink-inputs 2>/dev/null | jq -c '
        map({key: (.index | tostring), value: ([.volume[].value_percent | rtrimstr("%") | tonumber] | max)})
        | from_entries'
}

list() {
    local sinks sources apps
    sinks="$(devices sinks "$(pactl get-default-sink 2>/dev/null)")"
    sources="$(devices sources "$(pactl get-default-source 2>/dev/null)")"
    apps="$(apps)"
    jq -n -c --argjson sinks "${sinks:-[]}" --argjson sources "${sources:-[]}" --argjson apps "${apps:-[]}" \
        '{sinks: $sinks, sources: $sources, apps: $apps}'
}

valid_id() {
    [[ "$1" =~ ^[0-9]+$ ]] || { echo "Invalid device id: $1" >&2; exit 1; }
}

case "$1" in
    list)
        list
        ;;
    volumes)
        volumes
        ;;
    set-sink|set-source)
        valid_id "$2"
        pactl "set-default-${1#set-}" "$2"
        eww update audio_devices="$(list)"
        ;;
    mute-app)
        valid_id "$2"
        pactl set-sink-input-mute "$2" toggle
        eww update audio_devices="$(list)"
        ;;
    *)
        echo "Usage: $0 {list|volumes|set-sink <id>|set-source <id>|mute-app <id>}" >&2
        exit 1
        ;;
esac
