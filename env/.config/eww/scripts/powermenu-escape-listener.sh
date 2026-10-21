#!/bin/bash

# Listen for Escape key to close power menu
# This script runs in background when power menu is open

trap 'exit 0' TERM

# Use different methods to detect Escape key
if command -v xev >/dev/null 2>&1; then
    # X11 method
    xev -root -event keypress | while read line; do
        if echo "$line" | grep -q "keycode 9"; then  # Escape key
            eww close powermenu-popup 2>/dev/null
            exit 0
        fi
    done
elif command -v wev >/dev/null 2>&1; then
    # Wayland method
    wev | while read line; do
        if echo "$line" | grep -q "KEY_ESC"; then
            eww close powermenu-popup 2>/dev/null
            exit 0
        fi
    done
else
    # Fallback: just wait and check if window still exists
    for i in {1..30}; do
        sleep 1
        if ! eww active-windows | grep -q "powermenu-popup"; then
            exit 0
        fi
    done
fi