#!/bin/bash

MONITORS_FILE=~/.cache/eww/monitors.list

active_monitor_name=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.monitor')

if [[ -z "$active_monitor_name" || "$active_monitor_name" == "null" ]]; then
    exit 0
fi

index=""
if [[ -r "$MONITORS_FILE" ]]; then
    i=0
    while IFS= read -r monitor; do
        [[ -z "$monitor" ]] && continue
        if [[ "$monitor" == "$active_monitor_name" ]]; then
            index=$i
            break
        fi
        ((i++))
    done < "$MONITORS_FILE"
fi

if [[ -z "$index" ]]; then
    index=$(hyprctl -j monitors 2>/dev/null \
        | jq -r --arg name "$active_monitor_name" \
            'sort_by(.id) | map(.name) | index($name) // empty')
fi

if [[ -z "$index" ]]; then
    exit 0
fi

eww update colorpicker_hover=true
eww open "colorpicker-popup${index}" 2>/dev/null

~/.config/eww/scripts/auto-close-colorpicker.sh &
