#!/usr/bin/env bash

# Shared installer profile resolution for the runner and its audit command.

source "${DOTFILES_DIR:?DOTFILES_DIR must be set}/lib/platforms.sh"

profile_dir="${DOTFILES_DIR:?DOTFILES_DIR must be set}/profiles"
host_profile_dir="$DOTFILES_DIR/hosts"
default_profile_file="$host_profile_dir/default.conf"
# The preset this machine uses when no selection is given; kept outside the repository so synced checkouts can differ.
machine_host_file="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/host"
machine_host_name=""
profile_mode=0
desktop_profile="hyprland"
desktop_profile_explicit=0
requested_platform=""
export DOTFILES_PROFILE_MODE=0
export DOTFILES_ACTIVE_PROFILES=""
export DOTFILES_DESKTOP="$desktop_profile"
export DOTFILES_DESKTOP_PROFILES=""
export DOTFILES_PLATFORM=""
declare -a requested_profiles=()
declare -a resolved_profiles=()
declare -a resolved_desktop_profiles=()
declare -a resolved_profile_runs=()
declare -a requested_skips=()
declare -A loaded_host_presets=()
declare -A expanded_profiles=()

# profiles/<name>/profile.conf holds "key value" lines: description, platforms (omitted for every
# platform), include <profile>, module <module>, and for a desktop variant "desktop <selection>"
# (picked by --desktop, not --profile).
profile_conf_value() {
    local profile="$1"
    local wanted="$2"
    local key value

    while read -r key value; do
        if [[ "$key" == "$wanted" ]]; then
            printf '%s\n' "$value"
        fi
    done < "$profile_dir/$profile/profile.conf"
}

profile_supports_platform() {
    local platforms
    platforms="$(profile_conf_value "$1" platforms)"
    [[ -z "$platforms" || " $platforms " == *" $2 "* ]]
}

profile_names() {
    local conf
    for conf in "$profile_dir"/*/profile.conf; do
        [[ -f "$conf" ]] || continue
        conf="${conf%/profile.conf}"
        printf '%s\n' "${conf##*/}"
    done
}

profile_is_selectable() {
    [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ && -f "$profile_dir/$1/profile.conf" && -z "$(profile_conf_value "$1" desktop)" ]]
}

profile_selectable_names() {
    local profile
    while IFS= read -r profile; do
        if profile_is_selectable "$profile"; then
            printf '%s\n' "$profile"
        fi
    done < <(profile_names)
}

# Prints "profile selection" for each desktop variant.
profile_desktop_variants() {
    local profile selection
    while IFS= read -r profile; do
        selection="$(profile_conf_value "$profile" desktop)"
        if [[ -n "$selection" ]]; then
            printf '%s %s\n' "$profile" "$selection"
        fi
    done < <(profile_names)
}

profile_usage() {
    local profile selection
    local -a selections=()

    printf 'Profiles:\n'
    while IFS= read -r profile; do
        printf '  %-14s %s\n' "$profile" "$(profile_conf_value "$profile" description)"
    done < <(profile_selectable_names)
    while read -r profile selection; do
        selections+=("$selection")
    done < <(profile_desktop_variants)
    printf '\nDesktop selections: %s\n' "$(printf '%s, ' "${selections[@]}")both"
}

profile_add_request() {
    local profile="$1"
    local existing

    if ! profile_is_selectable "$profile"; then
        printf 'Unknown profile: %s\n' "$profile" >&2
        profile_usage >&2
        return 2
    fi

    profile_mode=1
    for existing in "${requested_profiles[@]}"; do
        [[ "$existing" == "$profile" ]] && return
    done
    requested_profiles+=("$profile")
}

profile_add_skip() {
    local module="$1"
    local existing

    for existing in "${requested_skips[@]}"; do
        [[ "$existing" == "$module" ]] && return 0
    done
    requested_skips+=("$module")
}

profile_load_selection_manifest() {
    local manifest="$1"
    local label="$2"
    local key value extra

    while read -r key value extra; do
        [[ -n "${key:-}" && "$key" != \#* ]] || continue
        if [[ -n "${extra:-}" || -z "${value:-}" ]]; then
            printf 'Invalid %s entry in %s: %s %s %s\n' \
                "$label" \
                "$manifest" "$key" "${value:-}" "${extra:-}" >&2
            return 2
        fi
        case "$key" in
            profile) profile_add_request "$value" || return $? ;;
            desktop) profile_set_desktop "$value" || return $? ;;
            skip) profile_add_skip "$value" ;;
            platform) requested_platform="$value" ;;
            include) profile_load_host "$value" || return $? ;;
            *)
                printf "Unknown %s key '%s' in %s\n" "$label" "$key" "$manifest" >&2
                return 2
                ;;
        esac
    done < "$manifest"
}

profile_load_host() {
    local host="$1"
    local manifest="$host_profile_dir/$host.conf"

    if [[ ! "$host" =~ ^[[:alnum:]_-]+$ ]]; then
        printf 'Invalid host preset name: %s\n' "$host" >&2
        return 2
    fi
    if [[ ! -f "$manifest" ]]; then
        printf 'Host preset not found: %s\n' "$manifest" >&2
        return 2
    fi
    # Presets can include each other; load each once so cycles and diamonds are harmless.
    [[ -n "${loaded_host_presets[$host]+set}" ]] && return 0
    loaded_host_presets["$host"]=1

    profile_mode=1
    profile_load_selection_manifest "$manifest" "host preset"
}

