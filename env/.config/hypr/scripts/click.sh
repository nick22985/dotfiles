#!/bin/bash

# Map human-readable keys to ydotool keycodes
get_keycode() {
    local key="$1"
    case "$key" in
        a) echo 30 ;; b) echo 48 ;; c) echo 46 ;; d) echo 32 ;;
        e) echo 18 ;; f) echo 33 ;; g) echo 34 ;; h) echo 35 ;;
        i) echo 23 ;; j) echo 36 ;; k) echo 37 ;; l) echo 38 ;;
        m) echo 50 ;; n) echo 49 ;; o) echo 24 ;; p) echo 25 ;;
        q) echo 16 ;; r) echo 19 ;; s) echo 31 ;; t) echo 20 ;;
        u) echo 22 ;; v) echo 47 ;; w) echo 17 ;; x) echo 45 ;;
        y) echo 21 ;; z) echo 44 ;;
        space) echo 57 ;; enter) echo 28 ;;
        shift) echo 42 ;; ctrl) echo 29 ;; alt) echo 56 ;;
        f1) echo 59 ;; f2) echo 60 ;; f3) echo 61 ;; f4) echo 62 ;;
        mouse1) echo 0xC0 ;; mouse2) echo 0xC1 ;;
        *) echo "INVALID" ;;
    esac
}

# Convert ms to fractional seconds
ms_to_sec() {
    awk "BEGIN { print $1 / 1000 }"
}

# Show usage
show_help() {
    echo "Usage: $0 <macro.txt> [-r|--run]"
    echo "Options:"
    echo "  -r, --run    Execute the compiled macro after generating it"
    exit 1
}

# Parse args
RUN_AFTER=false
FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--run) RUN_AFTER=true; shift ;;
        -*) echo "Unknown option: $1"; show_help ;;
        *) FILE="$1"; shift ;;
    esac
done

if [[ -z "$FILE" || ! -f "$FILE" ]]; then
    echo "❌ Error: Provide a valid macro script file."
    show_help
fi

# Load script into memory
mapfile -t lines < "$FILE"

# Setup
compiled_cmd=""
YDO="YDOTOOL_SOCKET=\"$HOME/.ydotool_socket\" ydotool"
click_count=0
last_click=""
pending_click_delay=""

# Helper: flush pending clicks with delay AFTER
flush_clicks() {
    if [[ "$click_count" -gt 0 ]]; then
        compiled_cmd+="$YDO click --repeat $click_count $last_click; "
        click_count=0
        last_click=""
        if [[ "$pending_click_delay" =~ ^[0-9]+(\.[0-9]+)?$ && "$pending_click_delay" != "0" ]]; then
            compiled_cmd+="sleep $(ms_to_sec "$pending_click_delay"); "
        fi
        pending_click_delay=""
    fi
}

# Process each line
for line in "${lines[@]}"; do
    [[ -z "$line" || "$line" == \#* ]] && continue

    # Handle "type" lines
    if [[ "$line" == type* ]]; then
        rest="${line#type }"
        flush_clicks
        compiled_cmd+="$YDO type '$rest'; "
        continue
    fi

    # Parse: key hold(ms) delay(ms)
    read -r key hold delay <<< "$line"
    keycode=$(get_keycode "$key")

    if [[ "$keycode" == "INVALID" ]]; then
        echo "❌ Invalid key: $key"
        exit 1
    fi

    # Handle mouse clicks
    if [[ "$key" == mouse* ]]; then
        if [[ "$keycode" == "$last_click" ]]; then
            ((click_count++))
        else
            flush_clicks
            last_click="$keycode"
            click_count=1
        fi

        # Save delay to apply after flush when next line processed or at end
        pending_click_delay="$delay"
        continue
    fi

    # Flush clicks before processing key
    flush_clicks

    # === KEY PRESS LOGIC WITH HOLD ===
    if [[ "$hold" =~ ^[0-9]+$ && "$hold" -gt 0 ]]; then
        compiled_cmd+="$YDO key ${keycode}:1; "
        compiled_cmd+="sleep $(ms_to_sec "$hold"); "
        compiled_cmd+="$YDO key ${keycode}:0; "
    else
        compiled_cmd+="$YDO key ${keycode}:1 ${keycode}:0; "
    fi

    # Delay after release
    if [[ "$delay" =~ ^[0-9]+(\.[0-9]+)?$ && "$delay" != "0" ]]; then
        compiled_cmd+="sleep $(ms_to_sec "$delay"); "
    fi
done

# Final flush any leftover clicks
flush_clicks

# Output compiled command
echo
echo "🔧 Compiled ydotool command:"
echo "-----------------------------------------"
echo "$compiled_cmd"
echo "-----------------------------------------"

# Execute if requested
if [ "$RUN_AFTER" = true ]; then
    echo "🚀 Running compiled macro..."
    eval "$compiled_cmd"
fi

