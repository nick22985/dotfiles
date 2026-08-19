#!/bin/bash
# Monitor change watcher for eww.
#
# Hyprland emits monitor events in bursts (especially when a dock is plugged
# in and several displays appear at once). Firing launch.sh on every event
# races and causes duplicate bars on the same screen. We debounce: after the
# first event, drain the event stream until it has been quiet for
# DEBOUNCE_SECS, then do a single signature check and restart.

DEBOUNCE_SECS=1.5
RECONCILE_SECS=30
RECONCILE_STRIKES=2
RECONCILE_COOLDOWN_SECS=300
RECONCILE_MAX_RESTARTS=3

SIGNATURE_FILE=~/.cache/eww/monitors.signature
MONITORS_FILE=~/.cache/eww/monitors.list

get_monitor_signature() {
    hyprctl -j monitors 2>/dev/null | jq -r 'sort_by(.name) | map(.name) | join(",")'
}

expected_bar_count() {
    local count
    count=$(grep -c . "$MONITORS_FILE" 2>/dev/null)
    echo "${count:-0}"
}

open_bar_count() {
    eww active-windows 2>/dev/null \
        | awk -F': ' 'NF>=2 && $2 ~ /^topbar[0-9]+$/ {c++} END {print c+0}'
}

restart_eww() {
    echo "$(date): $1"
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
        restart_eww "Monitor configuration changed: $current_signature -> $new_signature, restarting eww..."
        current_signature="$new_signature"
    else
        echo "$(date): Monitor event burst settled with no change ($current_signature)"
    fi
}

reconcile_loop() {
    local signature expected open reason
    local strikes=0 restarts=0 last_layout=""
    local elapsed_since_restart=$RECONCILE_COOLDOWN_SECS

    while true; do
        sleep "$RECONCILE_SECS"
        ((elapsed_since_restart += RECONCILE_SECS))

        signature=$(get_monitor_signature)
        [[ -z "$signature" ]] && continue

        if [[ "$signature" != "$last_layout" ]]; then
            last_layout="$signature"
            restarts=0
            strikes=0
        fi

        reason=""
        if [[ "$signature" != "$(cat "$SIGNATURE_FILE" 2>/dev/null)" ]]; then
            reason="layout drifted from launched signature ($signature)"
        else
            expected=$(expected_bar_count)
            open=$(open_bar_count)
            if ((expected > 0)) && ((open != expected)); then
                reason="$open/$expected topbars open"
            fi
        fi

        if [[ -z "$reason" ]]; then
            strikes=0
            restarts=0
            continue
        fi

        if ((restarts >= RECONCILE_MAX_RESTARTS)); then
            continue
        fi

        ((strikes++))
        if ((strikes < RECONCILE_STRIKES)); then
            echo "$(date): Reconcile: $reason (strike $strikes/$RECONCILE_STRIKES)"
            continue
        fi
        if ((elapsed_since_restart < RECONCILE_COOLDOWN_SECS)); then
            echo "$(date): Reconcile: $reason, but in cooldown; not restarting."
            continue
        fi

        strikes=0
        elapsed_since_restart=0
        ((restarts++))
        restart_eww "Reconcile: $reason, restarting eww (attempt $restarts/$RECONCILE_MAX_RESTARTS)..."
        if ((restarts >= RECONCILE_MAX_RESTARTS)); then
            echo "$(date): Reconcile: giving up on layout $signature after" \
                 "$RECONCILE_MAX_RESTARTS restarts; will retry when monitors change."
        fi
    done
}

current_signature=$(cat "$SIGNATURE_FILE" 2>/dev/null)
[[ -z "$current_signature" ]] && current_signature=$(get_monitor_signature)
echo "$(date): Starting monitor watcher. Launched layout: $current_signature"

startup_signature=$(get_monitor_signature)
if [[ -n "$startup_signature" && "$startup_signature" != "$current_signature" ]]; then
    current_signature="$startup_signature"
    restart_eww "Monitors changed before watcher started, restarting eww..."
fi

reconcile_loop &

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
            if [[ -n "$new_signature" && "$new_signature" != "$current_signature" ]]; then
                current_signature="$new_signature"
                restart_eww "Monitor configuration changed: $new_signature, restarting eww..."
            fi
        done
    fi
else
    echo "$(date): Not in Hyprland, using polling mode..."
    while true; do
        sleep 5
        new_signature=$(get_monitor_signature)
        if [[ -n "$new_signature" && "$new_signature" != "$current_signature" ]]; then
            current_signature="$new_signature"
            restart_eww "Monitor configuration changed: $new_signature, restarting eww..."
        fi
    done
fi
