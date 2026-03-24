#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="$(pwd)"

LIMIT=1000
EXCLUDE_REPOS=""
PARALLEL_JOBS=1

usage() {
    echo "Usage: $0 [-d backup_dir] [-e exclude_repos] [-j jobs] <organization>"
    echo "  -d backup_dir   Optional: directory to store backups (default: current directory)"
    echo "  -e exclude_repos Optional: comma-separated list of repos to exclude"
    echo "  -j jobs         Optional: number of parallel jobs (default: 1)"
    exit 1
}

while getopts ":d:e:j:" opt; do
    case $opt in
        d) BACKUP_DIR="$(realpath -m "$OPTARG")" ;;
        e) EXCLUDE_REPOS="$OPTARG" ;;
        j) PARALLEL_JOBS="$OPTARG" ;;
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

clone_or_update_repo() {
    local repo="$1"
    local name
    name=$(basename "$repo")

    cd "$BACKUP_DIR"

    if [ -d "$name/.git" ]; then
        (
            cd "$name"

            if [ -n "$(git status --porcelain)" ]; then
                echo "Skipping $name (local changes)"
                echo "skipped" >> "$STATS_FILE"
                return
            fi

            branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")
            git fetch origin 2>/dev/null
            result=$(git pull --ff-only origin "$branch" 2>/dev/null)
            if echo "$result" | grep -q "Already up to date"; then
                echo "Up to date: $name"
                echo "up_to_date" >> "$STATS_FILE"
            else
                echo "Updated: $name"
                echo "updated" >> "$STATS_FILE"
            fi
        ) || { echo "Failed: $name"; echo "failed" >> "$STATS_FILE"; }
    else
        echo "Cloning: $repo"
        if gh repo clone "$repo" 2>/dev/null; then
            echo "cloned" >> "$STATS_FILE"
        else
            echo "Failed to clone: $repo"
            echo "failed" >> "$STATS_FILE"
        fi
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
export BACKUP_DIR
export STATS_FILE

echo "$repos" | xargs -P "$PARALLEL_JOBS" -I {} bash -c 'clone_or_update_repo "$@"' _ {}

cloned=$(grep -c "^cloned$"      "$STATS_FILE" || true)
updated=$(grep -c "^updated$"    "$STATS_FILE" || true)
up_to_date=$(grep -c "^up_to_date$" "$STATS_FILE" || true)
skipped=$(grep -c "^skipped$"    "$STATS_FILE" || true)
failed=$(grep -c "^failed$"      "$STATS_FILE" || true)
rm -f "$STATS_FILE"

echo
echo "Backup complete! All repos saved in: ${BACKUP_DIR}"
echo
echo "Summary:"
echo "  Cloned (new):            $cloned"
echo "  Updated:                 $updated"
echo "  Already up to date:      $up_to_date"
echo "  Skipped (local changes): $skipped"
[ "$failed" -gt 0 ] && echo "  Failed:                  $failed"

