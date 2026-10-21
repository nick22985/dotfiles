#!/bin/bash

# Power action script for eww power menu
# Usage: power-action.sh [shutdown|restart|sleep|logout|lock]

action="$1"

case "$action" in
    "shutdown")
        notify-send "Power Menu" "Shutting down..." -i system-shutdown
        sleep 1
        systemctl poweroff
        ;;
    "restart")
        notify-send "Power Menu" "Restarting..." -i system-reboot
        sleep 1
        systemctl reboot
        ;;
    "sleep")
        notify-send "Power Menu" "Going to sleep..." -i system-suspend
        sleep 1
        systemctl suspend
        ;;
    "logout")
        notify-send "Power Menu" "Logging out..." -i system-log-out
        sleep 1
        # For Hyprland
        if command -v hyprctl >/dev/null; then
            hyprctl dispatch 'hl.dsp.exit()'
        # For other window managers
        elif command -v loginctl >/dev/null; then
            loginctl terminate-user "$USER"
        else
            pkill -KILL -u "$USER"
        fi
        ;;
    "lock")
        notify-send "Power Menu" "Locking screen..." -i system-lock-screen
        # Try different lock commands
        if command -v hyprlock >/dev/null; then
            hyprlock
        elif command -v swaylock >/dev/null; then
            swaylock -f
        elif command -v i3lock >/dev/null; then
            i3lock -i ~/.config/wallpaper.png 2>/dev/null || i3lock -c 000000
        else
            notify-send "Error" "No lock command found" -i dialog-error
        fi
        ;;
    *)
        echo "Usage: $0 [shutdown|restart|sleep|logout|lock]"
        notify-send "Error" "Invalid power action: $action" -i dialog-error
        exit 1
        ;;
esac