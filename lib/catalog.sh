#!/usr/bin/env bash

# Read-only overviews of the profiles and modules for ./run list and ./run show. They work on any
# platform: nothing here resolves packages or touches the machine.

catalog_list() {
    local profile module platforms

    printf 'Profiles:\n'
    while IFS= read -r profile; do
        platforms="$(profile_conf_value "$profile" platforms)"
        printf '  %-16s %-22s %s\n' "$profile" "${platforms:-all}" "$(profile_conf_value "$profile" description)"
    done < <(profile_selectable_names)
    printf '\nModules (in run order):\n'
    for module in "${execution_order[@]}"; do
        printf '  %-16s %-22s %s\n' "$module" "${module_platforms[$module]}" "${module_descriptions[$module]}"
    done
    printf '\nDetails: ./run show NAME\n'
}

# Prints the non-comment lines of a manifest, indented under a heading.
catalog_print_manifest() {
    local heading="$1"
    local manifest="$2"

    [[ -f "$manifest" ]] || return 0
    grep -q -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' -- "$manifest" || return 0
    printf '%s (%s):\n' "$heading" "${manifest#"$DOTFILES_DIR"/}"
    grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' -- "$manifest" | sed 's/^/  /'
}

# Profiles whose profile.conf has "<key> <value>".
catalog_profiles_with() {
    local key="$1"
    local value="$2"
    local profile
    local -a matches=()

    while IFS= read -r profile; do
        if [[ " $(profile_conf_value "$profile" "$key" | tr '\n' ' ') " == *" $value "* ]]; then
            matches+=("$profile")
        fi
    done < <(profile_names)
    printf '%s\n' "${matches[*]:-none}"
}

catalog_show_profile() {
    local profile="$1"
    local dir="$DOTFILES_DIR/profiles/$profile"
    local conf host platforms includes modules
    local -a hosts=()

    platforms="$(profile_conf_value "$profile" platforms)"
    includes="$(profile_conf_value "$profile" include | tr '\n' ' ')"
    includes="${includes% }"
    modules="$(profile_conf_value "$profile" module | tr '\n' ' ')"
    modules="${modules% }"
    for conf in "$DOTFILES_DIR"/hosts/*.conf; do
        host="$(basename "$conf" .conf)"
        if grep -Eq "^[[:space:]]*profile[[:space:]]+$profile([[:space:]]|$)" "$conf"; then
            hosts+=("$host")
        fi
    done

    printf 'Profile: %s\n' "$profile"
    printf 'Description: %s\n' "$(profile_conf_value "$profile" description)"
    printf 'Platforms: %s\n' "${platforms:-all}"
    if [[ -n "$(profile_conf_value "$profile" desktop)" ]]; then
        printf 'Desktop variant: used when --desktop includes %s\n' "$(profile_conf_value "$profile" desktop)"
    fi
    printf 'Includes: %s\n' "${includes:-none}"
    printf 'Included by: %s\n' "$(catalog_profiles_with include "$profile")"
    printf 'Hosts: %s\n' "${hosts[*]:-none}"
    printf 'Modules: %s\n' "${modules:-none}"
    catalog_print_manifest Packages "$dir/packages.list"
    catalog_print_manifest Tools "$dir/tools.list"
    catalog_print_manifest Flatpaks "$dir/flatpaks.list"
    catalog_print_manifest Dotfiles "$dir/dotfiles.list"
}

catalog_show_module() {
    local module="$1"
    local dir="$DOTFILES_DIR/modules/$module"
    local other manifest kind platform
    local -a needed_by=()

    for other in "${execution_order[@]}"; do
        if [[ " ${module_dependencies[$other]} " == *" $module "* ]]; then
            needed_by+=("$other")
        fi
    done

    printf 'Module: %s\n' "$module"
    printf 'Description: %s\n' "${module_descriptions[$module]}"
    printf 'Runs as: %s, %s risk\n' "$([[ "${module_needs_root[$module]}" == 1 ]] && echo root || echo user)" "${module_risks[$module]}"
    printf 'Platforms: %s\n' "${module_platforms[$module]}"
    printf 'Depends on: %s\n' "${module_dependencies[$module]:-none}"
    printf 'Needed by: %s\n' "${needed_by[*]:-none}"
    printf 'Profiles: %s\n' "$(catalog_profiles_with module "$module")"
    printf 'Script: %s\n' "${dir#"$DOTFILES_DIR"/}/install"
    catalog_print_manifest Packages "$dir/packages.list"
    for kind in services groups files; do
        for manifest in "$dir/$kind".*.list; do
            [[ -f "$manifest" ]] || continue
            platform="${manifest%.list}"
            platform="${platform##*.}"
            catalog_print_manifest "${kind^} on $platform" "$manifest"
        done
    done
}

catalog_show() {
    local name="$1"
    local found=0

    if [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ && -f "$DOTFILES_DIR/profiles/$name/profile.conf" ]]; then
        catalog_show_profile "$name"
        found=1
    fi
    if module_is_registered "$name"; then
        ((found == 0)) || printf '\n'
        catalog_show_module "$name"
        found=1
    fi
    if ((found == 0)); then
        printf 'No profile or module named %s. See ./run list.\n' "$name" >&2
        return 2
    fi
}
