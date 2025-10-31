#!/bin/bash
# Network speed monitoring script for eww

# Get the primary network interface
INTERFACE=$(ip route | grep '^default' | awk '{print $5}' | head -1)

if [[ -z "$INTERFACE" ]]; then
    echo "No connection"
    exit 0
fi

# File to store previous values
CACHE_FILE="/tmp/eww-network-${INTERFACE}"

# Get current bytes
RX_BYTES=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes 2>/dev/null || echo 0)
TX_BYTES=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes 2>/dev/null || echo 0)

# Get current time
CURRENT_TIME=$(date +%s)

# Read previous values
if [[ -f "$CACHE_FILE" ]]; then
    read PREV_TIME PREV_RX PREV_TX < "$CACHE_FILE"
else
    PREV_TIME=$CURRENT_TIME
    PREV_RX=$RX_BYTES
    PREV_TX=$TX_BYTES
fi

# Calculate time difference
TIME_DIFF=$((CURRENT_TIME - PREV_TIME))

if [[ $TIME_DIFF -gt 0 ]]; then
    # Calculate speeds in bytes per second
    RX_SPEED=$(( (RX_BYTES - PREV_RX) / TIME_DIFF ))
    TX_SPEED=$(( (TX_BYTES - PREV_TX) / TIME_DIFF ))
    
    # Convert to human readable format
    format_speed() {
        local speed=$1
        if [[ $speed -gt 1048576 ]]; then
            echo "$(( speed / 1048576 )) MB/s"
        elif [[ $speed -gt 1024 ]]; then
            echo "$(( speed / 1024 )) KB/s"
        else
            echo "${speed} B/s"
        fi
    }
    
    DOWN_SPEED=$(format_speed $RX_SPEED)
    UP_SPEED=$(format_speed $TX_SPEED)
    
    echo "↓ $DOWN_SPEED ↑ $UP_SPEED"
else
    echo "Calculating..."
fi

# Save current values
echo "$CURRENT_TIME $RX_BYTES $TX_BYTES" > "$CACHE_FILE"