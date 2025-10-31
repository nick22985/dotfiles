#!/bin/bash

# Eww multi-monitor bar management script

case "$1" in
    "start"|"launch")
        echo "Starting topbars on all monitors..."
        eww kill 2>/dev/null
        eww open topbar0
        eww open topbar1 
        eww open topbar2
        echo "All topbars launched!"
        ;;
    "stop"|"kill")
        echo "Stopping all topbars..."
        eww kill
        echo "All topbars stopped!"
        ;;
    "restart"|"reload")
        echo "Restarting topbars..."
        eww kill 2>/dev/null
        eww reload
        sleep 1
        eww open topbar0
        eww open topbar1
        eww open topbar2
        echo "All topbars restarted!"
        ;;
    "status")
        echo "Active eww windows:"
        eww active-windows
        ;;
    "monitor0"|"m0")
        eww close topbar0 2>/dev/null
        eww open topbar0
        echo "Topbar on monitor 0 refreshed"
        ;;
    "monitor1"|"m1")
        eww close topbar1 2>/dev/null
        eww open topbar1
        echo "Topbar on monitor 1 refreshed"
        ;;
    "monitor2"|"m2")
        eww close topbar2 2>/dev/null
        eww open topbar2
        echo "Topbar on monitor 2 refreshed"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|monitor0|monitor1|monitor2}"
        echo ""
        echo "Commands:"
        echo "  start/launch  - Start topbars on all monitors"
        echo "  stop/kill     - Stop all topbars"
        echo "  restart/reload- Restart all topbars"
        echo "  status        - Show active windows"
        echo "  monitor0/m0   - Refresh topbar on monitor 0"
        echo "  monitor1/m1   - Refresh topbar on monitor 1" 
        echo "  monitor2/m2   - Refresh topbar on monitor 2"
        exit 1
        ;;
esac