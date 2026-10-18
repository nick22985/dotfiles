#!/usr/bin/env bash

dotfile_profile_dir="${DOTFILES_DIR:?DOTFILES_DIR must be set}/profiles"
dotfile_source_dir="${DOTFILES_ENV_DIR:-$DOTFILES_DIR/env}"

dotfile_bundle_names() {
    local profile
    local -A emitted=()
    local -a profiles=(core)

    if [[ -n "${DOTFILES_ACTIVE_PROFILES:-}" ]]; then
        read -r -a profiles <<< "$DOTFILES_ACTIVE_PROFILES ${DOTFILES_DESKTOP_PROFILES:-}"
    fi
    for profile in "${profiles[@]}"; do
        [[ -f "$dotfile_profile_dir/$profile/dotfiles.list" ]] || continue
        [[ -n "${emitted[$profile]+set}" ]] && continue
        emitted["$profile"]=1
        printf '%s\n' "$profile"
    done
}

dotfile_manifest_paths() {
    local bundle manifest path

    while IFS= read -r bundle; do
        manifest="$dotfile_profile_dir/$bundle/dotfiles.list"
        while IFS= read -r path || [[ -n "$path" ]]; do
            path="${path%%#*}"
            path="${path#"${path%%[![:space:]]*}"}"
            path="${path%"${path##*[![:space:]]}"}"
            [[ -n "$path" ]] && printf '%s\n' "$path"
        done < "$manifest"
    done < <(dotfile_bundle_names)
}

dotfile_deploy_paths() {
    local path source source_file relative

    while IFS= read -r path; do
        source="$dotfile_source_dir/$path"
        if [[ -f "$source" || -L "$source" ]]; then
            printf '%s\n' "$path"
            continue
        fi
        # Nested repositories (submodules) are linked whole: their .git files hold
        # relative gitdir paths that only resolve from inside the repository.
        # Docker build contexts are linked whole too: BuildKit refuses symlinks
        # that point outside the context, so a per-file link to the Dockerfile fails.
        # This covers a declared path that is itself one (e.g. .config/nvim).
        if [[ ! -d "$source" || -e "$source/.git" || -e "$source/Dockerfile" ]]; then
            printf '%s\n' "$path"
            continue
        fi
        while IFS= read -r -d '' source_file; do
            relative="${source_file#"$source"/}"
            [[ "$relative" == .git || "$relative" == .git/* ]] && continue
            printf '%s/%s\n' "$path" "$relative"
        done < <(find "$source" -mindepth 1 \
            \( -type d \( -exec test -e '{}/.git' \; -o -exec test -e '{}/Dockerfile' \; \) -prune -print0 \) \
            -o \( -type f -o -type l \) -print0)
    done < <(dotfile_manifest_paths)
}

validate_dotfile_path() {
    local path="$1"
    [[ "$path" != /* && "$path" != *$'\n'* && "$path" != ".." \
        && "$path" != ../* && "$path" != */../* && "$path" != */.. ]]
}

deploy_dotfile_bundles() {
    local path source target source_real target_real backup backup_parent
    local receipt_dir="${DOTFILES_RECEIPT_DIR:-}"
    local status=0

    if [[ "$DRY_RUN" != "1" && -z "$receipt_dir" ]]; then
        log_error "Dotfile deployment requires the top-level runner and its recovery receipt"
        return 1
    fi

    while IFS= read -r path; do
        backup=""
        if ! validate_dotfile_path "$path"; then
            log_error "Invalid dotfile path: $path"
            status=1
            continue
        fi
        source="$dotfile_source_dir/$path"
        target="$HOME/$path"
        if [[ ! -e "$source" && ! -L "$source" ]]; then
            log_error "Declared dotfile source does not exist: $source"
            status=1
            continue
        fi
        source_real="$(realpath -m -- "$source")"
        target_real="$(realpath -m -- "$target")"
        if [[ "$source_real" == "$target_real" ]]; then
            log_success "$target is current"
            continue
        fi

        if [[ "$DRY_RUN" == "1" ]]; then
            if [[ -e "$target" || -L "$target" ]]; then
                log_info "Would back up and replace $target"
            else
                log_info "Would link $target to $source"
            fi
            continue
        fi

        if [[ -e "$target" || -L "$target" ]]; then
            if [[ -z "$receipt_dir" ]]; then
                log_error "Cannot replace $target without a run receipt backup directory"
                status=1
                continue
            fi
            backup="$receipt_dir/backups/user/$path"
            backup_parent="$(dirname "$backup")"
            mkdir -p "$backup_parent"
            if ! mv -- "$target" "$backup"; then
                log_error "Failed to back up $target"
                status=1
                continue
            fi
        fi

        mkdir -p "$(dirname "$target")"
        if ! ln -s -- "$source" "$target"; then
            log_error "Failed to link $target"
            if [[ -n "$backup" ]]; then
                mv -- "$backup" "$target" \
                    || log_error "Failed to restore $target after link failure"
            fi
            status=1
        elif [[ -n "$backup" ]]; then
            receipt_add_restore user "$(printf 'rm -f -- %q\nmkdir -p %q\nmv -- %q %q' \
                "$target" "$(dirname "$target")" "$backup" "$target")"
        else
            receipt_add_restore user "$(printf 'rm -f -- %q' "$target")"
        fi
    done < <(dotfile_deploy_paths | sort -u)

    return "$status"
}
