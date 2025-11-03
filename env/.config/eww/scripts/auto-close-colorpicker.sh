#!/bin/bash

# Auto-close colorpicker popup after a delay if not hovering
sleep 3

# Check if still hovering
if [ "$(eww get colorpicker_hover)" = "false" ]; then
    # Close all colorpicker popups dynamically
    monitor_count=$(hyprctl -j monitors | jq '. | length')
    for ((i=0; i<monitor_count; i++)); do
        eww close colorpicker-popup${i} 2>/dev/null
    done
fi