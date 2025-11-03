#!/bin/bash

# Dynamic eww multi-monitor bar management script

case "$1" in
    "start"|"launch"|"restart")
        echo "Starting eww with dynamic monitor detection..."
        ~/.config/eww/launch.sh
        ;;
    "stop"|"kill")
        echo "Stopping eww and monitor watcher..."
        eww kill
        pkill -f monitor-watcher.sh 2>/dev/null || true
        echo "All processes stopped!"
        ;;
    "reload")
        echo "Reloading eww configuration..."
        eww reload
        ;;
    "status")
        echo "=== EWW Status ==="
        echo "Active eww windows:"
        eww active-windows 2>/dev/null || echo "No eww windows active"
        echo ""
        echo "=== Processes ==="
        echo "EWW processes:"
        pgrep -f eww || echo "No eww processes found"
        echo "Monitor watcher:"
        pgrep -f monitor-watcher.sh || echo "No monitor watcher found"
        echo ""
        echo "=== Current Monitors ==="
        hyprctl -j monitors 2>/dev/null | jq -r '.[].name' | nl || echo "Could not detect monitors"
        ;;
    "logs")
        echo "Monitor watcher log (last 20 lines):"
        tail -20 ~/.cache/eww/monitor-watcher.log 2>/dev/null || echo "No monitor watcher log found"
        ;;
    "watch")
        echo "Watching monitor watcher log (Ctrl+C to exit):"
        tail -f ~/.cache/eww/monitor-watcher.log 2>/dev/null || echo "No monitor watcher log found"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|reload|status|logs|watch}"
        echo ""
        echo "Commands:"
        echo "  start/restart - Launch eww with dynamic monitor detection"
        echo "  stop/kill     - Stop eww and monitor watcher"
        echo "  reload        - Reload eww configuration only"
        echo "  status        - Show running processes and monitor info"
        echo "  logs          - Show monitor watcher logs"
        echo "  watch         - Watch monitor watcher logs in real-time"
        exit 1
        ;;
esac