#!/usr/bin/env bash

source "${DOTFILES_DIR:?DOTFILES_DIR must be set}/lib/platforms/common.sh"

dotfiles_platform_activate() {
    export DOTFILES_PLATFORM="arch"
    export DOTFILES_DEFAULT_PACKAGE_SOURCE="repo"
    export DOTFILES_BOOTSTRAP_DIR="$DOTFILES_DIR/modules/packages"
}

platform_validate_package_source() {
    [[ "$1" == "repo" || "$1" == "multilib" || "$1" == "aur" || "$1" == "group" ]]
}

platform_read_aur_helper_manifest() {
    local manifest="${1:-$DOTFILES_BOOTSTRAP_DIR/paru.conf}"
    local key value extra
    local saw_repository=0
    local saw_commit=0
    local saw_package=0
    local saw_mirror=0

    aur_helper_repository=""
    aur_helper_mirror=""
    aur_helper_commit=""
    aur_helper_package=""
    if [[ ! -f "$manifest" ]]; then
        printf 'AUR helper bootstrap manifest not found: %s\n' "$manifest" >&2
        return 1
    fi

    while read -r key value extra; do
        [[ -n "${key:-}" && "$key" != \#* ]] || continue
        if [[ -n "${extra:-}" || -z "${value:-}" ]]; then
            printf 'Invalid AUR helper bootstrap entry in %s\n' "$manifest" >&2
            return 1
        fi
        case "$key" in
            repository)
                ((saw_repository == 0)) || {
                    printf 'Duplicate repository in %s\n' "$manifest" >&2
                    return 1
                }
                aur_helper_repository="$value"
                saw_repository=1
                ;;
            commit)
                ((saw_commit == 0)) || {
                    printf 'Duplicate commit in %s\n' "$manifest" >&2
                    return 1
                }
                aur_helper_commit="$value"
                saw_commit=1
                ;;
            mirror)
                ((saw_mirror == 0)) || {
                    printf 'Duplicate mirror in %s\n' "$manifest" >&2
                    return 1
                }
                aur_helper_mirror="$value"
                saw_mirror=1
                ;;
            package)
                ((saw_package == 0)) || {
                    printf 'Duplicate package in %s\n' "$manifest" >&2
                    return 1
                }
                aur_helper_package="$value"
                saw_package=1
                ;;
            *)
                printf "Unknown AUR helper bootstrap key '%s' in %s\n" "$key" "$manifest" >&2
                return 1
                ;;
        esac
    done < "$manifest"

    if [[ "$aur_helper_repository" != "https://aur.archlinux.org/paru.git" \
        || ! "$aur_helper_commit" =~ ^[0-9a-f]{40}$ \
        || "$aur_helper_package" != "paru" \
        || ( -n "$aur_helper_mirror" && "$aur_helper_mirror" != "https://github.com/archlinux/aur.git" ) ]]; then
        printf 'Invalid or incomplete AUR helper bootstrap manifest: %s\n' "$manifest" >&2
        return 1
    fi
}

platform_validate_bootstrap_manifests() {
    platform_read_aur_helper_manifest
}

