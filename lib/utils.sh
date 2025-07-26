#!/usr/bin/env bash

# Shared utilities for dotfiles scripts
# Source this file in other scripts: source "$DOTFILES_DIR/lib/utils.sh"

# Global dry run flag (can be overridden by individual scripts)
DRY_RUN="${DRY_RUN:-0}"

# Shared logging function
log() {
    if [[ $DRY_RUN == "1" ]]; then
        echo "[DRY_RUN]: $1"
    else
        echo "$1"
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

# Parse common arguments (--dry flag)
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry)
                DRY_RUN="1"
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

    if [[ -d "$ssh_dir" ]]; then
        # Check for common SSH key types
        for key_type in id_rsa id_ed25519 id_ecdsa; do
            if [[ -f "$ssh_dir/$key_type" ]]; then
                log "✓ Found SSH key: $key_type"
                has_keys=true
            fi
        done
    fi

    if [[ $has_keys == false ]]; then
        log "⚠ No SSH keys found in $ssh_dir"
        log "→ Generate SSH key with: ssh-keygen -t ed25519 -C 'your.email@example.com'"
        log "→ Add to GitHub: cat ~/.ssh/id_ed25519.pub"
    fi

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

# Export functions for use in other scripts
export -f log parse_args command_exists is_installed_pacman is_installed_apt ensure_sudo
export -f check_ssh_keys check_gpg_keys update_submodules setup_github_ssh_keys check_nerd_fonts_installed install_nerd_fonts check_nvm check_bun check_js_runtimes reload_hyprland
