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
        d) BACKUP_DIR="$OPTARG" ;;
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
        echo "Checking for updates: $name"
        (
            cd "$name"

            if [ -n "$(git status --porcelain)" ]; then
                echo "Skipping update for $name (local changes detected)"
                return
            fi

            branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")
            git fetch origin
            git pull --ff-only origin "$branch" || echo "Failed to update $name"
        )
    else
        echo "Cloning: $repo"
        gh repo clone "$repo" || echo "Failed to clone $repo"
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

export -f clone_or_update_repo
export BACKUP_DIR

echo "$repos" | xargs -P "$PARALLEL_JOBS" -I {} bash -c 'clone_or_update_repo "$@"' _ {}

echo
echo "Backup complete! All repos saved in: ${BACKUP_DIR}"

