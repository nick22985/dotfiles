#!/bin/bash
# Dynamic eww multi-monitor bar launcher.

LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/eww-launch.lock"
SIGNATURE_FILE=~/.cache/eww/monitors.signature
MONITORS_FILE=~/.cache/eww/monitors.list

exec 9>"$LOCK_FILE"
if ! flock -w 30 9; then
    echo "launch.sh: could not acquire $LOCK_FILE within 30s, aborting."
    exit 1
fi

gdk_monitor_names() {
    wayland-info 2>/dev/null \
        | awk '/interface:.*wl_output/{found=1} found && /^\tname:/{print $2; found=0}'
}

hypr_monitor_names() {
    hyprctl -j monitors 2>/dev/null | jq -r 'sort_by(.id) | .[].name'
}

# Order-independent identity of the current monitor set.
monitor_signature() {
    hyprctl -j monitors 2>/dev/null | jq -r 'sort_by(.name) | map(.name) | join(",")'
}

count_lines() {
    grep -c . <<< "$1"
}

SAMPLE_INTERVAL=0.3
STABLE_SAMPLES=7
MAX_SAMPLES=60

wait_for_stable_monitors() {
    local previous="" current="" hypr_count gdk_count
    local stable=0 attempt=0

    while ((attempt < MAX_SAMPLES)); do
        ((attempt++))

        current=$(gdk_monitor_names)
        [[ -z "$current" ]] && current=$(hypr_monitor_names)

        gdk_count=$(count_lines "$current")
        hypr_count=$(count_lines "$(hypr_monitor_names)")

        if ((gdk_count > 0)) && ((gdk_count == hypr_count)) && [[ "$current" == "$previous" ]]; then
            ((stable++))
            if ((stable >= STABLE_SAMPLES)); then
                printf '%s\n' "$current"
                return 0
            fi
        else
            stable=0
        fi

        previous="$current"
        sleep "$SAMPLE_INTERVAL"
    done

    echo "launch.sh: monitor list never settled after ${MAX_SAMPLES} samples;" \
         "proceeding with last reading" >&2
    printf '%s\n' "$current"
}

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
    local monitors="$1"

    local monitor_count
    monitor_count=$(count_lines "$monitors")

    mkdir -p ~/.config/eww/tmp/{bars,widgets,modules}
    mkdir -p ~/.config/eww/templates ~/.cache/eww

    # Stash for other scripts (e.g. show-colorpicker-popup.sh) so they can map
    # a Hyprland monitor to the same GDK index we are binding to here.
    printf '%s\n' "$monitors" > "$MONITORS_FILE"

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
}

# Stop any existing watcher first so it does not react to the churn below.
pkill -f monitor-watcher.sh 2>/dev/null || true

# Full reset: kill any existing daemon so we cannot inherit stale windows
# from a previous monitor layout.
eww kill 2>/dev/null || true
for _ in {1..50}; do
    eww ping >/dev/null 2>&1 || break
    sleep 0.1
done

mkdir -p ~/.cache/eww
echo "Detecting monitors and generating configuration..."
monitors=$(wait_for_stable_monitors)
launch_signature=$(monitor_signature)
generate_monitor_config "$monitors"

monitor_count=$(count_lines "$monitors")
echo "Found $monitor_count monitors ($launch_signature), launching eww..."

printf '%s\n' "$launch_signature" > "$SIGNATURE_FILE"

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

final_signature=$(monitor_signature)
if [[ "$final_signature" != "$launch_signature" && -z "$EWW_LAUNCH_RETRY" ]]; then
    echo "launch.sh: monitors changed during launch ($launch_signature -> $final_signature), relaunching."
    flock -u 9
    exec env EWW_LAUNCH_RETRY=1 "$0" "$@"
fi

# Start monitor watcher detached so it outlives this script and the lock.
echo "Starting monitor change watcher..."
setsid ~/.config/eww/scripts/monitor-watcher.sh \
    >> ~/.cache/eww/monitor-watcher.log 2>&1 </dev/null &
disown 2>/dev/null || true

flock -u 9
