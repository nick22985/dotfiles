#!/bin/bash
# Real-time microphone mute listener for eww

get_mic_mute() {
    pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null | grep -q 'yes' && echo 'true' || echo 'false'
}

# Output initial mute state
get_mic_mute

# Listen to pulseaudio events
pactl subscribe | grep --line-buffered "Event 'change' on source" | while read -r line; do
    get_mic_mute
done