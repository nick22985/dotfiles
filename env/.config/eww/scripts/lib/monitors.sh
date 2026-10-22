#!/bin/bash

# Output names in the order GDK numbers monitors, which is what eww's :monitor and --screen
# indexes mean. An output that drops out and comes back goes to the end, so this order can
# change while the set of names stays the same.
gdk_monitor_names() {
    wayland-info 2>/dev/null \
        | awk '/interface:.*wl_output/{found=1} found && /^\tname:/{print $2; found=0}'
}
