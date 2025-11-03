#!/bin/bash

# Generate dynamic eww configuration based on detected monitors
generate_monitor_config() {
    local monitors=$(hyprctl -j monitors | jq -r '.[].name')
    local monitor_count=$(echo "$monitors" | wc -l)
    
    # Create tmp directory structure
    mkdir -p ~/.config/eww/tmp/{bars,widgets,modules}
    
    # Generate variables for each monitor
    {
        echo ";; Auto-generated monitor-specific workspace variables"
        local i=0
        while IFS= read -r monitor; do
            echo "(deflisten workspaces_info_${i} :initial \"{\\\"active\\\": 1, \\\"occupied\\\": [1,2,3,4,5,6]}\""
            echo "  \"~/.config/eww/scripts/workspaces-listener.sh ${monitor}\")"
            echo ""
            ((i++))
        done <<< "$monitors"
    } > ~/.config/eww/tmp/modules/variables.yuck
    
    # Generate center widgets for each monitor
    {
        echo ";; Auto-generated monitor-specific center widgets"
        local i=0
        while IFS= read -r monitor; do
            cat << EOF
(defwidget center_modules_${i} []
  (box :class "modules-center"
       :space-evenly false
       :spacing 10
    (workspaces :workspace_info workspaces_info_${i})
    (mpd_widget)))

EOF
            ((i++))
        done <<< "$monitors"
    } > ~/.config/eww/tmp/widgets/center-modules.yuck

    # Generate topbar content and windows for each monitor
    {
        echo ";; Auto-generated monitor-specific topbar content and windows"
        local i=0
        while IFS= read -r monitor; do
            cat << EOF
(defwidget topbar_content_${i} []
  (centerbox
    :orientation "h"
    :class "topbar-centerbox"
    (box :class "left-container" 
         :halign "start"
         :hexpand false
      (left_modules))
    (box :class "center-container"
         :halign "center" 
         :hexpand false
      (center_modules_${i}))
    (box :class "right-container"
         :halign "end"
         :hexpand false
      (right_modules))))

(defwindow topbar${i}
  :monitor ${i}
  :geometry (geometry :x "0%" :y "0%" :width "100%" :height "33px" :anchor "top center")
  :stacking "fg"
  :exclusive true
  (topbar_content_${i}))

EOF
            ((i++))
        done <<< "$monitors"
    } > ~/.config/eww/tmp/bars/topbar.yuck
    
    # Files are now generated in tmp directory - no need to modify main config files
    
    echo "$monitor_count"
}

# Close previous instances
eww kill

# Kill any existing monitor watcher
pkill -f monitor-watcher.sh 2>/dev/null || true

# Generate configuration based on current monitors
echo "Detecting monitors and generating configuration..."
monitor_count=$(generate_monitor_config)

echo "Found $monitor_count monitors, launching eww..."

# Start eww daemon first
eww daemon

# Wait a moment for daemon to initialize
sleep 2

# Launch eww bars for all detected monitors sequentially
for ((i=0; i<monitor_count; i++)); do
    eww open topbar${i}
    sleep 0.5  # Small delay between window opens
done

# Start monitor watcher in background
echo "Starting monitor change watcher..."
~/.config/eww/scripts/monitor-watcher.sh > ~/.cache/eww/monitor-watcher.log 2>&1 &

wait

