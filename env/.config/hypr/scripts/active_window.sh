#!/bin/bash

# Create log directory if it doesn't exist
mkdir -p ~/.config/hypr/logs

# Append active window info to a file with a timestamp
echo "==== $(date) ====" >> ~/.config/hypr/logs/active_window_log.txt
hyprctl activewindow -j >> ~/.config/hypr/logs/active_window_log.txt
echo "" >> ~/.config/hypr/logs/active_window_log.txt

