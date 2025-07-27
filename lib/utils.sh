#!/usr/bin/env bash

# Shared utilities for dotfiles scripts
# Source this file in other scripts: source "$DOTFILES_DIR/lib/utils.sh"

# Global dry run flag (can be overridden by individual scripts)
DRY_RUN="${DRY_RUN:-0}"

# Global quiet flag - when enabled, only show warnings and errors
QUIET="${QUIET:-0}"

# Error and Warning Tracking System (File-based for persistence across scripts)
# =============================================================================
# Use a consistent directory name that all scripts can share
DOTFILES_TEMP_DIR="${TMPDIR:-/tmp}/dotfiles-tracking"
DOTFILES_ERRORS_FILE="$DOTFILES_TEMP_DIR/errors.log"
DOTFILES_WARNINGS_FILE="$DOTFILES_TEMP_DIR/warnings.log"
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
    if sudo -v; then
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

# Check if package is installed (Arch)
is_installed_pacman() {
    pacman -Qi "$1" &> /dev/null
}

# Check if package is installed (Debian/Ubuntu)
is_installed_apt() {
    dpkg -l "$1" &> /dev/null
}

# Check SSH key setup
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
update_submodules() {
    local repo_dir="$1"

    if [[ ! -f "$repo_dir/.gitmodules" ]]; then
        log "→ No submodules found"
        return 0
    fi

    log "→ Initializing and updating git submodules..."
    if [[ $DRY_RUN == "0" ]]; then
        (
            cd "$repo_dir"

            # First, sync submodule URLs in case they changed
            git submodule sync --recursive 2>/dev/null || log "⚠ Failed to sync submodule URLs"

            # Initialize and update submodules
            if git submodule update --init --recursive 2>/dev/null; then
                log "✓ All submodules updated successfully"
            else
                log "⚠ Some submodules failed to update, trying individual updates..."

                # Try to update each submodule individually
                git submodule foreach --recursive '
                    echo "Updating submodule: $name"
                    if ! git submodule update --init; then
                        echo "⚠ Failed to update submodule: $name"
                        echo "→ You may need to check the repository URL or your SSH keys"
                    fi
                ' || true

                log "→ Submodule update completed with some warnings"
            fi
        ) || {
            log "⚠ Submodule update failed"
            log "→ This might be due to:"
            log "  - Network connectivity issues"
            log "  - SSH key not set up for private repositories"
            log "  - Repository URLs have changed"
            log "→ You can manually run: git submodule update --init --recursive"
            return 1
        }
    else
        log "Would sync and update all git submodules"
    fi
}

# Setup SSH keys from GitHub (like the original Windows script)
setup_github_ssh_keys() {
    local github_username="${GITHUB_USERNAME:-nick22985}"  # Default to your username
    local key_url="https://github.com/${github_username}.keys"
    local authorized_keys_file="$HOME/.ssh/authorized_keys"

    log "→ Downloading SSH keys from GitHub ($github_username)..."

    # Create .ssh directory if it doesn't exist
    if [[ $DRY_RUN == "0" ]]; then
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
    else
        log "Would create $HOME/.ssh directory"
    fi

    # Download keys from GitHub
    if [[ $DRY_RUN == "0" ]]; then
        if command_exists curl; then
            local keys_content
            keys_content=$(curl -s "$key_url" 2>/dev/null) || {
                log "⚠ Failed to download keys from $key_url"
                return 1
            }

            if [[ -z "$keys_content" ]]; then
                log "⚠ No keys found for user $github_username"
                return 1
            fi

            # Process each key
            local keys_added=0
            while IFS= read -r key; do
                key=$(echo "$key" | xargs)  # Trim whitespace
                if [[ -n "$key" ]]; then
                    # Check if key already exists
                    if [[ -f "$authorized_keys_file" ]] && grep -Fxq "$key" "$authorized_keys_file" 2>/dev/null; then
                        log "✓ Key already exists in authorized_keys"
                    else
                        echo "$key" >> "$authorized_keys_file"
                        log "✓ Added key to authorized_keys"
                        keys_added=$((keys_added + 1))
                    fi
                fi
            done <<< "$keys_content"

            if [[ $keys_added -gt 0 ]]; then
                chmod 600 "$authorized_keys_file"
                log "✓ Added $keys_added SSH key(s) from GitHub"
            else
                log "✓ All GitHub SSH keys already present"
            fi

        else
            log "⚠ curl not available, cannot download GitHub SSH keys"
            return 1
        fi
    else
        log "Would download SSH keys from $key_url"
        log "Would add keys to $authorized_keys_file"
    fi
}

