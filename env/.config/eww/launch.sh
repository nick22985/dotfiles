#!/bin/bash

# Function to generate from template
generate_from_template() {
    local template_file="$1"
    local output_file="$2"
    local monitor_count="$3"
    
    {
        echo ";; Auto-generated from template: $(basename "$template_file")"
        for ((i=0; i<monitor_count; i++)); do
            sed "s/{{MONITOR_ID}}/$i/g" "$template_file"
            echo ""
        done
    } > "$output_file"
}

# Generate dynamic eww configuration based on detected monitors
generate_monitor_config() {
    local monitors=$(hyprctl -j monitors | jq -r '.[].name')
    local monitor_count=$(echo "$monitors" | wc -l)
    
    # Create tmp directory structure
    mkdir -p ~/.config/eww/tmp/{bars,widgets,modules}
    mkdir -p ~/.config/eww/templates
    
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
    
    # Generate center widgets from template
    generate_from_template \
        ~/.config/eww/templates/center-modules.yuck.template \
        ~/.config/eww/tmp/widgets/center-modules.yuck \
        "$monitor_count"

    # Generate topbar content and windows from template
    generate_from_template \
        ~/.config/eww/templates/topbar-content.yuck.template \
        ~/.config/eww/tmp/bars/topbar.yuck \
        "$monitor_count"

    # Generate colorpicker popup windows from template
    generate_from_template \
        ~/.config/eww/templates/colorpicker-popup-window.yuck.template \
        ~/.config/eww/tmp/widgets/colorpicker-popup-windows.yuck \
        "$monitor_count"
    
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

