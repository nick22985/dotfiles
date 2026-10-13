#!/usr/bin/env bash

dotfiles_platform_activate() {
    export DOTFILES_PLATFORM="arch"
    export DOTFILES_PACKAGE_DIR="$DOTFILES_DIR/profiles/packages/arch"
    export DOTFILES_STAGE_PACKAGE_DIR="$DOTFILES_PACKAGE_DIR/stages"
    export DOTFILES_SERVICE_DIR="$DOTFILES_DIR/profiles/services/arch"
    export DOTFILES_GROUP_DIR="$DOTFILES_DIR/profiles/groups/arch"
    export DOTFILES_SYSTEM_FILE_DIR="$DOTFILES_DIR/profiles/files/arch"
    export DOTFILES_BOOTSTRAP_DIR="$DOTFILES_DIR/profiles/bootstrap/arch"
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
    local checkout_dir resolved_commit

    if command_exists paru && paru --version >/dev/null 2>&1; then
        log_success "Paru already installed"
        return 0
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

    if pacman -Qq paru-bin >/dev/null 2>&1; then
        # paru-bin conflicts with paru, and --noconfirm declines the removal prompt.
        if ! sudo pacman -Rdd --noconfirm paru-bin; then
            log_error "Failed to remove the broken paru-bin package"
            return 1
        fi
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
    # --rmdeps drops the pacman rust makedepend afterwards; mise owns the user toolchain.
    if ! (cd "$checkout_dir/repository" && makepkg -si --rmdeps --needed --noconfirm); then
        log_error "Failed to build and install $aur_helper_package"
        return 1
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
    printf 'sudo cp -a -- %q %q\n' "$backup" "$pacman_conf" >> "$DOTFILES_RECEIPT_DIR/restore-system.sh"

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

platform_enable_service() {
    local scope="$1"
    local unit="$2"
    local now="$3"
    local -a args=()

    [[ "$scope" == "user" ]] && args+=(--user)
    args+=(enable)
    [[ "$now" == "now" ]] && args+=(--now)
    args+=(-- "$unit")

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "Would run: systemctl ${args[*]}"
    elif [[ "$scope" == "system" ]]; then
        sudo systemctl "${args[@]}"
    else
        systemctl "${args[@]}"
    fi
}

platform_apply_service_manifest() {
    local stage="$1"
    local manifest="$DOTFILES_SERVICE_DIR/$stage.list"
    local scope action requirement unit extra service_status
    local status=0

    [[ -f "$manifest" ]] || return 0
    while read -r scope action requirement unit extra; do
        [[ -n "${scope:-}" && "$scope" != \#* ]] || continue
        if [[ -n "${extra:-}" || ! "$scope" =~ ^(system|user)$ \
            || ! "$action" =~ ^(enable|enable-now|start|restart)$ \
            || ! "$requirement" =~ ^(required|optional)$ \
            || ! "${unit:-}" =~ ^[A-Za-z0-9@_.:-]+\.(service|socket|timer|path)$ ]]; then
            log_error "Invalid service entry in $manifest"
            status=1
            continue
        fi

        service_status=0
        case "$action" in
            enable) platform_enable_service "$scope" "$unit" later || service_status=$? ;;
            enable-now) platform_enable_service "$scope" "$unit" now || service_status=$? ;;
            start)
                if [[ "$DRY_RUN" == "1" ]]; then
                    log_info "Would start $scope service $unit"
                elif [[ "$scope" == "system" ]]; then
                    sudo systemctl start -- "$unit" || service_status=$?
                else
                    systemctl --user start -- "$unit" || service_status=$?
                fi
                ;;
            restart)
                if [[ "$DRY_RUN" == "1" ]]; then
                    log_info "Would restart $scope service $unit"
                elif [[ "$scope" == "system" ]]; then
                    sudo systemctl restart -- "$unit" || service_status=$?
                else
                    systemctl --user restart -- "$unit" || service_status=$?
                fi
                ;;
        esac
        if ((service_status != 0)); then
            if [[ "$requirement" == "required" ]]; then
                log_error "Failed to apply required service $unit"
                status=1
            else
                log_warn "Could not apply optional service $unit"
            fi
        fi
    done < "$manifest"
    return "$status"
}

