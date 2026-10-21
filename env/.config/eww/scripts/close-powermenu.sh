#!/bin/bash

# Close power menu and cleanup

# Use the simple powermenu script
~/.config/eww/scripts/powermenu-simple.sh close

# Kill any remaining escape listeners (fallback cleanup)
pkill -f "powermenu-escape-listener.sh" 2>/dev/null
rm -f /tmp/powermenu-listener.pid 2>/dev/null