#!/bin/bash

# Add small delay to allow mouse to move between colorpicker and popup
sleep 0.1

# Check if we're still hovering (another hover event might have set it back to true)
if [ "$(eww get colorpicker_hover)" = "false" ]; then
    # Close all colorpicker popups dynamically based on current monitors
    monitor_count=$(hyprctl -j monitors | jq '. | length')
    for ((i=0; i<monitor_count; i++)); do
        eww close colorpicker-popup${i} 2>/dev/null
    done
fi