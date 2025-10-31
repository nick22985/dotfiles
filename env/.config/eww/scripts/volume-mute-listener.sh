#!/bin/bash
# Real-time volume mute listener for eww

get_mute() {
    pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | grep -q 'yes' && echo 'true' || echo 'false'
}

# Output initial mute state
get_mute

# Listen to pulseaudio events
pactl subscribe | grep --line-buffered "Event 'change' on sink" | while read -r line; do
    get_mute
done