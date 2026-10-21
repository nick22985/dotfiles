#!/bin/bash
# Audio page of the control center.
#   list               {"sinks": [...], "sources": [...]} with {"id", "name", "default"}
#   set-sink <id>      make an output the default
#   set-source <id>    make an input the default

devices() {
    local kind="$1" default="$2"
    pactl -f json list "$kind" 2>/dev/null | jq -c --arg default "$default" '
        map(select((.name | endswith(".monitor") | not) and ((.monitor_of_sink // "n/a") == "n/a"))
            | {id: .index, name: (.description // .name), default: (.name == $default)})'
}

list() {
    local sinks sources
    sinks="$(devices sinks "$(pactl get-default-sink 2>/dev/null)")"
    sources="$(devices sources "$(pactl get-default-source 2>/dev/null)")"
    jq -n -c --argjson sinks "${sinks:-[]}" --argjson sources "${sources:-[]}" '{sinks: $sinks, sources: $sources}'
}

valid_id() {
    [[ "$1" =~ ^[0-9]+$ ]] || { echo "Invalid device id: $1" >&2; exit 1; }
}

case "$1" in
    list)
        list
        ;;
    set-sink|set-source)
        valid_id "$2"
        pactl "set-default-${1#set-}" "$2"
        eww update audio_devices="$(list)"
        ;;
    *)
        echo "Usage: $0 {list|set-sink <id>|set-source <id>}" >&2
        exit 1
        ;;
esac
