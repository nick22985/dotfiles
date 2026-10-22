#!/usr/bin/env bash

# Shared utilities for dotfiles scripts
# Source this file in other scripts: source "$DOTFILES_DIR/lib/utils.sh"

caller_script="$(realpath -m -- "${BASH_SOURCE[1]:-}")"
if [[ "$caller_script" == "${DOTFILES_DIR:?DOTFILES_DIR must be set}"/modules/*/install ]]; then
    if [[ "${DOTFILES_RUNNER_ACTIVE:-0}" != "1" \
        || "${DOTFILES_RUNNER_PID:-}" != "$PPID" \
        || -z "${DOTFILES_RECEIPT_DIR:-}" ]]; then
        printf 'Internal module scripts must be executed through ./run apply.\n' >&2
        exit 2
    fi
    # flatpak, paru and others catch Ctrl-C and exit normally, which bash takes to mean
    # the interrupt was handled; without this the module would run its remaining steps.
    trap 'exit 130' INT TERM
fi

# Global dry run flag (can be overridden by individual scripts)
DRY_RUN="${DRY_RUN:-0}"

source "$DOTFILES_DIR/lib/platforms.sh"
active_platform="${DOTFILES_PLATFORM:-$(platform_detect)}"
if [[ "$active_platform" != "unsupported" ]]; then
    platform_activate "$active_platform"
fi

# Global quiet flag - when enabled, only show warnings and errors
QUIET="${QUIET:-0}"

# Error and Warning Tracking System (File-based for persistence across scripts)
# =============================================================================
# Use a consistent directory name that all scripts can share
DOTFILES_TEMP_DIR="${DOTFILES_TEMP_DIR:-${TMPDIR:-/tmp}/dotfiles-tracking}"
DOTFILES_ERRORS_FILE="${DOTFILES_ERRORS_FILE:-$DOTFILES_TEMP_DIR/errors.log}"
DOTFILES_WARNINGS_FILE="${DOTFILES_WARNINGS_FILE:-$DOTFILES_TEMP_DIR/warnings.log}"
declare -a DOTFILES_CONTEXT_STACK=()

# Initialize error tracking (create temp directory and files)
init_error_tracking() {
    mkdir -p "$DOTFILES_TEMP_DIR"
    touch "$DOTFILES_ERRORS_FILE" "$DOTFILES_WARNINGS_FILE"
}

# Cleanup error tracking files
cleanup_error_tracking() {
    rm -rf "$DOTFILES_TEMP_DIR" 2>/dev/null || true
}

# Set current context for error tracking (e.g., "Installing packages", "Setting up Git")
set_context() {
    local context="$1"
    DOTFILES_CONTEXT_STACK=("$context")
}

# Push a sub-context onto the stack
push_context() {
    local context="$1"
    DOTFILES_CONTEXT_STACK+=("$context")
}

# Pop the last context from the stack
pop_context() {
    if [ ${#DOTFILES_CONTEXT_STACK[@]} -gt 0 ]; then
        unset 'DOTFILES_CONTEXT_STACK[-1]'
    fi
}

# Get current context string
get_context() {
    if [ ${#DOTFILES_CONTEXT_STACK[@]} -gt 0 ]; then
        local IFS=" → "
        echo "${DOTFILES_CONTEXT_STACK[*]}"
    else
        echo "General"
    fi
}

# Enhanced logging functions with error/warning tracking
log() {
    # In quiet mode, suppress normal log messages
    if [[ $QUIET == "1" ]]; then
        return
    fi
    
    if [[ $DRY_RUN == "1" ]]; then
        echo "[DRY_RUN]: $1"
    else
        echo "$1"
    fi
}

# Log an error and track it
log_error() {
    local message="$1"
    local context="$(get_context)"

    if [[ $DRY_RUN == "1" ]]; then
        echo "[DRY_RUN] ❌ $message"
    else
        echo "❌ $message"
    fi

    # Initialize tracking if not already done
    init_error_tracking

    # Write error to file for persistence across script executions
    echo "[$context] $message" >> "$DOTFILES_ERRORS_FILE"
}

# Log a warning and track it
log_warn() {
    local message="$1"
    local context="$(get_context)"

    if [[ $DRY_RUN == "1" ]]; then
        echo "[DRY_RUN] ⚠ $message"
    else
        echo "⚠ $message"
    fi

    # Initialize tracking if not already done
    init_error_tracking

    # Write warning to file for persistence across script executions
    echo "[$context] $message" >> "$DOTFILES_WARNINGS_FILE"
}

# Log success
log_success() {
    local message="$1"
    
    # In quiet mode, suppress success messages
    if [[ $QUIET == "1" ]]; then
        return
    fi
    
    if [[ $DRY_RUN == "1" ]]; then
        echo "[DRY_RUN] ✓ $message"
    else
        echo "✓ $message"
    fi
}

# Log info/progress
log_info() {
    local message="$1"
    
    # In quiet mode, suppress info messages
    if [[ $QUIET == "1" ]]; then
        return
    fi
    
    if [[ $DRY_RUN == "1" ]]; then
        echo "[DRY_RUN] → $message"
    else
        echo "→ $message"
    fi
}

# Function to ensure sudo is available (only request if needed and not in dry run)
ensure_sudo() {
    if [[ $DRY_RUN == "1" ]]; then
        return 0
    fi

    # Check if we can run sudo without password prompt
    if sudo -n true 2>/dev/null; then
        return 0
    fi

    # If not, request sudo (this should only happen if main script didn't handle it)
    log "→ Requesting sudo privileges for this script..."
    if sudo -n true 2>/dev/null || sudo -v; then
        return 0
    else
        log "❌ Failed to get sudo privileges"
        return 1
    fi
}

# Parse common arguments (--dry and --auto-backup flags)
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry)
                DRY_RUN="1"
                ;;
            --auto-backup)
                AUTO_BACKUP="1"
                ;;
            --quiet|-q)
                QUIET="1"
                ;;
            --link)
                LINK_MODE="1"
                ;;
            *)
                # Return remaining args
                echo "$@"
                return
                ;;
        esac
        shift
    done
}

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Build a Rust binary from a local checkout and install it to ~/.local/bin,
# recording a restore step in the run receipt when it replaces a file.
# A bare repository (.bare or flat layout) keeps its checked-out branch in <dir>/<branch>; any
# other directory is printed as given.
checkout_dir() {
    local branch
    if [[ "$(git -C "$1" rev-parse --is-bare-repository 2>/dev/null)" == "true" ]] \
        && branch="$(git -C "$1" symbolic-ref -q --short HEAD)" && [[ -d "$1/$branch" ]]; then
        printf '%s\n' "$1/$branch"
    else
        printf '%s\n' "$1"
    fi
}

# Usage: install_cargo_binary <name> <source dir>
# Records the commands that undo one change, for restore-user.sh or restore-system.sh in the run
# receipt. The restore scripts run records newest first, so a path changed twice in one run is
# put back as it was before the run.
receipt_add_restore() {
    local kind="$1" dir count
    shift
    [[ -n "${DOTFILES_RECEIPT_DIR:-}" ]] || return 0
    dir="$DOTFILES_RECEIPT_DIR/restore.d/$kind"
    mkdir -p "$dir" || return 1
    count="$(find "$dir" -mindepth 1 -maxdepth 1 -type f | wc -l)"
    printf '%s\n' "$@" > "$(printf '%s/%06d.sh' "$dir" "$count")"
}

install_cargo_binary() {
    local name="$1" src="$2"
    local dest="$HOME/.local/bin/$name"

    [[ -f "$src/Cargo.toml" ]] || src="$(checkout_dir "$src")"

    if [[ ! -f "$src/Cargo.toml" ]]; then
        log_warn "$name source not found at $src, skipping"
        log_info "clone the repo (or add it to repos.txt) and re-run this script"
        return 0
    fi

    # Run cargo through mise so the pinned toolchain applies without shell activation.
    local -a cargo_cmd=(cargo)
    command_exists mise && cargo_cmd=(mise exec -- cargo)
    if ! "${cargo_cmd[@]}" --version >/dev/null 2>&1; then
        log_error "cargo not found — install Rust before this script runs"
        log_info "add rust to profiles/development/tools.list and run the mise module"
        return 1
    fi

    log "→ Building $name from $src..."
    if [[ $DRY_RUN == "1" ]]; then
        log "Would run: cargo build --release in $src"
        log "Would copy $src/target/release/$name → $dest"
        return 0
    fi
    if ! (cd "$src" && "${cargo_cmd[@]}" build --release --quiet); then
        log_error "cargo build failed for $name"
        return 1
    fi

    log "→ Installing to $dest..."
    mkdir -p "$(dirname "$dest")"
    if [[ -f "$dest" ]] && cmp -s "$src/target/release/$name" "$dest"; then
        log_success "$dest is current"
        return 0
    fi
    if [[ -z "${DOTFILES_RECEIPT_DIR:-}" ]]; then
        log_error "Installing $name requires a run receipt"
        return 1
    fi
    if [[ -e "$dest" || -L "$dest" ]]; then
        local backup="$DOTFILES_RECEIPT_DIR/backups/user/.local/bin/$name"
        mkdir -p "$(dirname "$backup")"
        mv -- "$dest" "$backup" || return 1
        receipt_add_restore user "$(printf 'rm -f -- %q\nmkdir -p %q\nmv -- %q %q' \
            "$dest" "$(dirname "$dest")" "$backup" "$dest")"
    else
        receipt_add_restore user "$(printf 'rm -f -- %q' "$dest")"
    fi
    install -m 755 "$src/target/release/$name" "$dest" || return 1
    log_success "$name installed to $dest"
}

# Check if package is installed (Arch)
is_installed_pacman() {
    pacman -Qi -- "$1" &> /dev/null
}

# Check if package is installed (Debian/Ubuntu)
check_ssh_keys() {
    local ssh_dir="$HOME/.ssh"
    local has_keys=false

    push_context "SSH keys"

    if [[ -d "$ssh_dir" ]]; then
        # Check for common SSH key types
        for key_type in id_rsa id_ed25519 id_ecdsa; do
            if [[ -f "$ssh_dir/$key_type" ]]; then
                log_success "Found SSH key: $key_type"
                has_keys=true
            fi
        done
    fi

    if [[ $has_keys == false ]]; then
        log_warn "No SSH keys found in $ssh_dir"
        log "→ Generate SSH key with: ssh-keygen -t ed25519 -C 'your.email@example.com'"
        log "→ Add to GitHub: cat ~/.ssh/id_ed25519.pub"
    fi

    pop_context
    return $([[ $has_keys == true ]] && echo 0 || echo 1)
}

# Check GPG key setup
check_gpg_keys() {
    if ! command_exists gpg; then
        log "⚠ GPG not installed"
        return 0  # Don't fail the script, just inform
    fi

    local gpg_keys=$(gpg --list-secret-keys --keyid-format LONG 2>/dev/null | grep sec | wc -l)

    if [[ $gpg_keys -gt 0 ]]; then
        log "✓ Found $gpg_keys GPG key(s)"

        # Check if git is configured to use GPG
        local signing_key=$(git config --global user.signingkey 2>/dev/null || echo "")
        if [[ -n "$signing_key" ]]; then
            log "✓ Git configured to use GPG key: $signing_key"
        else
            log "→ Configure git to use GPG: git config --global user.signingkey YOUR_KEY_ID"
            log "→ Enable commit signing: git config --global commit.gpgsign true"
        fi
    else
        log "⚠ No GPG keys found"
        log "→ Generate GPG key with: gpg --full-generate-key"
        log "→ Configure git: git config --global user.signingkey YOUR_KEY_ID"
    fi

    return 0  # Always succeed - GPG keys are optional
}
# Initialize/update git submodules
reload_hyprland() {
    log "→ Reloading Hyprland configuration..."

    # Check if hyprctl is available
    if ! command_exists hyprctl; then
        log "⚠ hyprctl not found, skipping Hyprland reload"
        return 0
    fi

    log "→ Looking for running Hyprland instance..."
    local hyprland_pid=$(pgrep -x "Hyprland" | head -1)
    if [[ -z "$hyprland_pid" ]]; then
        log "⚠ Hyprland not running, skipping reload"
        return 0
    fi

    log "→ Found Hyprland process (PID: $hyprland_pid)"

    local hyprland_user=$(ps -o user= -p "$hyprland_pid" | tr -d ' ')
    local hyprland_uid=$(id -u "$hyprland_user" 2>/dev/null || echo "")

    if [[ -z "$hyprland_uid" ]]; then
        log "⚠ Could not determine Hyprland user, using current user"
        hyprland_uid=$(id -u)
    fi

    log "→ Hyprland running as user: $hyprland_user (UID: $hyprland_uid)"

    if [[ $DRY_RUN == "0" ]]; then
        local hypr_socket_dir="/run/user/$hyprland_uid/hypr"

        if [[ ! -d "$hypr_socket_dir" ]]; then
            log "⚠ Hyprland socket directory not found at $hypr_socket_dir"
            return 1
        fi

        local signature_path=$(find "$hypr_socket_dir" -maxdepth 1 -type d -name "*_*_*" | head -1)
        if [[ -z "$signature_path" ]]; then
            log "⚠ No Hyprland instance signature found in $hypr_socket_dir"
            return 1
        fi

        local signature=$(basename "$signature_path")
        log "→ Found Hyprland instance signature: $signature"

        log "→ Attempting hyprctl reload with signature..."
        if HYPRLAND_INSTANCE_SIGNATURE="$signature" hyprctl reload 2>/dev/null; then
            log "✓ Hyprland configuration reloaded successfully"
        else
            log "→ hyprctl failed, trying direct socket communication..."

            local socket_path="$signature_path/.socket.sock"
            if [[ -S "$socket_path" ]]; then
                log "→ Using socket: $socket_path"
                if echo "reload" | socat - "UNIX-CONNECT:$socket_path" 2>/dev/null; then
                    log "✓ Hyprland configuration reloaded via socket"
                else
                    log "→ Socket communication failed, trying process signal..."

                    if kill -USR1 "$hyprland_pid" 2>/dev/null; then
                        log "✓ Sent reload signal to Hyprland process"
                    else
                        log "⚠ All reload methods failed"
                        return 1
                    fi
                fi
            else
                log "⚠ Hyprland socket not found at $socket_path"

                if kill -USR1 "$hyprland_pid" 2>/dev/null; then
                    log "✓ Sent reload signal to Hyprland process"
                else
                    log "⚠ Failed to send signal to Hyprland process"
                    return 1
                fi
            fi
        fi
    else
        log "Would find Hyprland instance and run: hyprctl reload"
    fi

    return 0
}

# Reload tmux configuration
reload_tmux() {
    log "→ Reloading tmux configuration..."

    # Check if tmux is available
    if ! command_exists tmux; then
        log "⚠ tmux not found, skipping tmux reload"
        return 0
    fi

    # Check if there are any tmux sessions running
    if ! tmux list-sessions &>/dev/null; then
        log "⚠ No tmux sessions running, skipping reload"
        return 0
    fi

    if [[ $DRY_RUN == "0" ]]; then
        local config_file=""
        
        # Determine which config file to use
        if [[ -f "$HOME/.config/tmux/tmux.conf" ]]; then
            config_file="$HOME/.config/tmux/tmux.conf"
        elif [[ -f "$HOME/.tmux.conf" ]]; then
            config_file="$HOME/.tmux.conf"
        else
            log "⚠ No tmux configuration file found"
            return 1
        fi

        log "→ Using config file: $config_file"
        
        # Source the configuration file globally
        if tmux source-file "$config_file" 2>/dev/null; then
            log "→ Configuration sourced globally"
        else
            log "⚠ Failed to source configuration globally"
            return 1
        fi
        
        # Check if TPM (Tmux Plugin Manager) is available and reload plugins
        local tpm_path="$HOME/.config/tmux/plugins/tpm/tpm"
        if [[ -f "$tpm_path" ]]; then
            log "→ Reloading tmux plugins with TPM..."
            # Run TPM to reload plugins
            "$tpm_path" 2>/dev/null || true
            # Also try to reload plugins using TPM's reload functionality
            tmux run-shell "$HOME/.config/tmux/plugins/tpm/scripts/install_plugins.sh" 2>/dev/null || true
        fi
        
        # Force reload of Catppuccin theme if it exists
        local catppuccin_path="$HOME/.config/tmux/plugins/catppuccin/catppuccin.tmux"
        if [[ -f "$catppuccin_path" ]]; then
            log "→ Reloading Catppuccin theme..."
            tmux run-shell "$catppuccin_path" 2>/dev/null || true
        fi
        
        # Kill and restart the status bar to force complete theme reload
        tmux set-option -g status off 2>/dev/null || true
        sleep 0.2
        tmux set-option -g status on 2>/dev/null || true
        
        # Get all sessions and refresh each one
        local sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null)
        local refresh_count=0
        
        while IFS= read -r session; do
            if [[ -n "$session" ]]; then
                log "→ Refreshing session: $session"
                # Multiple refresh methods to ensure theme is applied
                tmux refresh-client -t "$session" 2>/dev/null || true
                tmux refresh-client -t "$session" -S 2>/dev/null || true
                # Force complete redraw
                tmux refresh-client -t "$session" -f 2>/dev/null || true
                refresh_count=$((refresh_count + 1))
            fi
        done <<< "$sessions"
        
        # Final global refresh
        tmux refresh-client -S 2>/dev/null || true
        
        if [[ $refresh_count -gt 0 ]]; then
            log "✓ tmux configuration and plugins reloaded, $refresh_count session(s) refreshed"
        else
            log "⚠ No sessions were refreshed"
            return 1
        fi
    else
        log "Would reload tmux configuration, plugins, and refresh all running sessions"
    fi

    return 0
}

# Package Manager Utility Functions
# ===================================

# Install packages using pacman (Arch Linux)
install_packages_pacman() {
    local packages=("$@")
    local packages_to_install=()
    local status=0

    push_context "pacman packages"

    # Check which packages need to be installed
    for package in "${packages[@]}"; do
        if ! is_installed_pacman "$package"; then
            packages_to_install+=("$package")
        else
            log_success "$package already installed"
        fi
    done

    if [ ${#packages_to_install[@]} -gt 0 ]; then
        log_info "Installing packages: ${packages_to_install[*]}"
        if [[ $DRY_RUN == "0" ]]; then
            # Sync and upgrade with the install: a stale database 404s on new packages, and a sync alone is a partial upgrade
            local install_output
            if install_output=$(sudo pacman -Syu --needed --noconfirm -- "${packages_to_install[@]}" 2>&1); then
                log_success "All packages installed successfully"
            else
                # Parse the output to find specific failed packages
                local failed_packages=()
                for package in "${packages_to_install[@]}"; do
                    if echo "$install_output" | grep -q "target not found: $package"; then
                        failed_packages+=("$package")
                    fi
                done

                if [ ${#failed_packages[@]} -gt 0 ]; then
                    log_error "Failed to install packages: ${failed_packages[*]} (not found in repositories)"
                else
                    # pacman prints the cause after the transaction summary, so prefer its error lines
                    local formatted_error=$(echo "$install_output" | grep -E '^(error|warning):' | head -5 | tr '\n' '; ' | sed 's/; $//')
                    [[ -n "$formatted_error" ]] || formatted_error=$(echo "$install_output" | tail -5 | tr '\n' '; ' | sed 's/; $//')
                    log_error "Package installation failed: $formatted_error"
                fi
                status=1
                # Don't exit - continue execution and let summary show the error
            fi
        fi
    else
        log_success "All packages already installed"
    fi

    pop_context
    return "$status"
}

# Install packages using apt (Ubuntu/Debian)
install_packages_aur() {
    local packages=("$@")
    local packages_to_install=()
    local status=0

    push_context "AUR packages"

    # Check if paru is available
    if ! command_exists paru; then
        if [[ $DRY_RUN == "1" ]]; then
            log_info "Would install AUR packages after the paru prerequisite is met: ${packages[*]}"
            pop_context
            return 0
        fi
        log_error "paru not found, cannot install AUR packages"
        pop_context
        return 1
    fi

    # Check which packages need to be installed
    for package in "${packages[@]}"; do
        if ! is_installed_pacman "$package"; then
            packages_to_install+=("$package")
        else
            log_success "$package (AUR) already installed"
        fi
    done

    if [ ${#packages_to_install[@]} -gt 0 ]; then
        log_info "Installing AUR packages: ${packages_to_install[*]}"
        if [[ $DRY_RUN == "0" ]]; then
            # Stream paru output so build progress and errors stay visible, keeping a copy to parse.
            # --removemake drops build-only deps (pacman's rust/cargo); mise owns the user toolchains.
            local install_output install_log paru_status
            install_log="$(mktemp)"
            paru -S --needed --noconfirm --removemake -- "${packages_to_install[@]}" 2>&1 | tee "$install_log"
            paru_status="${PIPESTATUS[0]}"
            install_output="$(<"$install_log")"
            rm -f "$install_log"
            if [[ "$paru_status" == "0" ]]; then
                log_success "All AUR packages installed successfully"
            else
                # Parse the output to find specific failed packages
                local failed_packages=()
                for package in "${packages_to_install[@]}"; do
                    if echo "$install_output" | grep -q "target not found: $package\|could not find all required packages"; then
                        failed_packages+=("$package")
                    fi
                done

                if [ ${#failed_packages[@]} -gt 0 ]; then
                    log_error "Failed to install AUR packages: ${failed_packages[*]} (not found in AUR)"
                else
                    log_error "AUR package installation failed: $(echo "$install_output" | grep -iE 'error|conflict' | tail -3 | tr '\n' ' ')"
                fi
                status=1
                # Don't exit - continue execution and let summary show the error
            fi
        fi
    else
        log_success "All AUR packages already installed"
    fi

    pop_context
    return "$status"
}

install_module_packages() {
    install_package_list "$DOTFILES_DIR/modules/$1"
}

apply_module_services() {
    platform_apply_service_manifest "$1"
}

apply_module_groups() {
    platform_apply_group_manifest "$1"
}

apply_module_system_files() {
    platform_apply_system_file_manifest "$1"
}

# Install packages using yay (alternative AUR helper)
install_packages_flatpak() {
    local packages=("$@")
    local packages_to_install=()
    local status=0

    push_context "Flatpak packages"

    # Check if flatpak is available
    if ! command_exists flatpak; then
        log_error "flatpak not found, cannot install Flatpak packages"
        pop_context
        return 1
    fi

    # Check which packages need to be installed
    for package in "${packages[@]}"; do
        if ! flatpak list --user --app --columns=application | grep -Fxq -- "$package"; then
            packages_to_install+=("$package")
        else
            log_success "$package (Flatpak) already installed"
        fi
    done

    if [ ${#packages_to_install[@]} -gt 0 ]; then
        log_info "Installing Flatpak packages: ${packages_to_install[*]}"
        if [[ $DRY_RUN == "0" ]]; then
            for package in "${packages_to_install[@]}"; do
                log_info "Installing $package (user-level)..."
                if flatpak install -y flathub "$package" --user; then
                    log_success "Installed $package for user"
                else
                    log_error "Failed to install $package (user-level)"
                    status=1
                fi
            done
        fi
    else
        log_success "All Flatpak packages already installed"
    fi

    pop_context
    return "$status"
}

# Install Snap packages
install_packages_snap() {
    local packages=("$@")
    local packages_to_install=()

    # Check if snap is available
    if ! command_exists snap; then
        log "⚠ snap not found, cannot install Snap packages"
        return 1
    fi

    # Check which packages need to be installed
    for package in "${packages[@]}"; do
        if ! snap list | grep -q "^$package "; then
            packages_to_install+=("$package")
        else
            log "✓ $package (Snap) already installed"
        fi
    done

    if [ ${#packages_to_install[@]} -gt 0 ]; then
        log "→ Installing Snap packages: ${packages_to_install[*]}"
        if [[ $DRY_RUN == "0" ]]; then
            for package in "${packages_to_install[@]}"; do
                sudo snap install "$package" || log "⚠ Failed to install $package"
            done
        fi
        return 0
    else
        log "✓ All Snap packages already installed"
        return 0
    fi
}

show_summary() {
    local script_name="${1:-Script}"

    # Initialize tracking to ensure files exist
    init_error_tracking

    # Read errors and warnings from files
    local errors=()
    local warnings=()

    if [[ -f "$DOTFILES_ERRORS_FILE" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && errors+=("$line")
        done < "$DOTFILES_ERRORS_FILE"
    fi

    if [[ -f "$DOTFILES_WARNINGS_FILE" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && warnings+=("$line")
        done < "$DOTFILES_WARNINGS_FILE"
    fi

    echo ""
    echo "=========================================="
    echo "  $script_name Execution Summary"
    echo "=========================================="

    if [ ${#errors[@]} -eq 0 ] && [ ${#warnings[@]} -eq 0 ]; then
        echo "✅ Completed successfully with no errors or warnings!"
        cleanup_error_tracking
        return 0
    fi

    if [ ${#warnings[@]} -gt 0 ]; then
        echo ""
        echo "⚠️  WARNINGS (${#warnings[@]}):"
        echo "----------------------------------------"
        for warning in "${warnings[@]}"; do
            echo "  • $warning"
        done
    fi

    if [ ${#errors[@]} -gt 0 ]; then
        echo ""
        echo "❌ ERRORS (${#errors[@]}):"
        echo "----------------------------------------"
        for error in "${errors[@]}"; do
            echo "  • $error"
        done
        echo ""
        echo "❌ Script completed with ${#errors[@]} error(s)"
        cleanup_error_tracking
        return 1
    else
        echo ""
        echo "✅ Script completed successfully with ${#warnings[@]} warning(s)"
        cleanup_error_tracking
        return 0
    fi
}

# Clear all tracked errors and warnings (useful for testing)
clear_tracking() {
    cleanup_error_tracking
    init_error_tracking
    DOTFILES_CONTEXT_STACK=()
}

# Get error/warning counts
get_error_count() {
    init_error_tracking
    if [[ -f "$DOTFILES_ERRORS_FILE" ]]; then
        wc -l < "$DOTFILES_ERRORS_FILE" | tr -d ' '
    else
        echo "0"
    fi
}

get_warning_count() {
    init_error_tracking
    if [[ -f "$DOTFILES_WARNINGS_FILE" ]]; then
        wc -l < "$DOTFILES_WARNINGS_FILE" | tr -d ' '
    else
        echo "0"
    fi
}

# Timeshift Backup System
# =======================

# Global variables to track backup state across scripts
DOTFILES_BACKUP_CREATED="${DOTFILES_BACKUP_CREATED:-${TMPDIR:-/tmp}/dotfiles-backup-created}"
DOTFILES_BACKUP_CREATOR="${DOTFILES_BACKUP_CREATOR:-${TMPDIR:-/tmp}/dotfiles-backup-creator}"
DOTFILES_BACKUP_ID_FILE="${DOTFILES_BACKUP_ID_FILE:-${TMPDIR:-/tmp}/dotfiles-backup-id}"

# Check if Timeshift is available
check_timeshift_available() {
    if ! command_exists timeshift; then
        log_info "Timeshift command not found"
        return 1
    fi

    # Check if timeshift is configured by looking for config files
    if [[ ! -f "/etc/timeshift/timeshift.json" ]]; then
        log_info "Timeshift configuration file not found at /etc/timeshift/timeshift.json"
        return 1
    fi
}

# Configure Timeshift in btrfs mode when / is a btrfs @ subvolume.
# Other layouts need a chosen rsync destination, so they are left alone.
setup_timeshift_btrfs() {
    local config="/etc/timeshift/timeshift.json"
    local template="/etc/timeshift/default.json"
    local root_source device fs_uuid parent_uuid="" parent_name

    [[ -f "$config" ]] && return 0

    if [[ "$(findmnt -no FSTYPE / 2>/dev/null)" != "btrfs" ]]; then
        log_info "Root is not btrfs; configure Timeshift manually with sudo timeshift-gtk"
        return 1
    fi
    if [[ ",$(findmnt -no OPTIONS / 2>/dev/null)," != *",subvol=/@,"* ]]; then
        log_info "Root is not the btrfs @ subvolume; Timeshift btrfs mode needs @ and @home"
        return 1
    fi

    root_source="$(findmnt -no SOURCE / 2>/dev/null)"
    device="${root_source%%\[*}"
    fs_uuid="$(lsblk -dno UUID "$device" 2>/dev/null)"
    if [[ -z "$fs_uuid" ]]; then
        log_error "Could not read the filesystem UUID of $device"
        return 1
    fi
    if [[ "$(lsblk -dno TYPE "$device" 2>/dev/null)" == "crypt" ]]; then
        parent_name="$(lsblk -dno PKNAME "$device" 2>/dev/null)"
        [[ -n "$parent_name" ]] && parent_uuid="$(lsblk -dno UUID "/dev/$parent_name" 2>/dev/null)"
    fi

    if [[ $DRY_RUN != "0" ]]; then
        log "Would configure Timeshift btrfs snapshots on $device"
        return 0
    fi

    if [[ "${AUTO_BACKUP:-0}" != "1" && "${QUIET:-0}" != "1" ]]; then
        echo ""
        read -p "Timeshift is not configured. Set it up for btrfs snapshots on $device? [Y/n]: " -n 1 -r
        echo ""
        if [[ "${REPLY:-}" =~ ^[Nn]$ ]]; then
            log_info "Skipping Timeshift setup as requested"
            return 1
        fi
    fi

    if ! command_exists timeshift; then
        install_packages_pacman timeshift || return 1
    fi
    if ! command_exists jq; then
        install_packages_pacman jq || return 1
    fi
    if [[ ! -f "$template" ]]; then
        log_error "Timeshift template not found at $template"
        return 1
    fi

    local new_config
    if ! new_config="$(jq --arg uuid "$fs_uuid" --arg parent "$parent_uuid" \
        '.backup_device_uuid = $uuid | .parent_device_uuid = $parent | .btrfs_mode = "true" | .do_first_run = "false"' \
        "$template")"; then
        log_error "Failed to build Timeshift configuration from $template"
        return 1
    fi
    if ! printf '%s\n' "$new_config" | sudo tee "$config" >/dev/null || ! sudo chmod 644 "$config"; then
        log_error "Failed to write $config"
        return 1
    fi
    receipt_add_restore system "$(printf 'sudo rm -f -- %q' "$config")"

    log_success "Configured Timeshift btrfs snapshots on $device"
}

# Timeshift removes an interrupted btrfs snapshot (no info.json) file by file, which on a root
# snapshot takes long enough to look like a hang; delete those as whole subvolumes first.
remove_incomplete_timeshift_snapshots() {
    local config="/etc/timeshift/timeshift.json"
    local uuid mount_dir snapshot subvolume status=0

    command_exists jq || return 0
    [[ "$(jq -r '.btrfs_mode // ""' "$config" 2>/dev/null)" == "true" ]] || return 0
    uuid="$(jq -r '.backup_device_uuid // ""' "$config" 2>/dev/null)"
    [[ -n "$uuid" && -e "/dev/disk/by-uuid/$uuid" ]] || return 0
    # A running Timeshift's snapshot has no info.json until it finishes.
    pgrep -x timeshift >/dev/null && return 0

    mount_dir="$(mktemp -d)" || return 1
    if ! sudo mount -o subvolid=5 "/dev/disk/by-uuid/$uuid" "$mount_dir"; then
        rmdir "$mount_dir"
        return 1
    fi
    while IFS= read -r -d '' snapshot; do
        sudo test -f "$snapshot/info.json" && continue
        log_info "Deleting incomplete Timeshift snapshot ${snapshot##*/}"
        while IFS= read -r -d '' subvolume; do
            sudo btrfs subvolume delete "$subvolume" >/dev/null || status=1
        done < <(sudo find "$snapshot" -mindepth 1 -maxdepth 1 -type d -print0)
        sudo rmdir "$snapshot" || status=1
    done < <(sudo find "$mount_dir/timeshift-btrfs/snapshots" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    sudo umount "$mount_dir" && rmdir "$mount_dir"
    return "$status"
}

# Create a Timeshift backup before making system changes
create_dotfiles_backup() {
    local script_name="${1:-dotfiles}"

    # Check if backup was already created in this session
    if [[ -f "$DOTFILES_BACKUP_CREATED" ]]; then
        log_info "Timeshift backup already created in this session, skipping"
        return 0
    fi

    # Check if Timeshift is available and configured
    if ! check_timeshift_available && ! { setup_timeshift_btrfs && check_timeshift_available; }; then
        if [[ "${REQUIRE_BACKUP:-0}" == "1" ]]; then
            log_error "A high-risk module requires a configured Timeshift backup"
            return 1
        fi
        log_warn "Timeshift not available or not configured; continuing without a system backup"
        return 0
    fi

    push_context "Timeshift backup"

    log_info "Creating Timeshift backup before $script_name execution..."

    if [[ $DRY_RUN == "0" ]]; then
        # Ask for user confirmation unless --auto-backup is specified
        if [[ "${AUTO_BACKUP:-0}" != "1" ]]; then
            # In quiet mode, automatically create backup without prompting
            if [[ "${QUIET:-0}" == "1" ]]; then
                # Auto-create backup in quiet mode
                REPLY="Y"
            else
                echo ""
                echo "🛡️  System Backup Recommendation"
                echo "=================================="
                echo "It's recommended to create a Timeshift backup before making system changes."
                echo "This allows you to restore your system if anything goes wrong."
                echo ""
                read -p "Create Timeshift backup now? [Y/n]: " -n 1 -r
                echo ""
            fi

            if [[ "${REPLY:-}" =~ ^[Nn]$ ]]; then
                if [[ "${REQUIRE_BACKUP:-0}" == "1" ]]; then
                    log_error "A high-risk module cannot continue without a backup"
                    pop_context
                    return 1
                fi
                log_info "Skipping backup as requested"
                pop_context
                return 0
            fi
        fi

        # Create the backup with a descriptive comment
        local backup_comment="Pre-$script_name-$(date +%Y%m%d-%H%M%S)"
        log_info "Creating backup: $backup_comment"

        # Stream timeshift's output: a snapshot waiting on another timeshift's lock or
        # copying a large rsync delta otherwise looks like a hang.
        local timeshift_status
        remove_incomplete_timeshift_snapshots || log_warn "Could not delete every incomplete Timeshift snapshot; Timeshift will retry"
        sudo timeshift --create --comments "$backup_comment" --scripted 2>&1 | sed -u 's/^/    /'
        timeshift_status=${PIPESTATUS[0]}
        if ((timeshift_status == 0)); then
            log_success "Timeshift backup created successfully"
            # Mark that backup was created in this session and track who created it
            touch "$DOTFILES_BACKUP_CREATED"
            echo "$script_name" > "$DOTFILES_BACKUP_CREATOR"
            printf '%s\n' "$backup_comment" > "$DOTFILES_BACKUP_ID_FILE"
        else
            log_error "Failed to create Timeshift backup (exit $timeshift_status; output above)"
            if [[ "${REQUIRE_BACKUP:-0}" == "1" ]]; then
                pop_context
                return 1
            fi
            echo ""
            read -p "Continue without backup? [y/N]: " -n 1 -r
            echo ""

            if [[ ! "${REPLY:-}" =~ ^[Yy]$ ]]; then
                log_error "Aborting due to backup failure"
                exit 1
            fi
        fi
    else
        log "Would create Timeshift backup: Pre-$script_name-$(date +%Y%m%d-%H%M%S)"
        # In dry run, still create tracking files for deduplication testing
        touch "$DOTFILES_BACKUP_CREATED"
        echo "$script_name" > "$DOTFILES_BACKUP_CREATOR"
    fi

    pop_context
    return 0
}

# Cleanup backup tracking files
cleanup_backup_tracking() {
    rm -f "$DOTFILES_BACKUP_CREATED" "$DOTFILES_BACKUP_CREATOR" 2>/dev/null || true
}

# Cleanup backup tracking only if current script created the backup
cleanup_backup_tracking_if_owner() {
    local script_name="${1:-unknown}"
    
    if [[ -f "$DOTFILES_BACKUP_CREATOR" ]]; then
        local creator=$(cat "$DOTFILES_BACKUP_CREATOR" 2>/dev/null || echo "")
        if [[ "$creator" == "$script_name" ]]; then
            cleanup_backup_tracking
        fi
    fi
}

# Export functions for use in other scripts
export -f log log_error log_warn log_success log_info parse_args command_exists is_installed_pacman ensure_sudo
export -f init_error_tracking cleanup_error_tracking set_context push_context pop_context get_context show_summary clear_tracking get_error_count get_warning_count
export -f check_timeshift_available setup_timeshift_btrfs remove_incomplete_timeshift_snapshots create_dotfiles_backup cleanup_backup_tracking cleanup_backup_tracking_if_owner
export -f check_ssh_keys check_gpg_keys reload_hyprland reload_tmux
export -f install_packages_pacman install_packages_aur install_packages_flatpak install_packages_snap install_module_packages apply_module_services apply_module_groups apply_module_system_files
