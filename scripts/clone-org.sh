#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="$(pwd)"

LIMIT=1000
EXCLUDE_REPOS=""
PARALLEL_JOBS=1
BARE_MODE=0

usage() {
    echo "Usage: $0 [-d backup_dir] [-e exclude_repos] [-j jobs] [--bare] <organization>"
    echo "  -d backup_dir    Optional: directory to store backups (default: current directory)"
    echo "  -e exclude_repos Optional: comma-separated list of repos to exclude"
    echo "  -j jobs          Optional: number of parallel jobs (default: 1)"
    echo "  --bare, -b       Optional: clone each repo as a flat bare repo with the default branch"
    echo "                   checked out as a worktree subdir. Without this, repos are normal clones."
    exit 1
}

# Translate --bare to -b so getopts can parse it
ARGS=()
for a in "$@"; do
    case "$a" in
        --bare) ARGS+=("-b") ;;
        *) ARGS+=("$a") ;;
    esac
done
set -- "${ARGS[@]}"

while getopts ":d:e:j:b" opt; do
    case $opt in
        d) BACKUP_DIR="$(realpath -m "$OPTARG")" ;;
        e) EXCLUDE_REPOS="$OPTARG" ;;
        j) PARALLEL_JOBS="$OPTARG" ;;
        b) BARE_MODE=1 ;;
        *) usage ;;
    esac
done
shift $((OPTIND -1))

