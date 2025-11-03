#!/bin/bash
# Monitor change watcher for eww
# This script watches for monitor connect/disconnect events and restarts eww

# Function to get current monitor setup
get_monitor_signature() {
    hyprctl -j monitors 2>/dev/null | jq -r 'sort_by(.name) | map(.name) | join(",")'
}

# Function to restart eww with new monitor setup
restart_eww() {
    echo "$(date): Monitor change detected, restarting eww..."
    ~/.config/eww/launch.sh &
}

# Get initial monitor signature
current_signature=$(get_monitor_signature)
echo "$(date): Starting monitor watcher. Current monitors: $current_signature"

# Watch for Hyprland monitor events
if [[ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]]; then
    SOCKET_PATH="/run/user/$(id -u)/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
    if [[ -S "$SOCKET_PATH" ]]; then
        echo "$(date): Listening for monitor events..."
        socat -u "UNIX-CONNECT:$SOCKET_PATH" - | while read -r line; do
            case "$line" in
                "monitoradded>>"*|"monitorremoved>>"*)
                    # Add a small delay to let the system settle
                    sleep 1
                    
                    new_signature=$(get_monitor_signature)
                    if [[ "$new_signature" != "$current_signature" ]]; then
                        echo "$(date): Monitor configuration changed: $current_signature -> $new_signature"
                        current_signature="$new_signature"
                        restart_eww
                    fi
                    ;;
            esac
        done
    else
        echo "$(date): Hyprland socket not found, falling back to polling..."
        # Fallback: poll for monitor changes
        while true; do
            sleep 2
            new_signature=$(get_monitor_signature)
            if [[ "$new_signature" != "$current_signature" ]]; then
                echo "$(date): Monitor configuration changed: $current_signature -> $new_signature"
                current_signature="$new_signature"
                restart_eww
            fi
        done
    fi
else
    echo "$(date): Not in Hyprland, using polling mode..."
    # Fallback for non-Hyprland environments
    while true; do
        sleep 5
        new_signature=$(get_monitor_signature)
        if [[ "$new_signature" != "$current_signature" ]]; then
            echo "$(date): Monitor configuration changed: $current_signature -> $new_signature"
            current_signature="$new_signature"
            restart_eww
        fi
    done
fi