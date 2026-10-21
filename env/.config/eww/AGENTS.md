# EWW Configuration Agent Guidelines

## Commands
- **Launch**: `./launch.sh` or `eww open topbar0 topbar1 topbar2`
- **Kill**: `eww kill`
- **Reload**: `eww reload`
- **Debug**: `eww debug` for widget inspection

## Multi-Monitor Requirements
- Config must work on any number of monitors without hardcoding monitor counts
- Use dynamic scripts to detect monitors and create bars automatically
- Never hardcode specific monitor numbers in YUCK files
- Launch scripts should detect available monitors and open bars accordingly
- **Dynamic adjustment**: Must automatically adjust when monitors are plugged/unplugged
- Implement monitor change listeners to add/remove bars in real-time

## Topbar Configuration

### Architecture Overview
The topbar system uses a dynamic configuration that automatically generates monitor-specific components:

- **Generated Config Location**: `~/.config/eww/tmp/` directory
- **Auto-detection**: `launch.sh` detects monitors and creates config files
- **Monitor-specific Components**: Each monitor gets its own workspace listener and center module

### Workspace System Behavior

#### Standard Workspaces (1-6)
- **Display**: Always visible on ALL monitors
- **Behavior**: Global workspace switching - clicking on any monitor affects all
- **Active State**: Shows consistently across all monitors
- **Styling**: 
  - Active: `◙` (filled square)
  - Inactive: `○` (circle)

#### High-numbered Workspaces (7+)
- **Active Workspace Behavior**: When workspace 7+ is active, it displays on:
  - ALL monitors if no specific monitor name is set (global view)
  - The bound monitor AND all monitors if the workspace is bound to the current monitor
  - Only on the bound monitor if workspace is bound to a different monitor
- **Inactive Workspace Behavior**: Workspaces 7+ with windows only show on their bound monitor
- **Purpose**: Dynamic workspaces that can be monitor-specific or global depending on usage

### Workspace Listener Logic
```bash
# Key logic in scripts/workspaces-listener.sh for workspaces 7+:
if [[ $active_workspace -gt 6 ]]; then
    local ws_bound_monitor=$(timeout 2 hyprctl -j workspaces 2>/dev/null | jq -r ".[] | select(.id == $active_workspace) | .monitor" 2>/dev/null)
    
    if [[ -z "$MONITOR_NAME" ]]; then
        # No monitor specified - show on all monitors
        all_workspaces="$all_workspaces $active_workspace"
    elif [[ "$ws_bound_monitor" == "$MONITOR_NAME" ]]; then
        # Workspace is bound to this monitor - show it
        all_workspaces="$all_workspaces $active_workspace"
    else
        # Workspace bound to different monitor - also show if it matches
        if [[ "$ws_bound_monitor" == "$MONITOR_NAME" ]]; then
            all_workspaces="$all_workspaces $active_workspace"
        fi
    fi
fi

# For inactive workspaces 7+ with windows:
# Only show on their bound monitor
```

### Configuration Files
- **Main Config**: `eww.yuck` includes auto-generated files
- **Generated Variables**: `tmp/modules/variables.yuck` - monitor-specific workspace listeners
- **Generated Widgets**: `tmp/widgets/center-modules.yuck` - per-monitor center modules  
- **Generated Bars**: `tmp/bars/topbar.yuck` - monitor-specific topbar windows

### Launch Process
1. `launch.sh` detects monitors using `hyprctl -j monitors`
2. Generates monitor-specific config in `tmp/` directory
3. Starts eww daemon first to avoid race conditions
4. Opens windows sequentially with delays to prevent duplication
5. Starts monitor-watcher for dynamic changes

## Code Style

### YUCK Files (.yuck)
- Use 2-space indentation
- Organize includes at top of main file: modules, widgets, bars
- Widget naming: lowercase with hyphens (e.g., `clock`, `system-info`)
- Add descriptive comments with `;; Comment` format
- Structure: `(defwidget name [] (box :class "class" ...))`

### SCSS Files (.scss)
- Use partial imports with `@import "styles/base"`
- Font: 'JetBrainsMono Nerd Font' at 14px base size
- Class naming: lowercase with hyphens matching widget names
- Organize into modular files: `_base.scss`, `_topbar.scss`, `_widgets.scss`

### Shell Scripts (.sh)
- Include shebang `#!/bin/bash`
- Add descriptive comments for script purpose
- Use functions for reusable logic
- Handle errors gracefully with `2>/dev/null || fallback`
- Scripts listen to system events and output data for eww consumption