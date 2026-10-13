#!/usr/bin/env bash

stage_catalog_file="${DOTFILES_DIR:?DOTFILES_DIR must be set}/profiles/stages.tsv"
declare -a execution_order=()
declare -A stage_needs_root=()
declare -A stage_dependencies=()
declare -A stage_platforms=()
declare -A stage_risks=()
declare -A stage_descriptions=()

load_stage_catalog() {
    local name root dependencies platforms risk description extra

    [[ -f "$stage_catalog_file" ]] || {
        printf 'Stage catalog not found: %s\n' "$stage_catalog_file" >&2
        return 2
    }

    execution_order=()
    while IFS='|' read -r name root dependencies platforms risk description extra; do
        [[ -n "$name" && "$name" != \#* ]] || continue
        if [[ -n "$extra" || ! "$name" =~ ^[a-z0-9][a-z0-9-]*$ \
            || ! "$root" =~ ^[01]$ || ! "$risk" =~ ^(normal|high)$ \
            || -z "$platforms" || -z "$description" ]]; then
            printf 'Invalid stage catalog entry: %s\n' \
                "$name|$root|$dependencies|$platforms|$risk|$description${extra:+|$extra}" >&2
            return 2
        fi
        if [[ -n "${stage_needs_root[$name]+set}" ]]; then
            printf 'Duplicate stage in catalog: %s\n' "$name" >&2
            return 2
        fi
        execution_order+=("$name")
        stage_needs_root["$name"]="$root"
        stage_dependencies["$name"]="$dependencies"
        stage_platforms["$name"]="$platforms"
        stage_risks["$name"]="$risk"
        stage_descriptions["$name"]="$description"
    done < "$stage_catalog_file"
}

stage_is_registered() {
    [[ -n "${stage_needs_root[$1]+set}" ]]
}

stage_supports_platform() {
    local stage="$1"
    local platform="$2"
    local candidate
    local -a supported_platforms=()

    IFS=',' read -r -a supported_platforms <<< "${stage_platforms[$stage]}"
    for candidate in "${supported_platforms[@]}"; do
        [[ "$candidate" == "$platform" ]] && return 0
    done
    return 1
}

stage_dependency_list() {
    local dependencies="${stage_dependencies[$1]:-}"
    [[ -n "$dependencies" ]] || return 0
    tr ',' '\n' <<< "$dependencies"
}

load_stage_catalog
