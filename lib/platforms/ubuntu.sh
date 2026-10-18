#!/usr/bin/env bash

source "${DOTFILES_DIR:?DOTFILES_DIR must be set}/lib/platforms/common.sh"

dotfiles_platform_activate() {
    export DOTFILES_PLATFORM="ubuntu"
    export DOTFILES_DEFAULT_PACKAGE_SOURCE="apt"
    export DOTFILES_BOOTSTRAP_DIR="$DOTFILES_DIR/modules/packages"
}

# Package sources are "apt" for the Ubuntu archive or the name of a third-party repository
# declared in apt-repositories.list (name, key fingerprint, key URL, repository URL, suite, component).
platform_read_apt_repository() {
    local wanted="$1"
    local manifest="$DOTFILES_BOOTSTRAP_DIR/apt-repositories.list"
    local name fingerprint key_url url suite component extra

    [[ -f "$manifest" ]] || return 1
    while read -r name fingerprint key_url url suite component extra; do
        [[ -n "${name:-}" && "$name" != \#* ]] || continue
        [[ "$name" == "$wanted" ]] || continue
        apt_repository_fingerprint="$fingerprint"
        apt_repository_key_url="$key_url"
        apt_repository_url="$url"
        apt_repository_suite="$suite"
        apt_repository_component="$component"
        [[ -z "${extra:-}" && "$name" =~ ^[a-z0-9][a-z0-9-]*$ && "$fingerprint" =~ ^[0-9A-F]{40}$ \
            && "$key_url" == https://* && "$url" == https://* && -n "${suite:-}" && -n "${component:-}" ]]
        return
    done < "$manifest"
    return 1
}

platform_validate_package_source() {
    [[ "$1" == "apt" ]] || platform_read_apt_repository "$1"
}

platform_validate_bootstrap_manifests() {
    local manifest="$DOTFILES_BOOTSTRAP_DIR/apt-repositories.list"
    local name extra invalid=0

    [[ -f "$manifest" ]] || return 0
    while read -r name extra; do
        [[ -n "${name:-}" && "$name" != \#* ]] || continue
        if [[ "$name" == "apt" ]] || ! platform_read_apt_repository "$name"; then
            printf 'Invalid apt repository entry in %s: %s %s\n' "$manifest" "$name" "${extra:-}" >&2
            invalid=1
        fi
    done < "$manifest"
    ((invalid == 0))
}

platform_add_apt_repository() {
    local name="$1"
    local keyring="/etc/apt/keyrings/dotfiles-$name.gpg"
    local sources="/etc/apt/sources.list.d/dotfiles-$name.sources"
    local work_dir fingerprint

    platform_read_apt_repository "$name" || {
        log_error "Apt repository is not declared: $name"
        return 1
    }
    if [[ -f "$keyring" && -f "$sources" ]]; then
        return 0
    fi
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "Would add apt repository $name from $apt_repository_url (key $apt_repository_fingerprint)"
        return 0
    fi
    if [[ -z "${DOTFILES_RUN_DIR:-}" || -z "${DOTFILES_RECEIPT_DIR:-}" ]]; then
        log_error "Adding an apt repository requires the top-level runner and its recovery receipt"
        return 1
    fi
    if ! command_exists curl || ! command_exists gpg; then
        log_error "curl and gpg are required to add the apt repository $name"
        return 1
    fi

    work_dir="$(mktemp -d "$DOTFILES_RUN_DIR/apt-$name.XXXXXX")" || return 1
    mkdir -m 700 "$work_dir/gnupg" || return 1
    if ! curl -fsSL --proto '=https' -o "$work_dir/key" -- "$apt_repository_key_url"; then
        log_error "Failed to download the signing key for $name from $apt_repository_key_url"
        return 1
    fi
    # The primary key must be the pinned one, or the download is not the repository's key.
    fingerprint="$(GNUPGHOME="$work_dir/gnupg" gpg --batch --show-keys --with-colons "$work_dir/key" 2>/dev/null \
        | awk -F: '$1 == "fpr" { print $10; exit }')"
    if [[ "$fingerprint" != "$apt_repository_fingerprint" ]]; then
        log_error "Signing key for $name has fingerprint ${fingerprint:-unknown}, expected $apt_repository_fingerprint"
        return 1
    fi
    if ! GNUPGHOME="$work_dir/gnupg" gpg --batch --dearmor -o "$work_dir/keyring" "$work_dir/key"; then
        log_error "Failed to convert the signing key for $name"
        return 1
    fi
    printf 'Types: deb\nURIs: %s\nSuites: %s\nComponents: %s\nSigned-By: %s\n' \
        "$apt_repository_url" "$apt_repository_suite" "$apt_repository_component" "$keyring" > "$work_dir/sources"

    receipt_add_restore system "$(printf 'sudo rm -f -- %q %q' "$sources" "$keyring")" || return 1
    if ! sudo install -D -o root -g root -m 644 "$work_dir/keyring" "$keyring" \
        || ! sudo install -D -o root -g root -m 644 "$work_dir/sources" "$sources"; then
        log_error "Failed to install the apt repository $name"
        return 1
    fi
    apt_index_stale=1
    log_success "Added apt repository $name"
}

is_installed_apt() {
    [[ "$(dpkg-query -W -f='${db:Status-Status}' -- "$1" 2>/dev/null)" == "installed" ]]
}

install_packages_apt() {
    local package install_output
    local -a packages_to_install=()

    for package in "$@"; do
        is_installed_apt "$package" || packages_to_install+=("$package")
    done
    if ((${#packages_to_install[@]} == 0)); then
        log_success "Apt packages are installed: $*"
        return 0
    fi
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "Would install apt packages: ${packages_to_install[*]}"
        return 0
    fi

    # Refresh the package index once per run, and again after a repository is added.
    if [[ "${apt_index_stale:-1}" == "1" ]]; then
        if ! sudo apt-get update -q; then
            log_error "apt-get update failed"
            return 1
        fi
        apt_index_stale=0
    fi
    log_info "Installing apt packages: ${packages_to_install[*]}"
    if install_output=$(sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends -- "${packages_to_install[@]}" 2>&1); then
        log_success "Installed apt packages: ${packages_to_install[*]}"
    else
        printf '%s\n' "$install_output" >&2
        log_error "Failed to install apt packages: ${packages_to_install[*]}"
        return 1
    fi
}

platform_install_package_manifest() {
    local manifest="$1"
    local source package extra repository
    local -a apt_packages=()
    local -a repository_names=()
    local -A repository_packages=()
    local status=0

    [[ -f "$manifest" ]] || return 0
    while read -r source package extra; do
        [[ -n "${source:-}" && "$source" != \#* ]] || continue
        if [[ -n "${extra:-}" || ! "${package:-}" =~ ^[a-z0-9][a-z0-9@._+:-]*$ ]]; then
            log_error "Invalid package entry in $manifest: $source ${package:-} ${extra:-}"
            status=1
            continue
        fi
        if [[ "$source" == "apt" ]]; then
            apt_packages+=("$package")
        elif platform_read_apt_repository "$source"; then
            [[ -n "${repository_packages[$source]+set}" ]] || repository_names+=("$source")
            repository_packages["$source"]+="$package "
        else
            log_error "Unknown package source '$source' in $manifest"
            status=1
        fi
    done < "$manifest"

    # Archive packages first: they include curl and gpg, which adding a repository needs.
    if ((${#apt_packages[@]} > 0)); then
        install_packages_apt "${apt_packages[@]}" || status=1
    fi
    for repository in "${repository_names[@]}"; do
        if platform_add_apt_repository "$repository"; then
            read -r -a apt_packages <<< "${repository_packages[$repository]}"
            install_packages_apt "${apt_packages[@]}" || status=1
        else
            status=1
        fi
    done
    return "$status"
}

platform_list_installed_packages() {
    dpkg-query -W -f='${db:Status-Status} ${Package}\n' | awk '$1 == "installed" { print $2 }'
}

platform_list_explicit_repo_packages() {
    apt-mark showmanual
}

platform_list_explicit_foreign_packages() {
    :
}
