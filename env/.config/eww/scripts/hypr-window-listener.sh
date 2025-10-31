#!/bin/bash
# Hyprland window listener for eww
# This script listens to Hyprland events and outputs window class changes

# Function to get current active window
get_active_window() {
    hyprctl -j activewindow 2>/dev/null | jq -r '.class // ""' || echo ""
}

# Output initial window
get_active_window

# Check if we're in Hyprland and socket exists
if [[ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]]; then
    SOCKET_PATH="/run/user/$(id -u)/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
    if [[ -S "$SOCKET_PATH" ]]; then
        # Listen to Hyprland events
        socat -u "UNIX-CONNECT:$SOCKET_PATH" - | while read -r line; do
            # Check for window focus events
            case "$line" in
                "activewindow"*|"focusedmon"*|"workspace"*|"openwindow"*|"closewindow"*|"windowtitle"*)
                    get_active_window
                    ;;
            esac
        done
    else
        # Fallback to polling if socket doesn't exist
        while true; do
            get_active_window
            sleep 0.5
        done
    fi
else
    # Fallback to polling if not in Hyprland
    while true; do
        get_active_window
        sleep 1
    done
fi