#!/bin/bash

# Script to get brightness percentage with fallback
# Returns "disabled" if no proper backlight control is available

# Check if brightnessctl is installed
if ! command -v brightnessctl >/dev/null 2>&1; then
    echo "disabled"
    exit 0
fi

# Try brightnessctl with intel_backlight first
if brightnessctl -d intel_backlight info >/dev/null 2>&1; then
    max=$(brightnessctl -d intel_backlight max)
    # If max brightness is too low (like 1), it's probably not a real backlight
    if [ "$max" -gt 10 ]; then
        current=$(brightnessctl -d intel_backlight get)
        echo $((current * 100 / max))
        exit 0
    fi
fi

# Try /sys/class/backlight for real backlight devices
if [ -d /sys/class/backlight ]; then
    for backlight in /sys/class/backlight/*/; do
        if [ -f "${backlight}brightness" ] && [ -f "${backlight}max_brightness" ]; then
            max=$(cat "${backlight}max_brightness" 2>/dev/null || echo "1")
            # Only use if max brightness is reasonable (not just LED indicators)
            if [ "$max" -gt 10 ]; then
                current=$(cat "${backlight}brightness" 2>/dev/null || echo "$max")
                echo $((current * 100 / max))
                exit 0
            fi
        fi
    done
fi

# Check if any brightnessctl device has reasonable max brightness
for device in $(brightnessctl -l 2>/dev/null | grep "Device" | cut -d"'" -f2); do
    max=$(brightnessctl -d "$device" max 2>/dev/null || echo "1")
    if [ "$max" -gt 10 ]; then
        current=$(brightnessctl -d "$device" get 2>/dev/null || echo "$max")
        echo $((current * 100 / max))
        exit 0
    fi
done

# No proper backlight control found
echo "disabled"