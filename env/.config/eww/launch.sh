#!/bin/bash
# Dynamic eww multi-monitor bar launcher.
#
# Monitor binding notes for eww 0.5.x:
#   - `:monitor N` is an integer GDK monitor index.
#   - GDK on Wayland enumerates outputs in Hyprland's wl_output advertisement
#     order, which corresponds to Hyprland's `.id` field sorted ascending.
#   - Hyprland `.id` values are NOT the same as the default order returned by
#     `hyprctl -j monitors` and can have gaps (e.g. 0,1,3,2). We therefore
#     sort by `.id` and use the resulting zero-based position as the
#     `:monitor` index; that is what matches the GDK list that eww binds to.
#
# Concurrency notes:
#   - flock serializes concurrent invocations so monitor hotplug bursts from
#     monitor-watcher.sh cannot race each other into duplicate bars.

LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/eww-launch.lock"
exec 9>"$LOCK_FILE"
if ! flock -w 30 9; then
    echo "launch.sh: could not acquire $LOCK_FILE within 30s, aborting."
    exit 1
fi

# Substitutes {{MONITOR_ID}} in a template once per monitor.
generate_from_template() {
    local template_file="$1"
    local output_file="$2"
    local monitor_count="$3"

    {
        echo ";; Auto-generated from template: $(basename "$template_file")"
        for ((i=0; i<monitor_count; i++)); do
            sed "s|{{MONITOR_ID}}|${i}|g" "$template_file"
            echo ""
        done
    } > "$output_file"
}

generate_monitor_config() {
    # Monitor names sorted by Hyprland .id — position in this list is the
    # GDK monitor index that eww will bind `:monitor N` to.
    local monitors
    monitors=$(hyprctl -j monitors 2>/dev/null \
        | jq -r 'sort_by(.id) | .[].name')
    local monitor_count
    monitor_count=$(printf '%s\n' "$monitors" | grep -c .)

    mkdir -p ~/.config/eww/tmp/{bars,widgets,modules}
    mkdir -p ~/.config/eww/templates ~/.cache/eww

    # Stash for other scripts (e.g. show-colorpicker-popup.sh) so they can map
    # a Hyprland monitor to the same GDK index we are binding to here.
    printf '%s\n' "$monitors" > ~/.cache/eww/monitors.list

    {
        echo ";; Auto-generated monitor-specific workspace variables"
        local i=0
        while IFS= read -r monitor; do
            [[ -z "$monitor" ]] && continue
            echo "(deflisten workspaces_info_${i} :initial \"{\\\"active\\\": 1, \\\"occupied\\\": [1,2,3,4,5,6]}\""
            echo "  \"~/.config/eww/scripts/workspaces-listener.sh ${monitor}\")"
            echo ""
            ((i++))
        done <<< "$monitors"
    } > ~/.config/eww/tmp/modules/variables.yuck

    generate_from_template \
        ~/.config/eww/templates/center-modules.yuck.template \
        ~/.config/eww/tmp/widgets/center-modules.yuck \
        "$monitor_count"

    generate_from_template \
        ~/.config/eww/templates/topbar-content.yuck.template \
        ~/.config/eww/tmp/bars/topbar.yuck \
        "$monitor_count"

    generate_from_template \
        ~/.config/eww/templates/colorpicker-popup-window.yuck.template \
        ~/.config/eww/tmp/widgets/colorpicker-popup-windows.yuck \
        "$monitor_count"

    echo "$monitor_count"
}

# Stop any existing watcher first so it does not react to the churn below.
pkill -f monitor-watcher.sh 2>/dev/null || true

# Full reset: kill any existing daemon so we cannot inherit stale windows
# from a previous monitor layout.
eww kill 2>/dev/null || true
sleep 0.3

mkdir -p ~/.cache/eww
echo "Detecting monitors and generating configuration..."
monitor_count=$(generate_monitor_config)
echo "Found $monitor_count monitors, launching eww..."

eww daemon

# Wait until the daemon is actually responsive.
for _ in {1..50}; do
    if eww ping >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done
# Extra settle time for GDK/Wayland to finish enumerating outputs before we
# bind windows to them.
sleep 0.5

windows=()
for ((i=0; i<monitor_count; i++)); do
    windows+=("topbar${i}")
done

# Parse the second column of `eww active-windows` (`<id>: <name>`).
active_window_names() {
    eww active-windows 2>/dev/null | awk -F': ' 'NF>=2 {print $2}'
}

open_and_verify() {
    local attempts=0
    local log=~/.cache/eww/launch.log
    while ((attempts < 3)); do
        ((attempts++))
        eww close "${windows[@]}" >/dev/null 2>&1 || true
        if ((${#windows[@]} > 0)); then
            eww open-many "${windows[@]}" >>"$log" 2>&1 || true
        fi

        local active missing=0 w
        active=$(active_window_names)
        for w in "${windows[@]}"; do
            if ! grep -qx "$w" <<< "$active"; then
                ((missing++))
            fi
        done
        if ((missing == 0)); then
            echo "launch.sh: opened ${#windows[@]} bars on attempt $attempts" >>"$log"
            return 0
        fi
        echo "launch.sh: $missing bars missing after attempt $attempts" >>"$log"
        sleep 0.5
    done
    return 1
}

if ((${#windows[@]} > 0)); then
    open_and_verify || echo "launch.sh: some bars never opened; see ~/.cache/eww/launch.log"
fi

# Start monitor watcher detached so it outlives this script and the lock.
echo "Starting monitor change watcher..."
setsid ~/.config/eww/scripts/monitor-watcher.sh \
    >> ~/.cache/eww/monitor-watcher.log 2>&1 </dev/null &
disown 2>/dev/null || true

flock -u 9
