#!/usr/bin/env bash

# systemd services, groups, system files and the shared package lists work the same on every
# supported platform.

# A module's per-platform list, e.g. modules/docker/services.arch.list.
module_platform_list() {
    printf '%s/modules/%s/%s.%s.list\n' "$DOTFILES_DIR" "$1" "$2" "$DOTFILES_PLATFORM"
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
    local module="$1"
    local manifest
    manifest="$(module_platform_list "$module" services)"
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
    local module="$1"
    local manifest
    manifest="$(module_platform_list "$module" groups)"
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
    local module="$1"
    local manifest module_dir="$DOTFILES_DIR/modules/$module"
    manifest="$(module_platform_list "$module" files)"
    local mode source_path target extra source source_real target_real backup
    local status=0

    [[ -f "$manifest" ]] || return 0
    if [[ "$DRY_RUN" != "1" && -z "${DOTFILES_RECEIPT_DIR:-}" ]]; then
        log_error "System file installation requires the top-level runner and its recovery receipt"
        return 1
    fi
    while read -r mode source_path target extra; do
        [[ -n "${mode:-}" && "$mode" != \#* ]] || continue
        source="$module_dir/$source_path"
        source_real="$(realpath -m -- "$source")"
        target_real="$(realpath -m -- "$target")"
        if [[ -n "${extra:-}" || ! "$mode" =~ ^0?[0-7]{3}$ \
            || "$source_real" != "$module_dir"/* \
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
            receipt_add_restore system "$(printf 'sudo cp -a -- %q %q' "$backup" "$target")"
        elif [[ ! -e "$target" ]]; then
            receipt_add_restore system "$(printf 'sudo rm -f -- %q' "$target")"
        fi

        if ! sudo install -D -o root -g root -m "$mode" "$source" "$target"; then
            log_error "Failed to install $target"
            status=1
        fi
    done < "$manifest"
    return "$status"
}

# packages.list (in a profile or module directory) is a table. Its first line names the columns,
# "package" and then the platforms the list covers (package arch ubuntu windows), and each row has a
# cell per platform: "=" installs the package name from the platform's default source, "name" installs
# another name from it, "source:name" picks the source too, and "-" leaves it out. A platform without a
# column installs nothing from the list. Prints this platform's "source package" entries.
platform_resolve_package_table() {
    local manifest="$1"
    local -a header=() fields=()
    local -A seen=()
    local column=0 index cell source package status=0

    [[ -f "$manifest" ]] || return 0
    while read -r -a fields; do
        [[ ${#fields[@]} -gt 0 && "${fields[0]}" != \#* ]] || continue
        if ((${#header[@]} == 0)); then
            header=("${fields[@]}")
            if [[ "${header[0]}" != "package" || ${#header[@]} -lt 2 ]]; then
                printf 'Package table %s must start with a "package <platform>..." header\n' "$manifest" >&2
                return 1
            fi
            for ((index = 1; index < ${#header[@]}; index++)); do
                if [[ ! "${header[index]}" =~ ^(arch|ubuntu|windows)$ || -n "${seen[${header[index]}]+set}" ]]; then
                    printf 'Invalid platform column in %s: %s\n' "$manifest" "${header[index]}" >&2
                    return 1
                fi
                seen["${header[index]}"]=1
                [[ "${header[index]}" != "$DOTFILES_PLATFORM" ]] || column="$index"
            done
            continue
        fi
        if ((${#fields[@]} != ${#header[@]})) || [[ ! "${fields[0]}" =~ ^[a-z0-9][a-z0-9@._+-]*$ ]]; then
            printf 'Invalid package row in %s (expected %s cells): %s\n' "$manifest" "${#header[@]}" "${fields[*]}" >&2
            status=1
            continue
        fi
        for cell in "${fields[@]:1}"; do
            if [[ ! "$cell" =~ ^(=|-|([a-z]+:)?[A-Za-z0-9][A-Za-z0-9@._+:-]*)$ ]]; then
                printf 'Invalid package cell in %s: %s (row %s)\n' "$manifest" "$cell" "${fields[0]}" >&2
                status=1
                continue 2
            fi
        done
        ((column > 0)) || continue
        cell="${fields[column]}"
        [[ "$cell" != "-" ]] || continue
        [[ "$cell" != "=" ]] || cell="${fields[0]}"
        source="$DOTFILES_DEFAULT_PACKAGE_SOURCE"
        package="$cell"
        if [[ "$cell" == *:* ]]; then
            source="${cell%%:*}"
            package="${cell#*:}"
        fi
        if ! platform_validate_package_source "$source"; then
            printf "Unknown package source '%s' in %s (row %s)\n" "$source" "$manifest" "${fields[0]}" >&2
            status=1
            continue
        fi
        printf '%s %s\n' "$source" "$package"
    done < "$manifest"
    return "$status"
}

package_list_exists() {
    [[ -f "$1/packages.list" ]]
}

# Prints the "source package" entries a profile or module directory's table has for this platform.
package_list_entries() {
    platform_resolve_package_table "$1/packages.list"
}

install_package_list() {
    local resolved status=0

    resolved="$(mktemp)" || return 1
    package_list_entries "$1" > "$resolved" || status=1
    if [[ -s "$resolved" ]]; then
        platform_install_package_manifest "$resolved" || status=1
    fi
    rm -f -- "$resolved"
    return "$status"
}
