#!/bin/bash
# Monitor change watcher for eww.
#
# Hyprland emits monitor events in bursts (especially when a dock is plugged
# in and several displays appear at once). Firing launch.sh on every event
# races and causes duplicate bars on the same screen. We debounce: after the
# first event, drain the event stream until it has been quiet for
# DEBOUNCE_SECS, then do a single signature check and restart.

DEBOUNCE_SECS=1.5

get_monitor_signature() {
    hyprctl -j monitors 2>/dev/null | jq -r 'sort_by(.name) | map(.name) | join(",")'
}

restart_eww() {
    echo "$(date): Monitor change detected, restarting eww..."
    # launch.sh serializes itself via flock, so even if this function is
    # somehow re-entered we will not get overlapping launches.
    ~/.config/eww/launch.sh >> ~/.cache/eww/monitor-watcher.log 2>&1 &
}

# Called from inside the `while read` loop over the event pipe. Consumes any
# further events from stdin until the stream has been quiet for DEBOUNCE_SECS,
# then decides whether to restart eww.
handle_event_burst() {
    local extra
    while read -r -t "$DEBOUNCE_SECS" extra; do
        :  # drop the event; we only care that activity is still happening
    done

    local new_signature
    new_signature=$(get_monitor_signature)
    if [[ "$new_signature" != "$current_signature" ]]; then
        echo "$(date): Monitor configuration changed: $current_signature -> $new_signature"
        current_signature="$new_signature"
        restart_eww
    else
        echo "$(date): Monitor event burst settled with no change ($current_signature)"
    fi
}

current_signature=$(get_monitor_signature)
echo "$(date): Starting monitor watcher. Current monitors: $current_signature"

if [[ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]]; then
    SOCKET_PATH="/run/user/$(id -u)/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
    if [[ -S "$SOCKET_PATH" ]]; then
        echo "$(date): Listening for monitor events..."
        socat -u "UNIX-CONNECT:$SOCKET_PATH" - | while read -r line; do
            case "$line" in
                monitoradded\>\>*|monitorremoved\>\>*)
                    handle_event_burst
                    ;;
            esac
        done
    else
        echo "$(date): Hyprland socket not found, falling back to polling..."
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
