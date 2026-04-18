#!/usr/bin/env bash

# clone into org folders (personal should be username)
# make service so it backups every x time automatically
# get repos to pull for changes (force pull overwrite local if need)
# get new repos and download / clone them

set -euo pipefail

BACKUP_DIR="${HOME}/github-backup"
LIMIT=1000

echo "🔐 Checking GitHub authentication..."
if ! gh auth status &>/dev/null; then
    echo "❌ You are not authenticated. Run: gh auth login"
    exit 1
fi

USER="$(gh api user --jq .login)"
echo "👤 Authenticated as: ${USER}"

echo "📁 Creating backup directory: ${BACKUP_DIR}"
mkdir -p "$BACKUP_DIR"
cd "$BACKUP_DIR"

# --- Function to clone or update repos ---
clone_or_update_repo() {
    local repo="$1"
    local name
    name=$(basename "$repo")

    if [ -d "$name/.git" ]; then
        echo "🔄 Updating: $name"
        (
            cd "$name"
            branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")
            git fetch origin
            git reset --hard "origin/$branch" || echo "⚠️  Failed to update $name"
        )
    else
        echo "⬇️  Cloning: $repo"
        if gh repo clone "$repo"; then
            new_repos+=("$repo")
        else
            echo "⚠️  Failed to clone $repo"
        fi
    fi
}

# --- Personal Repos (public + private) ---
echo
echo "💾 Fetching personal repositories for: ${USER}"
personal_dir="${BACKUP_DIR}/${USER}"
mkdir -p "$personal_dir"
cd "$personal_dir"

repos_public=$(gh repo list "$USER" --visibility public --limit "$LIMIT" --json nameWithOwner -q '.[].nameWithOwner' || true)
repos_private=$(gh repo list "$USER" --visibility private --limit "$LIMIT" --json nameWithOwner -q '.[].nameWithOwner' || true)
repos=$(printf "%s\n%s\n" "$repos_public" "$repos_private" | sort -u)

count=$(echo "$repos" | grep -c . || true)
echo "📦 Found $count personal repositories."

new_repos=()
for repo in $repos; do
    clone_or_update_repo "$repo"
done

if [ ${#new_repos[@]} -gt 0 ]; then
    echo "✨ ${#new_repos[@]} new repo(s) cloned for ${USER}:"
    for r in "${new_repos[@]}"; do
        echo "   + $r"
    done
else
    echo "ℹ️  No new repos for ${USER}."
fi

cd "$BACKUP_DIR"

# --- Organization Repos ---
echo
echo "🏢 Fetching organizations..."
orgs=$(gh api user/orgs --jq '.[].login' || true)

if [ -z "$orgs" ]; then
    echo "ℹ️  No organizations found."
else
    for org in $orgs; do
        echo
        echo "🏢 Backing up organization: ${org}"
        org_dir="${BACKUP_DIR}/${org}"
        mkdir -p "$org_dir"
        cd "$org_dir"

        org_repos_public=$(gh repo list "$org" --visibility public --limit "$LIMIT" --json nameWithOwner -q '.[].nameWithOwner' || true)
        org_repos_private=$(gh repo list "$org" --visibility private --limit "$LIMIT" --json nameWithOwner -q '.[].nameWithOwner' || true)
        org_repos=$(printf "%s\n%s\n" "$org_repos_public" "$org_repos_private" | sort -u)

        count=$(echo "$org_repos" | grep -c . || true)
        echo "📦 Found $count repos in ${org}"

        new_repos=()
        for repo in $org_repos; do
            clone_or_update_repo "$repo"
        done

        if [ ${#new_repos[@]} -gt 0 ]; then
            echo "✨ ${#new_repos[@]} new repo(s) cloned for ${org}:"
            for r in "${new_repos[@]}"; do
                echo "   + $r"
            done
        else
            echo "ℹ️  No new repos for ${org}."
        fi

        cd "$BACKUP_DIR"
    done
fi

echo
echo "✅ Backup complete! All repos saved in: ${BACKUP_DIR}"


