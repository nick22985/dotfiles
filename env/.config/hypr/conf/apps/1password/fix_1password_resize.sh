5#!/bin/bash

# Wait for the window to finish its auto-resizing
sleep 0.3

# Find the window with class "1Password" and title "1Password"
winaddr=$(hyprctl clients -j | jq -r '.[] | select(.class=="1Password" and .title=="1Password") | .address')

# If found, resize it
if [[ -n "$winaddr" ]]; then
    hyprctl dispatch resizewindowpixel "$winaddr" 800 500
fi