if [ $# -ne 1 ]; then
    usage
fi

ORG="$1"

echo "Checking GitHub authentication..."
if ! gh auth status &>/dev/null; then
    echo "You are not authenticated. Run: gh auth login"
    exit 1
fi

echo "Backing up organization: $ORG"
mkdir -p "$BACKUP_DIR"
cd "$BACKUP_DIR"

normalize_remote_to_ssh() {
    local repo_dir="$1"
    local current
    current=$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)
    if [[ "$current" =~ ^https://github\.com/ ]]; then
        local ssh_url
        ssh_url=$(echo "$current" | sed -E 's#^https://github\.com/#git@github.com:#')
        git -C "$repo_dir" remote set-url origin "$ssh_url"
    fi
}

resolve_default_branch() {
    local d="$1"
    git -C "$d" remote set-head origin -a >/dev/null 2>&1 || true
    local b
    b=$(git -C "$d" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
    [ -z "$b" ] && b=$(git -C "$d" symbolic-ref --short HEAD 2>/dev/null || echo "main")
    echo "$b"
}

# Make a directory a proper bare repo (idempotent).
correct_bare_repo() {
    local d="$1"
    git -C "$d" config core.bare true
    git -C "$d" config --unset core.worktree 2>/dev/null || true
    rm -f "$d/index"
}

is_flat_bare() {
    local d="$1"
    [ ! -d "$d/.git" ] && [ -f "$d/HEAD" ] && [ -d "$d/objects" ] && [ -d "$d/refs" ]
}

# ─── default mode: plain clone-or-pull ────────────────────────────────────
clone_or_update_normal() {
    local repo="$1" name="$2" url="$3"
    local container="$BACKUP_DIR/${name}"

    if [ -d "$container/.git" ]; then
        normalize_remote_to_ssh "$container"

        if [ -n "$(git -C "$container" status --porcelain 2>/dev/null)" ]; then
            echo "Skipping $name (local changes)"
            echo "skipped $name $url" >> "$STATS_FILE"
            return
        fi

        local branch
        branch=$(git -C "$container" symbolic-ref --short HEAD 2>/dev/null || echo "main")
        git -C "$container" fetch origin 2>/dev/null || true
        local local_head
        local_head=$(git -C "$container" rev-parse HEAD)
        if git -C "$container" pull --ff-only origin "$branch" >/dev/null 2>&1; then
            local new_head
            new_head=$(git -C "$container" rev-parse HEAD)
            if [ "$local_head" = "$new_head" ]; then
                echo "Up to date: $name"
                echo "up_to_date $name $url" >> "$STATS_FILE"
            else
                echo "Updated: $name"
                echo "updated $name $url" >> "$STATS_FILE"
            fi
        else
            echo "Up to date: $name (can't fast-forward)"
            echo "up_to_date $name $url" >> "$STATS_FILE"
        fi
        return
    fi

    if [ -e "$container" ]; then
        echo "Skipping $name (exists but not a normal checkout; re-run with --bare?)"
        echo "skipped $name $url" >> "$STATS_FILE"
        return
    fi

    echo "Cloning: $repo"
    if gh repo clone "$repo" "$container" 2>/dev/null; then
        normalize_remote_to_ssh "$container"
        echo "cloned $name $url" >> "$STATS_FILE"
    else
        echo "Failed to clone: $repo"
        echo "failed $name $url" >> "$STATS_FILE"
    fi
}

# ─── --bare mode: flat bare repo with worktrees as siblings ───────────────
migrate_dotbare_to_flat() {
    local container="$1"
    [ -d "$container/.bare" ] || return 0
    find "$container/.bare" -mindepth 1 -maxdepth 1 -exec mv {} "$container/" \; 2>/dev/null || true
    rmdir "$container/.bare" 2>/dev/null || true
    local wt_dir
    for wt_dir in "$container"/*/; do
        wt_dir="${wt_dir%/}"
        [ -f "$wt_dir/.git" ] || continue
        if grep -q "/\.bare/worktrees/" "$wt_dir/.git" 2>/dev/null; then
            sed -i "s|/\.bare/worktrees/|/worktrees/|g" "$wt_dir/.git"
        fi
    done
}

clone_or_update_bare() {
    local repo="$1" name="$2" url="$3"
    local container="$BACKUP_DIR/${name}"

    if [ -d "$container/.bare" ]; then
        echo "Migrating $name from .bare/ layout to flat"
        migrate_dotbare_to_flat "$container"
    fi

    if is_flat_bare "$container"; then
        correct_bare_repo "$container"
        normalize_remote_to_ssh "$container"
        git -C "$container" worktree prune 2>/dev/null || true

        local before_refs
        before_refs=$(git -C "$container" for-each-ref --format='%(refname) %(objectname)' refs/remotes/ 2>/dev/null || true)

        if ! git -C "$container" fetch origin 2>/dev/null; then
            echo "Failed to fetch: $name"
            echo "failed $name $url" >> "$STATS_FILE"
            return
        fi

        local after_refs
        after_refs=$(git -C "$container" for-each-ref --format='%(refname) %(objectname)' refs/remotes/ 2>/dev/null || true)

        local default_branch
        default_branch=$(resolve_default_branch "$container")
        local default_work_dir="$container/$default_branch"
        if [ ! -d "$default_work_dir" ]; then
            if git -C "$container" worktree add "$default_work_dir" "$default_branch" >/dev/null 2>&1; then
                echo "Recreated worktree for $name on $default_branch"
            fi
        fi

        local wt
        for wt in "$container"/*/; do
            wt="${wt%/}"
            [ -e "$wt/.git" ] || continue
            if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
                echo "Skipping dirty worktree: $name/$(basename "$wt")"
                echo "skipped $name/$(basename "$wt") $url" >> "$STATS_FILE"
                continue
            fi
            local wt_branch
            wt_branch=$(git -C "$wt" symbolic-ref --short HEAD 2>/dev/null || echo "")
            [ -n "$wt_branch" ] || continue
            git -C "$wt" pull --ff-only origin "$wt_branch" >/dev/null 2>&1 || true
        done

        if [ "$before_refs" = "$after_refs" ]; then
            echo "Up to date: $name"
            echo "up_to_date $name $url" >> "$STATS_FILE"
        else
            echo "Updated: $name"
            echo "updated $name $url" >> "$STATS_FILE"
        fi
        return
    fi

    local is_fresh=0
    if [ ! -e "$container" ]; then
        echo "Cloning: $repo"
        if ! gh repo clone "$repo" "$container" 2>/dev/null; then
            echo "Failed to clone: $repo"
            echo "failed $name $url" >> "$STATS_FILE"
            return
        fi
        is_fresh=1
    fi

    if [ -d "$container/.git" ]; then
        if [ "$is_fresh" -ne 1 ] && [ -n "$(git -C "$container" status --porcelain 2>/dev/null)" ]; then
            echo "Skipping $name (local changes, not converting)"
            echo "skipped $name $url" >> "$STATS_FILE"
            return
        fi

        normalize_remote_to_ssh "$container"

        local default_branch
        default_branch=$(git -C "$container" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
        if [ -z "$default_branch" ]; then
            default_branch=$(git -C "$container" symbolic-ref --short HEAD 2>/dev/null || echo "main")
        fi
        local work_dir="$container/$default_branch"

        local stage="$BACKUP_DIR/.${name}_stage_$$"
        rm -rf "$stage"
        mkdir -p "$stage"
        find "$container" -mindepth 1 -maxdepth 1 ! -name ".git" -exec mv {} "$stage/" \; 2>/dev/null || true

        find "$container/.git" -mindepth 1 -maxdepth 1 -exec mv {} "$container/" \; 2>/dev/null || true
        rmdir "$container/.git" 2>/dev/null || true
        correct_bare_repo "$container"

        if ! git -C "$container" worktree add "$work_dir" "$default_branch" >/dev/null 2>&1; then
            echo "Conversion failed for $name (worktree add)"
            echo "failed $name $url" >> "$STATS_FILE"
            return
        fi

        find "$stage" -mindepth 1 -maxdepth 1 -exec mv -n -t "$work_dir/" {} + 2>/dev/null || true
        rm -rf "$stage"

        if [ "$is_fresh" -eq 1 ]; then
            echo "cloned $name $url" >> "$STATS_FILE"
        else
            echo "Converted $name to flat bare + worktree on $default_branch"
            echo "converted $name $url" >> "$STATS_FILE"
        fi
        return
    fi

    echo "Failed (unrecognized state): $name"
    echo "failed $name $url" >> "$STATS_FILE"
}

clone_or_update_repo() {
    local repo="$1"
    local name
    name=$(basename "$repo")
    local url="https://github.com/${repo}"

    cd "$BACKUP_DIR"

    if [ "${BARE_MODE:-0}" = "1" ]; then
        clone_or_update_bare "$repo" "$name" "$url"
    else
        clone_or_update_normal "$repo" "$name" "$url"
    fi
}

repos_public=$(gh repo list "$ORG" --visibility public --limit "$LIMIT" --json nameWithOwner -q '.[].nameWithOwner' || true)
repos_private=$(gh repo list "$ORG" --visibility private --limit "$LIMIT" --json nameWithOwner -q '.[].nameWithOwner' || true)
repos=$(printf "%s\n%s\n" "$repos_public" "$repos_private" | sort -u)

count=$(echo "$repos" | grep -c . || true)
echo "Found $count repositories in ${ORG}"

if [ -n "$EXCLUDE_REPOS" ]; then
    echo "Excluding repos: $EXCLUDE_REPOS"
    OLD_REPOS="$repos"
    repos=""
    while IFS= read -r repo; do
        excluded=false
        IFS=',' read -ra EXCLUDE_ARRAY <<< "$EXCLUDE_REPOS"
        for exclude in "${EXCLUDE_ARRAY[@]}"; do
            if [[ "$repo" == "$exclude" || "$repo" == "$ORG/$exclude" ]]; then
                excluded=true
                break
            fi
        done
        if [ "$excluded" = false ]; then
            repos="$repos$repo"$'\n'
        fi
    done <<< "$OLD_REPOS"
    repos=$(echo "$repos" | sort -u)
    new_count=$(echo "$repos" | grep -c . || true)
    echo "After exclusion: $new_count repositories"
fi

STATS_FILE="$(mktemp)"

export -f clone_or_update_repo
export -f clone_or_update_normal
export -f clone_or_update_bare
export -f normalize_remote_to_ssh
export -f resolve_default_branch
export -f correct_bare_repo
export -f is_flat_bare
export -f migrate_dotbare_to_flat
export BACKUP_DIR
export STATS_FILE
export BARE_MODE

echo "$repos" | xargs -P "$PARALLEL_JOBS" -I {} bash -c 'clone_or_update_repo "$@"' _ {}

cloned=$(grep -c "^cloned "      "$STATS_FILE" || true)
converted=$(grep -c "^converted " "$STATS_FILE" || true)
updated=$(grep -c "^updated "    "$STATS_FILE" || true)
up_to_date=$(grep -c "^up_to_date " "$STATS_FILE" || true)
skipped=$(grep -c "^skipped "    "$STATS_FILE" || true)
failed=$(grep -c "^failed "      "$STATS_FILE" || true)

print_repos() {
    local status="$1"
    grep "^${status} " "$STATS_FILE" 2>/dev/null | while read -r _ name url; do
        echo "    $name  $url"
    done
}

echo
echo "Backup complete! All repos saved in: ${BACKUP_DIR}"
echo
echo "Summary:"
echo "  Cloned (new):            $cloned"
[ "$cloned" -gt 0 ] && print_repos "cloned"
if [ "$converted" -gt 0 ]; then
    echo "  Converted to bare:       $converted"
    print_repos "converted"
fi
echo "  Updated:                 $updated"
[ "$updated" -gt 0 ] && print_repos "updated"
echo "  Already up to date:      $up_to_date"
echo "  Skipped (local changes): $skipped"
[ "$skipped" -gt 0 ] && print_repos "skipped"
if [ "$failed" -gt 0 ]; then
    echo "  Failed:                  $failed"
    print_repos "failed"
fi

rm -f "$STATS_FILE"
