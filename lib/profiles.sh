#!/usr/bin/env bash

# Shared installer profile resolution for the runner and its audit command.

source "${DOTFILES_DIR:?DOTFILES_DIR must be set}/lib/platforms.sh"

profile_dir="${DOTFILES_DIR:?DOTFILES_DIR must be set}/profiles"
host_profile_dir="$profile_dir/hosts"
default_profile_file="$profile_dir/default.conf"
profile_mode=0
desktop_profile="hyprland"
desktop_profile_explicit=0
requested_platform="arch"
export DOTFILES_PROFILE_MODE=0
export DOTFILES_ACTIVE_PROFILES=""
export DOTFILES_DESKTOP="$desktop_profile"
export DOTFILES_PLATFORM=""
export DOTFILES_PACKAGE_DIR=""
declare -a requested_profiles=()
declare -a resolved_profiles=()
declare -a resolved_profile_runs=()
declare -a requested_skips=()
declare -A loaded_host_presets=()

profile_usage() {
    cat <<'EOF'
Profiles:
  core         Base packages, shell, Git, tmux, and the SSH client
  development  Java, JavaScript runtimes, repositories, sbx, and snd
  desktop      Flatpaks, clipboard tools, and a desktop selection
  system       Boot and multiboot configuration
  virtualization  QEMU, libvirt, and VM tools
  hardware     Device, SDR, GPU, and printing tools
  security     Network and host security tools
  media        Audio, recording, and media tools
  ssh-server   SSH daemon configuration and remote access
  gpu-amd      AMD graphics drivers and ROCm tools
  gpu-intel    Intel graphics drivers and video acceleration
  gpu-nvidia   NVIDIA graphics drivers and PRIME offload
  laptop       Power profiles and thermal management
  full         Every general workstation profile

Desktop selections: hyprland, plasma, both
EOF
}

profile_add_request() {
    local profile="$1"
    local existing

    case "$profile" in
        core|development|desktop|system|virtualization|hardware|security|media|ssh-server|gpu-amd|gpu-intel|gpu-nvidia|laptop|full)
            ;;
        *)
            printf 'Unknown profile: %s\n' "$profile" >&2
            profile_usage >&2
            return 2
            ;;
    esac

    profile_mode=1
    for existing in "${requested_profiles[@]}"; do
        [[ "$existing" == "$profile" ]] && return
    done
    requested_profiles+=("$profile")
}

profile_add_skip() {
    local stage="$1"
    local existing

    for existing in "${requested_skips[@]}"; do
        [[ "$existing" == "$stage" ]] && return 0
    done
    requested_skips+=("$stage")
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

profile_load_default() {
    if [[ -f "$default_profile_file" ]]; then
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

    if [[ "$requested_platform" != "arch" ]]; then
        printf 'Unsupported platform in selection: %s\n' "$requested_platform" >&2
        return 2
    fi
    if [[ "$detected_platform" != "$requested_platform" ]]; then
        printf 'This installer currently supports Arch Linux only; detected %s.\n' "$detected_platform" >&2
        return 2
    fi

    platform_activate "$detected_platform"
}

profile_set_desktop() {
    case "$1" in
        hyprland|plasma|both)
            desktop_profile="$1"
            ;;
        *)
            printf 'Unknown desktop: %s\n' "$1" >&2
            profile_usage >&2
            return 2
            ;;
    esac

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

profile_load_runs() {
    local profile="$1"
    local manifest="$profile_dir/$profile.runs"
    local line

    if [[ ! -f "$manifest" ]]; then
        printf 'Profile manifest not found: %s\n' "$manifest" >&2
        return 2
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -n "$line" ]] && profile_add_run "$line"
    done < "$manifest"
}

profile_has_request() {
    local wanted="$1"
    local profile

    for profile in "${requested_profiles[@]}"; do
        [[ "$profile" == "$wanted" || "$profile" == "full" ]] && return 0
    done
    return 1
}

profile_resolve() {
    local profile

    ((profile_mode == 1)) || return 0
    if ((desktop_profile_explicit == 1)) && ! profile_has_request desktop; then
        profile_add_request desktop
    fi
    resolved_profiles=()
    resolved_profile_runs=()

    profile_add_resolved core
    profile_load_runs core

    for profile in "${requested_profiles[@]}"; do
        case "$profile" in
            core)
                ;;
            full)
                for profile in development desktop system virtualization hardware security media; do
                    profile_add_resolved "$profile"
                    profile_load_runs "$profile"
                done
                ;;
            desktop)
                profile_add_resolved desktop
                profile_load_runs desktop
                ;;
            *)
                profile_add_resolved "$profile"
                profile_load_runs "$profile"
                ;;
        esac
    done

    if profile_has_request desktop; then
        case "$desktop_profile" in
            hyprland)
                profile_load_runs desktop-hyprland
                ;;
            plasma)
                profile_load_runs desktop-plasma
                ;;
            both)
                profile_load_runs desktop-hyprland
                profile_load_runs desktop-plasma
                ;;
        esac
    fi

    export DOTFILES_PROFILE_MODE=1
    export DOTFILES_ACTIVE_PROFILES="${resolved_profiles[*]}"
    export DOTFILES_DESKTOP="$desktop_profile"
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
