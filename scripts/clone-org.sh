#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="$(pwd)"
LIMIT=1000

usage() {
    echo "Usage: $0 [-d backup_dir] <organization>"
    echo "  -d backup_dir   Optional: directory to store backups (default: current directory)"
    exit 1
}

while getopts ":d:" opt; do
    case $opt in
        d) BACKUP_DIR="$OPTARG" ;;
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

for repo in $repos; do
    clone_or_update_repo "$repo"
done

echo
echo "Backup complete! All repos saved in: ${BACKUP_DIR}"