# Check if Nerd Fonts are already installed
check_nerd_fonts_installed() {
    # Check if the Nerd Fonts directory exists and has fonts
    local fonts_dir="$HOME/.local/share/fonts/NerdFonts"
    [[ -d "$fonts_dir" ]] && [[ -n "$(find "$fonts_dir" -name "*.ttf" -o -name "*.otf" 2>/dev/null | head -1)" ]]
}

# Install Nerd Fonts from official repository
install_nerd_fonts() {
    local fonts_dir="$HOME/.local/share/fonts/NerdFonts"
    local nerd_fonts_repo="https://github.com/ryanoasis/nerd-fonts.git"
    local repo_dir="$HOME/.cache/nerd-fonts-repo"

    log "→ Installing ALL Nerd Fonts from official repository..."

    # Check if Nerd Fonts are already installed
    if check_nerd_fonts_installed; then
        log "✓ Nerd Fonts already installed (found in $fonts_dir)"
        return 0
    fi

    if [[ $DRY_RUN == "0" ]]; then
        # Create fonts directory
        mkdir -p "$fonts_dir"
        mkdir -p "$(dirname "$repo_dir")"

        # Check if we already have the repository
        if [[ -d "$repo_dir/.git" ]]; then
            log "→ Updating existing Nerd Fonts repository..."
            (
                cd "$repo_dir"
                # Check if we need to pull updates
                git fetch origin main 2>/dev/null || git fetch origin master 2>/dev/null || {
                    log "⚠ Failed to fetch updates, using existing repository"
                }

                # Get current and remote commit hashes
                local current_commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
                local remote_commit=$(git rev-parse @{u} 2>/dev/null || echo "unknown")

                if [[ "$current_commit" != "$remote_commit" ]] && [[ "$remote_commit" != "unknown" ]]; then
                    log "→ Repository has updates, pulling latest changes..."
                    git reset --hard @{u} 2>/dev/null || log "⚠ Failed to update repository"
                else
                    log "✓ Repository is up to date"
                fi
            ) || {
                log "⚠ Failed to update repository, re-cloning..."
                rm -rf "$repo_dir"
            }
        fi

        # Clone repository if we don't have it or update failed
        if [[ ! -d "$repo_dir/.git" ]]; then
            log "→ Cloning Nerd Fonts repository..."
            if ! git clone --depth 1 "$nerd_fonts_repo" "$repo_dir" 2>/dev/null; then
                log "⚠ Failed to clone Nerd Fonts repository"
                return 1
            fi
        fi

        # Install ALL fonts
        (
            cd "$repo_dir"
            log "→ Installing ALL Nerd Fonts (this will take a while)..."
            ./install.sh 2>/dev/null || log "⚠ Some fonts may have failed to install"
        ) || {
            log "⚠ Font installation failed"
            return 1
        }

        # Refresh font cache
        log "→ Refreshing font cache..."
        fc-cache -fv &> /dev/null || log "⚠ Failed to refresh font cache"

    else
        if [[ -d "$repo_dir/.git" ]]; then
            log "Would update existing repository at $repo_dir"
        else
            log "Would clone $nerd_fonts_repo to $repo_dir"
        fi
        log "Would install ALL Nerd Fonts"
        log "Would refresh font cache"
    fi

    log "✓ Nerd Fonts installation complete"
}

# Check if NVM is installed and working
check_nvm() {
    local nvm_dir="${NVM_DIR:-$HOME/.nvm}"

    if [[ -d "$nvm_dir" ]] && [[ -s "$nvm_dir/nvm.sh" ]]; then
        # Source NVM
        source "$nvm_dir/nvm.sh" 2>/dev/null

        if command_exists nvm; then
            local nvm_version=$(nvm --version 2>/dev/null || echo "unknown")
            log "✓ NVM $nvm_version is installed and working"

            # Show current Node version if available
            if command_exists node; then
                local node_version=$(node --version 2>/dev/null || echo "none")
                log "→ Current Node.js version: $node_version"
            fi
            return 0
        fi
    fi

    log "⚠ NVM not found or not working"
    log "→ Run './run nvm' to install NVM"
    return 1
}

# Check if Bun is installed and working
check_bun() {
    if command_exists bun; then
        local bun_version=$(bun --version 2>/dev/null || echo "unknown")
        log "✓ Bun $bun_version is installed and working"
        return 0
    fi

    log "⚠ Bun not found"
    log "→ Run './run nvm' to install Bun"
    return 1
}