platform_install_aur_helper() {
    local checkout_dir resolved_commit key value dep built_package installed_before
    local -a build_deps=() missing_deps=() added_deps=() stale_helpers=()

    if command_exists paru && paru --version >/dev/null 2>&1; then
        log_success "Paru already installed"
        return 0
    fi
    if [[ "${aur_helper_bootstrap_failed:-0}" == "1" ]]; then
        log_error "Skipping AUR packages because the paru bootstrap already failed in this run"
        return 1
    fi
    platform_read_aur_helper_manifest || return 1
    if command_exists paru; then
        log_warn "Installed paru is broken (likely built against an older libalpm); rebuilding from source"
    fi

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "Would bootstrap $aur_helper_package at ${aur_helper_commit:0:12} from $aur_helper_repository"
        return 0
    fi
    if [[ -z "${DOTFILES_RUN_DIR:-}" ]]; then
        log_error "AUR helper bootstrap requires the top-level runner"
        return 1
    fi
    if ! command_exists git || ! command_exists makepkg; then
        log_error "git and makepkg are required to bootstrap paru"
        return 1
    fi

    # paru-bin (and its debug package) conflict with paru, and --noconfirm declines the removal prompt.
    mapfile -t stale_helpers < <(pacman -Qq paru-bin paru-bin-debug 2>/dev/null)
    if ((${#stale_helpers[@]} > 0)) && ! sudo pacman -Rdd --noconfirm -- "${stale_helpers[@]}"; then
        log_error "Failed to remove the broken paru-bin packages: ${stale_helpers[*]}"
        return 1
    fi

    checkout_dir="$(mktemp -d "$DOTFILES_RUN_DIR/paru.XXXXXX")" || return 1
    if ! git clone --no-checkout --quiet -- "$aur_helper_repository" "$checkout_dir/repository"; then
        rm -rf -- "$checkout_dir/repository"
        if [[ -z "$aur_helper_mirror" ]]; then
            log_error "Failed to clone the pinned paru bootstrap repository"
            return 1
        fi
        log_warn "AUR clone failed; trying the $aur_helper_package branch of $aur_helper_mirror"
        if ! git clone --no-checkout --quiet --single-branch --branch "$aur_helper_package" \
            -- "$aur_helper_mirror" "$checkout_dir/repository"; then
            log_error "Failed to clone the pinned paru bootstrap repository from the AUR or its mirror"
            return 1
        fi
    fi
    if ! git -C "$checkout_dir/repository" cat-file -e "$aur_helper_commit^{commit}" \
        || ! git -C "$checkout_dir/repository" checkout --detach --quiet "$aur_helper_commit"; then
        log_error "Pinned paru bootstrap commit is unavailable: $aur_helper_commit"
        return 1
    fi
    resolved_commit="$(git -C "$checkout_dir/repository" rev-parse HEAD)" || return 1
    if [[ "$resolved_commit" != "$aur_helper_commit" ]]; then
        log_error "Paru bootstrap checkout does not match its pinned commit"
        return 1
    fi
    # rustup without a toolchain still satisfies cargo for makepkg, then fails in prepare().
    # Rust is managed by mise now, so drop the toolchain-less package left by older runs.
    if pacman -Qq rustup >/dev/null 2>&1 && ! rustup show active-toolchain >/dev/null 2>&1; then
        log_info "Removing the toolchain-less rustup package so makepkg uses pacman's rust for the build"
        if ! sudo pacman -R --noconfirm rustup; then
            log_error "Failed to remove rustup; run 'rustup default stable' or remove it manually"
            return 1
        fi
        receipt_add_restore system 'sudo pacman -S --needed --noconfirm rustup'
    fi
    # pacman steps run through our sudo so the runner's cached credentials apply;
    # makepkg's own sudo calls prompt for the password again.
    while read -r key _ value; do
        case "$key" in
            depends|makedepends) build_deps+=("${value%%[<>=]*}") ;;
        esac
    done < "$checkout_dir/repository/.SRCINFO"
    for dep in "${build_deps[@]}"; do
        pacman -T "$dep" >/dev/null 2>&1 || missing_deps+=("$dep")
    done
    if ((${#missing_deps[@]} > 0)); then
        installed_before="$(pacman -Qq)"
        if ! sudo pacman -S --needed --asdeps --noconfirm -- "${missing_deps[@]}"; then
            aur_helper_bootstrap_failed=1
            log_error "Failed to install build dependencies for $aur_helper_package: ${missing_deps[*]}"
            return 1
        fi
        mapfile -t added_deps < <(comm -13 <(sort <<<"$installed_before") <(pacman -Qq | sort))
    fi
    built_package=""
    if (cd "$checkout_dir/repository" && PKGDEST="$checkout_dir/pkg" makepkg --noconfirm); then
        for built_package in "$checkout_dir/pkg/$aur_helper_package"-[0-9]*.pkg.tar.*; do
            [[ -f "$built_package" ]] && break
        done
    fi
    if [[ ! -f "$built_package" ]] || ! sudo pacman -U --needed --noconfirm -- "$built_package"; then
        aur_helper_bootstrap_failed=1
        log_error "Failed to build and install $aur_helper_package"
        return 1
    fi
    # Drop build-only deps (pacman's rust); mise owns the user toolchain.
    if ((${#added_deps[@]} > 0)) && ! sudo pacman -Rns --noconfirm -- "${added_deps[@]}"; then
        log_warn "Could not remove paru build dependencies: ${added_deps[*]}"
    fi
    if ! paru --version >/dev/null 2>&1; then
        log_error "$aur_helper_package installed without a working paru command"
        return 1
    fi
    log_success "Installed $aur_helper_package from pinned commit ${aur_helper_commit:0:12}"
}

platform_enable_multilib() {
    local pacman_conf="/etc/pacman.conf"
    local backup

    if pacman-conf --repo-list 2>/dev/null | grep -Fxq multilib; then
        return 0
    fi
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "Would enable the multilib repository in $pacman_conf"
        return 0
    fi
    if [[ -z "${DOTFILES_RECEIPT_DIR:-}" ]]; then
        log_error "Enabling multilib requires the top-level runner and its recovery receipt"
        return 1
    fi
    if ! grep -Eq '^#[[:space:]]*\[multilib\][[:space:]]*$' "$pacman_conf"; then
        log_error "No commented [multilib] section found in $pacman_conf; enable it manually"
        return 1
    fi

    backup="$DOTFILES_RECEIPT_DIR/backups/system$pacman_conf"
    mkdir -p "$(dirname "$backup")"
    if ! sudo cp -a -- "$pacman_conf" "$backup"; then
        log_error "Failed to back up $pacman_conf"
        return 1
    fi
    receipt_add_restore system "$(printf 'sudo cp -a -- %q %q' "$backup" "$pacman_conf")" || return 1

    if ! sudo sed -i -E '/^#[[:space:]]*\[multilib\][[:space:]]*$/{s/^#[[:space:]]*//;n;s/^#[[:space:]]*(Include)/\1/}' "$pacman_conf"; then
        log_error "Failed to enable multilib in $pacman_conf"
        return 1
    fi
    if ! pacman-conf --repo-list 2>/dev/null | grep -Fxq multilib; then
        log_error "multilib is still disabled after editing $pacman_conf"
        return 1
    fi
    # A sync without the matching upgrade would leave a partial upgrade.
    if ! sudo pacman -Syu --noconfirm; then
        log_error "Failed to sync and upgrade after enabling multilib"
        return 1
    fi
    log_success "Enabled the multilib repository"
}

# pacman --noconfirm answers "Remove <old>? [y/N]" with no, so swap known
# conflicting providers explicitly before installing their replacements.
platform_replace_conflicting_packages() {
    local package old
    local status=0

    for package in "$@"; do
        case "$package" in
            pipewire-jack) old="jack2" ;;
            *) continue ;;
        esac
        pacman -Qq "$package" >/dev/null 2>&1 && continue
        pacman -Qq "$old" >/dev/null 2>&1 || continue
        if [[ "$DRY_RUN" == "1" ]]; then
            log_info "Would replace $old with $package"
            continue
        fi
        log_info "Replacing $old with $package"
        if ! sudo pacman -Rdd --noconfirm -- "$old"; then
            log_error "Failed to remove $old before installing $package"
            status=1
        fi
    done
    return "$status"
}

platform_install_package_manifest() {
    local manifest="$1"
    local source package extra
    local -a repo_packages=()
    local -a multilib_packages=()
    local -a aur_packages=()
    local -a group_packages=()
    local aur_helper_requested=0
    local status=0

    [[ -f "$manifest" ]] || return 0
    while read -r source package extra; do
        [[ -n "${source:-}" && "$source" != \#* ]] || continue
        if [[ -n "${extra:-}" || ! "${package:-}" =~ ^[a-z0-9][a-z0-9@._+:-]*$ ]]; then
            log_error "Invalid package entry in $manifest: $source ${package:-} ${extra:-}"
            status=1
            continue
        fi
        case "$source" in
            repo) repo_packages+=("$package") ;;
            multilib) multilib_packages+=("$package") ;;
            group)
                if mapfile -t group_packages < <(pacman -Sgq -- "$package") \
                    && ((${#group_packages[@]} > 0)); then
                    repo_packages+=("${group_packages[@]}")
                else
                    log_error "Package group is unavailable or empty: $package"
                    status=1
                fi
                ;;
            aur)
                if [[ "$package" == "paru" ]]; then
                    aur_helper_requested=1
                else
                    aur_packages+=("$package")
                fi
                ;;
            *) log_error "Unknown package source '$source' in $manifest"; status=1 ;;
        esac
    done < "$manifest"

    if ((${#multilib_packages[@]} > 0)); then
        if platform_enable_multilib; then
            repo_packages+=("${multilib_packages[@]}")
        else
            status=1
        fi
    fi
    if ((${#repo_packages[@]} > 0)); then
        platform_replace_conflicting_packages "${repo_packages[@]}" || status=1
        install_packages_pacman "${repo_packages[@]}" || status=1
    fi
    if ((aur_helper_requested == 1 || ${#aur_packages[@]} > 0)); then
        if platform_install_aur_helper; then
            if ((${#aur_packages[@]} > 0)); then
                install_packages_aur "${aur_packages[@]}" || status=1
            fi
        else
            status=1
        fi
    fi
    return "$status"
}

platform_list_installed_packages() {
    pacman -Qq
}

platform_list_explicit_repo_packages() {
    pacman -Qqen
}

platform_list_explicit_foreign_packages() {
    pacman -Qqem
}
