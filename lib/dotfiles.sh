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

merge_untracked_dotfile_entries() {
    local target="$1" source="$2" relative="${3:-}"
    local entry name

    if [[ ! -r "$target/$relative" || ! -x "$target/$relative" ]]; then
        log_error "Cannot read $target/$relative to merge it into $source/$relative"
        return 1
    fi
    while IFS= read -r -d '' entry; do
        name="$relative${entry##*/}"
        if [[ ! -e "$source/$name" && ! -L "$source/$name" ]]; then
            if [[ "$(stat -c %d -- "$entry")" != "$(stat -c %d -- "$source/$relative")" ]]; then
                log_error "Cannot move untracked $target/$name into $source/$name: they are on different filesystems"
                return 1
            fi
            if [[ "$DRY_RUN" == "1" ]]; then
                log_info "Would move untracked $target/$name into $source/$name"
            elif ! mv -n -- "$entry" "$source/$name" || [[ -e "$entry" || -L "$entry" ]]; then
                log_error "Failed to move untracked $target/$name into $source/$name"
                return 1
            fi
            dotfile_merged_entries+=("$name")
        elif [[ -d "$entry" && ! -L "$entry" && -d "$source/$name" && ! -L "$source/$name" ]]; then
            merge_untracked_dotfile_entries "$target" "$source" "$name/" || return 1
        elif [[ ! -f "$entry" || -L "$entry" ]] || ! cmp -s -- "$entry" "$source/$name"; then
            dotfile_shadowed_count=$((dotfile_shadowed_count + 1))
        fi
    done < <(find "$target/$relative" -mindepth 1 -maxdepth 1 -print0)
}

unmerge_untracked_dotfile_entries() {
    local target="$1" source="$2" index name

    for ((index = ${#dotfile_merged_entries[@]} - 1; index >= 0; index--)); do
        name="${dotfile_merged_entries[index]}"
        mv -n -- "$source/$name" "$target/$name" \
            || log_error "Failed to move $source/$name back to $target/$name"
    done
}

deploy_dotfile_bundles() {
    local path source target source_real target_real backup backup_parent restore name
    local receipt_dir="${DOTFILES_RECEIPT_DIR:-}"
    local status=0 current_count=0

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
        # -ef is a builtin, so the thousands of already-linked files cost no subprocesses.
        if [[ "$target" -ef "$source" ]]; then
            current_count=$((current_count + 1))
            continue
        fi
        source_real="$(realpath -m -- "$source")"
        target_real="$(realpath -m -- "$target")"
        if [[ "$source_real" == "$target_real" ]]; then
            current_count=$((current_count + 1))
            continue
        fi

        if [[ -e "$target" || -L "$target" ]] && [[ -z "$receipt_dir" && "$DRY_RUN" != "1" ]]; then
            log_error "Cannot replace $target without a run receipt backup directory"
            status=1
            continue
        fi

        dotfile_merged_entries=()
        dotfile_shadowed_count=0
        if [[ -d "$target" && ! -L "$target" && -d "$source" ]] \
            && ! merge_untracked_dotfile_entries "$target" "$source"; then
            unmerge_untracked_dotfile_entries "$target" "$source"
            log_error "Left $target in place because its untracked entries could not be moved into $source; merge them by hand and rerun"
            status=1
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

        if (( ${#dotfile_merged_entries[@]} > 0 )); then
            log_info "Moved ${#dotfile_merged_entries[@]} untracked entries of $target into $source"
        fi
        if [[ -e "$target" || -L "$target" ]]; then
            backup="$receipt_dir/backups/user/$path"
            backup_parent="$(dirname "$backup")"
            mkdir -p "$backup_parent"
            if ! mv -- "$target" "$backup"; then
                log_error "Failed to back up $target"
                unmerge_untracked_dotfile_entries "$target" "$source"
                status=1
                continue
            fi
        fi
        if (( dotfile_shadowed_count > 0 )); then
            log_warn "$dotfile_shadowed_count entries of $target differ from $source; their old copies are in $backup"
        fi

        mkdir -p "$(dirname "$target")"
        if ! ln -s -- "$source" "$target"; then
            log_error "Failed to link $target"
            if [[ -n "$backup" ]]; then
                mv -- "$backup" "$target" \
                    || log_error "Failed to restore $target after link failure"
                unmerge_untracked_dotfile_entries "$target" "$source"
            fi
            status=1
        elif [[ -n "$backup" ]]; then
            restore="$(printf 'rm -f -- %q\nmkdir -p %q\nmv -- %q %q' \
                "$target" "$(dirname "$target")" "$backup" "$target")"
            for name in "${dotfile_merged_entries[@]}"; do
                restore+=$'\n'"$(printf 'mv -n -- %q %q' "$source/$name" "$target/$name")"
            done
            receipt_add_restore user "$restore"
        else
            receipt_add_restore user "$(printf 'rm -f -- %q' "$target")"
        fi
    done < <(dotfile_deploy_paths | sort -u)

    log_success "$current_count dotfiles already linked"
    return "$status"
}
