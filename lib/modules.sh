#!/usr/bin/env bash

# Each module is a module directory: modules/<name>/module.conf describes it, modules/<name>/install
# runs it, and modules/order.list sets the order modules run in.
module_root="${DOTFILES_DIR:?DOTFILES_DIR must be set}/modules"
module_order_file="$module_root/order.list"
declare -a execution_order=()
declare -A module_needs_root=()
declare -A module_dependencies=()
declare -A module_platforms=()
declare -A module_risks=()
declare -A module_descriptions=()

module_dir() {
    printf '%s/%s\n' "$module_root" "$1"
}

module_path() {
    printf '%s/%s/install\n' "$module_root" "$1"
}

# module.conf holds "key value..." lines: description, root (yes|no), depends, platforms, risk.
load_module_conf() {
    local name="$1"
    local conf="$module_root/$name/module.conf"
    local key value root="" platforms="" risk="" description="" dependencies=""

    [[ -f "$conf" ]] || {
        printf 'Module config not found: %s\n' "$conf" >&2
        return 2
    }
    while read -r key value; do
        [[ -n "${key:-}" && "$key" != \#* ]] || continue
        case "$key" in
            description) description="$value" ;;
            root) root="$value" ;;
            depends) dependencies="$value" ;;
            platforms) platforms="$value" ;;
            risk) risk="$value" ;;
            *)
                printf "Unknown key '%s' in %s\n" "$key" "$conf" >&2
                return 2
                ;;
        esac
    done < "$conf"
    if [[ ! "$root" =~ ^(yes|no)$ || ! "$risk" =~ ^(normal|high)$ \
        || -z "$platforms" || -z "$description" ]]; then
        printf 'Invalid module config %s: needs description, root yes|no, platforms and risk normal|high\n' "$conf" >&2
        return 2
    fi
    module_needs_root["$name"]="$([[ "$root" == yes ]] && echo 1 || echo 0)"
    module_dependencies["$name"]="$dependencies"
    module_platforms["$name"]="$platforms"
    module_risks["$name"]="$risk"
    module_descriptions["$name"]="$description"
}

load_module_catalog() {
    local name extra

    [[ -f "$module_order_file" ]] || {
        printf 'Module order not found: %s\n' "$module_order_file" >&2
        return 2
    }

    execution_order=()
    while read -r name extra; do
        [[ -n "${name:-}" && "$name" != \#* ]] || continue
        if [[ -n "${extra:-}" || ! "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
            printf 'Invalid entry in %s: %s %s\n' "$module_order_file" "$name" "${extra:-}" >&2
            return 2
        fi
        if [[ -n "${module_needs_root[$name]+set}" ]]; then
            printf 'Duplicate module in %s: %s\n' "$module_order_file" "$name" >&2
            return 2
        fi
        load_module_conf "$name" || return $?
        execution_order+=("$name")
    done < "$module_order_file"
}

module_is_registered() {
    [[ -n "${module_needs_root[$1]+set}" ]]
}

module_supports_platform() {
    local module="$1"
    local platform="$2"
    local candidate
    local -a supported_platforms=()

    read -r -a supported_platforms <<< "${module_platforms[$module]}"
    for candidate in "${supported_platforms[@]}"; do
        [[ "$candidate" == "$platform" ]] && return 0
    done
    return 1
}

module_dependency_list() {
    local dependencies="${module_dependencies[$1]:-}"
    [[ -n "$dependencies" ]] || return 0
    tr -s ' ' '\n' <<< "$dependencies"
}

load_module_catalog