platform_add_user_to_group() {
    local group="$1"

    if id -nG "$USER" | tr ' ' '\n' | grep -Fxq -- "$group"; then
        log_success "$USER already belongs to $group"
    elif [[ "$DRY_RUN" == "1" ]]; then
        log_info "Would add $USER to group $group"
    else
        sudo usermod -aG "$group" -- "$USER"
    fi
}

platform_apply_group_manifest() {
    local stage="$1"
    local manifest="$DOTFILES_GROUP_DIR/$stage.list"
    local requirement group extra
    local status=0

    [[ -f "$manifest" ]] || return 0
    while read -r requirement group extra; do
        [[ -n "${requirement:-}" && "$requirement" != \#* ]] || continue
        if [[ -n "${extra:-}" || ! "$requirement" =~ ^(required|optional)$ \
            || ! "${group:-}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            log_error "Invalid group entry in $manifest"
            status=1
            continue
        fi
        if ! platform_add_user_to_group "$group"; then
            if [[ "$requirement" == "required" ]]; then
                log_error "Failed to add $USER to required group $group"
                status=1
            else
                log_warn "Could not add $USER to optional group $group"
            fi
        fi
    done < "$manifest"
    return "$status"
}

platform_apply_system_file_manifest() {
    local stage="$1"
    local manifest="$DOTFILES_SYSTEM_FILE_DIR/$stage.list"
    local mode source_path target extra source source_real target_real backup
    local status=0

    [[ -f "$manifest" ]] || return 0
    if [[ "$DRY_RUN" != "1" && -z "${DOTFILES_RECEIPT_DIR:-}" ]]; then
        log_error "System file installation requires the top-level runner and its recovery receipt"
        return 1
    fi
    while read -r mode source_path target extra; do
        [[ -n "${mode:-}" && "$mode" != \#* ]] || continue
        source="$DOTFILES_DIR/$source_path"
        source_real="$(realpath -m -- "$source")"
        target_real="$(realpath -m -- "$target")"
        if [[ -n "${extra:-}" || ! "$mode" =~ ^0?[0-7]{3}$ \
            || "$source_real" != "$DOTFILES_DIR"/* \
            || ! -f "$source" \
            || ( "$target_real" != /etc/* && "$target_real" != /usr/local/* ) ]]; then
            log_error "Invalid system file entry in $manifest"
            status=1
            continue
        fi

        if [[ -f "$target" ]] && cmp -s "$source" "$target" \
            && [[ "$(stat -c %a "$target")" == "${mode#0}" ]]; then
            log_success "$target is current"
            continue
        fi
        if [[ "$DRY_RUN" == "1" ]]; then
            log_info "Would install $source as $target with mode $mode"
            continue
        fi

        if [[ -e "$target" && -n "${DOTFILES_RECEIPT_DIR:-}" ]]; then
            backup="$DOTFILES_RECEIPT_DIR/backups/system$target"
            mkdir -p "$(dirname "$backup")"
            if ! sudo cp -a -- "$target" "$backup"; then
                log_error "Failed to back up $target"
                status=1
                continue
            fi
            printf 'sudo cp -a -- %q %q\n' \
                "$backup" "$target" >> "$DOTFILES_RECEIPT_DIR/restore-system.sh"
            chmod 700 "$DOTFILES_RECEIPT_DIR/restore-system.sh"
        elif [[ ! -e "$target" && -n "${DOTFILES_RECEIPT_DIR:-}" ]]; then
            printf 'sudo rm -f -- %q\n' "$target" >> "$DOTFILES_RECEIPT_DIR/restore-system.sh"
            chmod 700 "$DOTFILES_RECEIPT_DIR/restore-system.sh"
        fi

        if ! sudo install -D -o root -g root -m "$mode" "$source" "$target"; then
            log_error "Failed to install $target"
            status=1
        fi
    done < "$manifest"
    return "$status"
}