# Check JavaScript runtimes
check_js_runtimes() {
    log "→ Checking JavaScript runtimes..."
    check_nvm
    check_bun
}

# Reload Hyprland configuration
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

# Package Manager Utility Functions
# ===================================

# Install packages using pacman (Arch Linux)
install_packages_pacman() {
    local packages=("$@")
    local packages_to_install=()

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
            # Try to install packages and capture output
            local install_output
            if install_output=$(sudo pacman -S --needed --noconfirm "${packages_to_install[@]}" 2>&1); then
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
                    # Format multi-line error output to be more readable
                    local formatted_error=$(echo "$install_output" | head -5 | tr '\n' '; ' | sed 's/; $//')
                    log_error "Package installation failed: $formatted_error"
                fi
                # Don't exit - continue execution and let summary show the error
            fi
        fi
    else
        log_success "All packages already installed"
    fi

    pop_context
    # Always return 0 to continue execution
    return 0
}

# Install packages using apt (Ubuntu/Debian)
install_packages_apt() {
    local packages=("$@")
    local packages_to_install=()

    push_context "apt packages"

    # Check which packages need to be installed
    for package in "${packages[@]}"; do
        if ! is_installed_apt "$package"; then
            packages_to_install+=("$package")
        else
            log_success "$package already installed"
        fi
    done

    if [ ${#packages_to_install[@]} -gt 0 ]; then
        log_info "Updating package list..."
        if [[ $DRY_RUN == "0" ]]; then
            if ! sudo apt update -qq; then
                log_warn "Failed to update package list"
            fi
        fi

        log_info "Installing packages: ${packages_to_install[*]}"
        if [[ $DRY_RUN == "0" ]]; then
            # Try to install packages and capture output
            local install_output
            if install_output=$(sudo apt install -y "${packages_to_install[@]}" 2>&1); then
                log_success "All packages installed successfully"
            else
                # Parse the output to find specific failed packages
                local failed_packages=()
                for package in "${packages_to_install[@]}"; do
                    if echo "$install_output" | grep -q "Unable to locate package $package"; then
                        failed_packages+=("$package")
                    fi
                done

                if [ ${#failed_packages[@]} -gt 0 ]; then
                    log_error "Failed to install packages: ${failed_packages[*]} (not found in repositories)"
                else
                    log_error "Package installation failed: $(echo "$install_output" | head -3 | tr '\n' ' ')"
                fi
                # Don't exit - continue execution and let summary show the error
            fi
        fi
    else
        log_success "All packages already installed"
    fi

    pop_context
    # Always return 0 to continue execution
    return 0
}

# Install AUR packages using paru
install_packages_aur() {
    local packages=("$@")
    local packages_to_install=()

    push_context "AUR packages"

    # Check if paru is available
    if ! command_exists paru; then
        log_error "paru not found, cannot install AUR packages"
        pop_context
        # Return 0 to continue execution - this is not a fatal error
        return 0
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
            # Try to install packages and capture output
            local install_output
            if install_output=$(paru -S --needed --noconfirm "${packages_to_install[@]}" 2>&1); then
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
                    log_error "AUR package installation failed: $(echo "$install_output" | head -3 | tr '\n' ' ')"
                fi
                # Don't exit - continue execution and let summary show the error
            fi
        fi
    else
        log_success "All AUR packages already installed"
    fi

    pop_context
    # Always return 0 to continue execution
    return 0
}

# Install packages using yay (alternative AUR helper)
install_packages_yay() {
    local packages=("$@")
    local packages_to_install=()

    # Check if yay is available
    if ! command_exists yay; then
        log "⚠ yay not found, cannot install AUR packages"
        return 1
    fi

    # Check which packages need to be installed
    for package in "${packages[@]}"; do
        if ! is_installed_pacman "$package"; then
            packages_to_install+=("$package")
        else
            log "✓ $package (AUR) already installed"
        fi
    done

    if [ ${#packages_to_install[@]} -gt 0 ]; then
        log "→ Installing AUR packages with yay: ${packages_to_install[*]}"
        if [[ $DRY_RUN == "0" ]]; then
            yay -S --needed --noconfirm "${packages_to_install[@]}" || log "⚠ Some AUR packages may have failed to install"
        fi
        return 0
    else
        log "✓ All AUR packages already installed"
        return 0
    fi
}

# Install Flatpak packages
install_packages_flatpak() {
    local packages=("$@")
    local packages_to_install=()

    push_context "Flatpak packages"

    # Check if flatpak is available
    if ! command_exists flatpak; then
        log_error "flatpak not found, cannot install Flatpak packages"
        pop_context
        return 1
    fi

    # Check which packages need to be installed
    for package in "${packages[@]}"; do
        if ! flatpak list --app | grep -q "$package"; then
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
                fi
            done
        fi
    else
        log_success "All Flatpak packages already installed"
    fi

    pop_context
    return 0
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

# Universal package installer - detects system and uses appropriate package manager
install_packages() {
    local packages=("$@")

    if command_exists pacman; then
        install_packages_pacman "${packages[@]}"
    elif command_exists apt; then
        install_packages_apt "${packages[@]}"
    else
        log "⚠ Unknown package manager. Please install packages manually: ${packages[*]}"
        return 1
    fi
}

# Install paru AUR helper
install_paru() {
    push_context "paru installation"

    if command_exists paru; then
        log_success "Paru already installed"
        pop_context
        return 0
    fi

    log_info "Installing paru (AUR helper)..."
    if [[ $DRY_RUN == "0" ]]; then
        # Clone and build paru
        temp_dir=$(mktemp -d)
        (
            cd "$temp_dir"
            git clone https://aur.archlinux.org/paru.git
            cd paru
            makepkg -si --noconfirm
        ) || {
            log_error "Failed to install paru"
            pop_context
            # Return 0 to continue execution - this is not fatal
            return 0
        }
        rm -rf "$temp_dir"
        log_success "Paru installed successfully"
    else
        log "Would clone and build paru from AUR"
    fi

    pop_context
    return 0
}

# Install yay AUR helper
install_yay() {
    if command_exists yay; then
        log "✓ Yay already installed"
        return 0
    fi

    log "→ Installing yay (AUR helper)..."
    if [[ $DRY_RUN == "0" ]]; then
        # Clone and build yay
        temp_dir=$(mktemp -d)
        (
            cd "$temp_dir"
            git clone https://aur.archlinux.org/yay.git
            cd yay
            makepkg -si --noconfirm
        ) || log "⚠ Failed to install yay"
        rm -rf "$temp_dir"
    else
        log "Would clone and build yay from AUR"
    fi
    log "✓ Yay installation complete"
}

# Setup package manager services (Docker, Bluetooth, etc.)
setup_package_services() {
    push_context "system services"

    if [[ $DRY_RUN == "0" ]]; then
        # Enable snapd if installed
        if is_installed_pacman "snapd" || command_exists snap; then
            log_info "Setting up Snap service..."
            if sudo systemctl enable --now snapd.socket 2>/dev/null; then
                log_success "Snap service enabled"
            else
                log_warn "Failed to enable snapd"
            fi
            sudo systemctl enable --now snapd.apparmor 2>/dev/null || true
            # Create snap symlink if it doesn't exist
            if [[ ! -e /snap ]]; then
                sudo ln -sf /var/lib/snapd/snap /snap 2>/dev/null || true
            fi
        fi

        # Enable docker if installed
        if is_installed_pacman "docker" || is_installed_apt "docker" || command_exists docker; then
            log_info "Setting up Docker service..."

            # Reload systemd daemon in case unit files changed
            sudo systemctl daemon-reload 2>/dev/null || true

            # Check if docker is already enabled and running
            if systemctl is-enabled docker.service >/dev/null 2>&1; then
                log_success "Docker service already enabled"
            else
                if sudo systemctl enable docker 2>/dev/null; then
                    log_success "Docker service enabled"
                else
                    log_warn "Failed to enable docker service"
                fi
            fi

            # Check if docker is running
            if systemctl is-active docker.service >/dev/null 2>&1; then
                log_success "Docker service is running"
            else
                if sudo systemctl start docker 2>/dev/null; then
                    log_success "Docker service started"
                else
                    log_warn "Failed to start docker service"
                fi
            fi

            # Add user to docker group
            if ! groups "$USER" | grep -q docker; then
                if sudo usermod -aG docker "$USER"; then
                    log_success "Added $USER to docker group"
                    log_info "Note: Log out and back in for docker group membership to take effect"
                else
                    log_warn "Failed to add user to docker group"
                fi
            else
                log_success "$USER already in docker group"
            fi
        fi

        # Enable bluetooth if installed
        if is_installed_pacman "bluez" || is_installed_apt "bluez"; then
            log_info "Setting up Bluetooth service..."

            # Reload systemd daemon in case unit files changed
            sudo systemctl daemon-reload 2>/dev/null || true

            # Check if bluetooth is already enabled and running
            if systemctl is-enabled bluetooth.service >/dev/null 2>&1; then
                log_success "Bluetooth service already enabled"
            else
                if sudo systemctl enable bluetooth.service 2>/dev/null; then
                    log_success "Bluetooth service enabled"
                else
                    log_warn "Failed to enable bluetooth service"
                fi
            fi

            # Check if bluetooth is running
            if systemctl is-active bluetooth.service >/dev/null 2>&1; then
                log_success "Bluetooth service is running"
            else
                if sudo systemctl start bluetooth.service 2>/dev/null; then
                    log_success "Bluetooth service started"
                else
                    log_warn "Failed to start bluetooth service"
                fi
            fi
        fi
    else
        log "Would enable snapd, docker, and bluetooth services"
        log "Would add user to docker group"
    fi

    pop_context
}

# Add user to system groups
add_user_to_groups() {
    local groups_to_add=("$@")
    local groups_added=()

    log "→ Adding user to system groups..."

    if [[ $DRY_RUN == "0" ]]; then
        for group in "${groups_to_add[@]}"; do
            if getent group "$group" >/dev/null 2>&1 && ! groups "$USER" | grep -q "$group"; then
                if sudo usermod -aG "$group" "$USER"; then
                    log "✓ Added $USER to $group group"
                    groups_added+=("$group")
                fi
            fi
        done

        # Reload user groups if any were added
        if [ ${#groups_added[@]} -gt 0 ]; then
            log "→ Groups added: ${groups_added[*]}"
            log "→ Note: Some services may require a full logout/login to work properly"
        fi
    else
        log "Would add user to groups: ${groups_to_add[*]}"
    fi
}

# Display summary of all errors and warnings
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
DOTFILES_BACKUP_CREATED="${TMPDIR:-/tmp}/dotfiles-backup-created"
DOTFILES_BACKUP_CREATOR="${TMPDIR:-/tmp}/dotfiles-backup-creator"

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

# Create a Timeshift backup before making system changes
create_dotfiles_backup() {
    local script_name="${1:-dotfiles}"

    # Check if backup was already created in this session
    if [[ -f "$DOTFILES_BACKUP_CREATED" ]]; then
        log_info "Timeshift backup already created in this session, skipping"
        return 0
    fi

    # Check if Timeshift is available and configured
    if ! check_timeshift_available; then
        log_warn "Timeshift not available or not configured - skipping backup"
        log "→ Install timeshift and configure it for automatic system backups"
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

            if [[ $REPLY =~ ^[Nn]$ ]]; then
                log_info "Skipping backup as requested"
                pop_context
                return 0
            fi
        fi

        # Create the backup with a descriptive comment
        local backup_comment="Pre-$script_name-$(date +%Y%m%d-%H%M%S)"
        log_info "Creating backup: $backup_comment"

        # Capture both stdout and stderr to see what's failing
        local timeshift_output
        if timeshift_output=$(sudo timeshift --create --comments "$backup_comment" --scripted 2>&1); then
            log_success "Timeshift backup created successfully"
            # Mark that backup was created in this session and track who created it
            touch "$DOTFILES_BACKUP_CREATED"
            echo "$script_name" > "$DOTFILES_BACKUP_CREATOR"
        else
            log_error "Failed to create Timeshift backup"
            log_error "Timeshift error: $timeshift_output"
            echo ""
            read -p "Continue without backup? [y/N]: " -n 1 -r
            echo ""

            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
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
export -f log log_error log_warn log_success log_info parse_args command_exists is_installed_pacman is_installed_apt ensure_sudo
export -f init_error_tracking cleanup_error_tracking set_context push_context pop_context get_context show_summary clear_tracking get_error_count get_warning_count
export -f check_timeshift_available create_dotfiles_backup cleanup_backup_tracking cleanup_backup_tracking_if_owner
export -f check_ssh_keys check_gpg_keys update_submodules setup_github_ssh_keys check_nerd_fonts_installed install_nerd_fonts check_nvm check_bun check_js_runtimes reload_hyprland
export -f install_packages_pacman install_packages_apt install_packages_aur install_packages_yay install_packages_flatpak install_packages_snap install_packages install_paru install_yay setup_package_services add_user_to_groups
