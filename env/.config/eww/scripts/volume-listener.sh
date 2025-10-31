#!/bin/bash
# Real-time volume listener for eww

get_volume() {
    pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i ~ /%/) print $i}' | head -1 | sed 's/%//' || echo '50'
}

# Output initial volume
get_volume

# Listen to pulseaudio events
pactl subscribe | grep --line-buffered "Event 'change' on sink" | while read -r line; do
    get_volume
done