# Prints the host preset saved for this machine, or nothing.
profile_machine_host() {
    local host=""
    [[ -f "$machine_host_file" ]] || return 0
    read -r host < "$machine_host_file" || true
    printf '%s\n' "$host"
}

profile_load_default() {
    machine_host_name="$(profile_machine_host)"
    if [[ -n "$machine_host_name" ]]; then
        profile_load_host "$machine_host_name"
    elif [[ -f "$default_profile_file" ]]; then
        profile_load_selection_manifest "$default_profile_file" "default selection"
    else
        profile_add_request core
    fi
}

profile_validate_default() {
    [[ -f "$default_profile_file" ]] || return 0
    (
        profile_mode=0
        requested_profiles=()
        requested_skips=()
        profile_load_selection_manifest "$default_profile_file" "default selection"
    )
}

platform_resolve() {
    local detected_platform

    detected_platform="$(platform_detect)"
    # A selection without a platform line is for whatever this machine is.
    [[ -n "$requested_platform" ]] || requested_platform="$detected_platform"

    if [[ "$requested_platform" == "windows" ]]; then
        printf 'Windows selections run through run.ps1, for example: powershell -ExecutionPolicy Bypass -File .\\run.ps1 plan --host windows\n' >&2
        return 2
    fi
    if [[ "$requested_platform" != "arch" && "$requested_platform" != "ubuntu" ]]; then
        printf 'Unsupported platform: %s\n' "$requested_platform" >&2
        return 2
    fi
    if [[ "$detected_platform" != "$requested_platform" ]]; then
        printf 'The selection is for %s, but this machine was detected as %s.\n' "$requested_platform" "$detected_platform" >&2
        return 2
    fi

    platform_activate "$detected_platform"
}

profile_set_desktop() {
    local profile selection found=""

    if [[ "$1" != "both" ]]; then
        # Read every line: breaking early closes the pipe while the producer is still printing.
        while read -r profile selection; do
            [[ "$selection" == "$1" ]] && found=1
        done < <(profile_desktop_variants)
        if [[ -z "$found" ]]; then
            printf 'Unknown desktop: %s\n' "$1" >&2
            profile_usage >&2
            return 2
        fi
    fi
    desktop_profile="$1"

    profile_mode=1
    desktop_profile_explicit=1
}

profile_add_run() {
    local run_name="$1"
    local existing

    for existing in "${resolved_profile_runs[@]}"; do
        [[ "$existing" == "$run_name" ]] && return
    done
    resolved_profile_runs+=("$run_name")
}

profile_add_resolved() {
    local profile="$1"
    local existing

    for existing in "${resolved_profiles[@]}"; do
        [[ "$existing" == "$profile" ]] && return
    done
    resolved_profiles+=("$profile")
}

# Adds a profile's included profiles, its modules, then the profile itself; each is expanded once.
profile_expand() {
    local profile="$1"
    local manifest="$profile_dir/$profile/profile.conf"
    local key value extra existing

    [[ -n "${expanded_profiles[$profile]+set}" ]] && return 0
    expanded_profiles["$profile"]=1
    if [[ ! -f "$manifest" ]]; then
        printf 'Profile not found: %s\n' "$manifest" >&2
        return 2
    fi
    while read -r key value extra; do
        [[ -n "${key:-}" && "$key" != \#* ]] || continue
        case "$key" in
            description|desktop|platforms) ;;
            include) profile_expand "$value" || return $? ;;
            module) profile_add_run "$value" ;;
            *)
                printf "Unknown key '%s' in %s\n" "$key" "$manifest" >&2
                return 2
                ;;
        esac
    done < "$manifest"
    profile_add_resolved "$profile"
}

profile_has_request() {
    local wanted="$1"
    local profile

    for profile in "${resolved_profiles[@]}"; do
        [[ "$profile" == "$wanted" ]] && return 0
    done
    return 1
}

profile_resolve() {
    local profile selection key value

    ((profile_mode == 1)) || return 0
    resolved_profiles=()
    expanded_profiles=()
    resolved_desktop_profiles=()
    resolved_profile_runs=()

    profile_expand core || return $?
    for profile in "${requested_profiles[@]}"; do
        profile_expand "$profile" || return $?
    done
    if ((desktop_profile_explicit == 1)); then
        profile_expand desktop || return $?
    fi

    if profile_has_request desktop; then
        while read -r profile selection; do
            [[ "$desktop_profile" == "both" || "$desktop_profile" == "$selection" ]] || continue
            resolved_desktop_profiles+=("$profile")
            while read -r key value; do
                if [[ "$key" == "module" ]]; then
                    profile_add_run "$value"
                fi
            done < "$profile_dir/$profile/profile.conf"
        done < <(profile_desktop_variants)
    fi

    export DOTFILES_PROFILE_MODE=1
    export DOTFILES_ACTIVE_PROFILES="${resolved_profiles[*]}"
    export DOTFILES_DESKTOP="$desktop_profile"
    export DOTFILES_DESKTOP_PROFILES="${resolved_desktop_profiles[*]}"
}

profile_includes_run() {
    local wanted="$1"
    local run_name skipped

    ((profile_mode == 1)) || return 0
    for skipped in "${requested_skips[@]}"; do
        [[ "$skipped" == "$wanted" ]] && return 1
    done
    for run_name in "${resolved_profile_runs[@]}"; do
        [[ "$run_name" == "$wanted" ]] && return 0
    done
    return 1
}

profile_skips_run() {
    local wanted="$1"
    local skipped

    for skipped in "${requested_skips[@]}"; do
        [[ "$skipped" == "$wanted" ]] && return 0
    done
    return 1
}
