#!/bin/bash
# Open the colorpicker popup on the currently focused monitor.
#
# eww binds windows by GDK monitor index, which corresponds to Hyprland
# monitors sorted by their `.id` field. We must map the active monitor to
# that same sorted position so the popup window name matches the bar we
# generated in launch.sh.

active_monitor_name=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.monitor')

if [[ -z "$active_monitor_name" || "$active_monitor_name" == "null" ]]; then
    exit 0
fi

index=$(hyprctl -j monitors 2>/dev/null \
    | jq -r --arg name "$active_monitor_name" \
        'sort_by(.id) | map(.name) | index($name) // empty')

if [[ -z "$index" ]]; then
    exit 0
fi

eww update colorpicker_hover=true
eww open "colorpicker-popup${index}" 2>/dev/null

~/.config/eww/scripts/auto-close-colorpicker.sh &
