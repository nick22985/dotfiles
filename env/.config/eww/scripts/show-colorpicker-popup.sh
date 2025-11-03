#!/bin/bash

# Get the focused monitor ID from hyprland
monitor_id=$(hyprctl activeworkspace -j | jq -r '.monitorID')

# Open popup on the focused monitor
eww update colorpicker_hover=true
eww open colorpicker-popup$monitor_id 2>/dev/null

# Start auto-close timer in background
~/.config/eww/scripts/auto-close-colorpicker.sh &