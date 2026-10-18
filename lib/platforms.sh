#!/usr/bin/env bash

platform_detect() {
    if command -v pacman >/dev/null 2>&1; then
        printf 'arch\n'
    elif command -v apt-get >/dev/null 2>&1 && [[ "$(. /etc/os-release 2>/dev/null && printf '%s' "${ID:-}")" == "ubuntu" ]]; then
        printf 'ubuntu\n'
    else
        printf 'unsupported\n'
    fi
}

platform_activate() {
    local platform="$1"
    local backend="${DOTFILES_DIR:?DOTFILES_DIR must be set}/lib/platforms/$platform.sh"

    [[ -f "$backend" ]] || {
        printf 'Platform backend not found: %s\n' "$backend" >&2
        return 2
    }
    source "$backend"
    dotfiles_platform_activate
}
