#!/bin/bash

# Power menu key handler
# Handles keyboard shortcuts for the power menu

key_event="$1"

# Parse the key from the event
# EWW passes key events as JSON-like strings
if [[ "$key_event" == *"Escape"* ]]; then
    eww close powermenu-popup
elif [[ "$key_event" == *"q"* ]]; then
    eww close powermenu-popup
fi