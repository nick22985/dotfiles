#!/usr/bin/env bash
# Convert a repository into the .bare layout: git internals in <dir>/.bare, a <dir>/.git file
# pointing at them, and worktrees as <dir>/<branch>. Nothing is lost either way:
#
#   - A normal checkout keeps every file, including local changes, untracked and ignored files,
#     in the worktree for its current branch, and the old index moves with it so staged changes
#     stay staged.
#   - A flat bare repo (internals at the root) keeps its worktrees where they are.
#
# Submodules are re-pointed at their moved git directories.
#
#   scripts/convert-to-bare.sh <dir>
set -euo pipefail

die() { echo "convert-to-bare: $*" >&2; exit 1; }

# Re-point submodule .git files and core.worktree under $1 from the $2 prefix to the $3 prefix.
# Relative gitdirs resolve from where $1 used to be ($4, default $1).
repoint_submodules() {
    local root="$1" old="$2" new="$3" was="${4:-$1}" gitfile submodule target module_dir
    while IFS= read -r -d '' gitfile; do
        submodule="$(dirname -- "$gitfile")"
        target="$(sed -n 's/^gitdir: //p' "$gitfile")"
        [[ "$target" == /* ]] || target="$(realpath -m -- "$was/${submodule#"$root"/}/$target")"
        [[ "$target" == "$old"* ]] || continue
        module_dir="$new${target#"$old"}"
        [[ -d "$module_dir" ]] || continue
        printf 'gitdir: %s\n' "$(realpath -m --relative-to="$submodule" -- "$module_dir")" > "$gitfile"
        git config -f "$module_dir/config" core.worktree "$(realpath -m --relative-to="$module_dir" -- "$submodule")"
    done < <(find "$root" -mindepth 2 -name .git -type f -print0)
}

[[ $# -eq 1 ]] || die "usage: $0 <dir>"
dir="$(realpath -- "$1")"
[[ ! -d "$dir/.bare" ]] || die "$dir already uses the .bare layout"

if [[ -d "$dir/.git" && ! -L "$dir/.git" ]]; then
    branch="$(git -C "$dir" symbolic-ref -q --short HEAD)" || die "$dir has a detached HEAD"
    git -C "$dir" rev-parse -q --verify "HEAD^{commit}" >/dev/null || die "$dir has no commits on $branch"
    for state in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG rebase-merge rebase-apply index.lock; do
        [[ ! -e "$dir/.git/$state" ]] || die "$dir has a $state in progress"
    done
    [[ -z "$(git -C "$dir" worktree list --porcelain | sed -n '2,$p' | grep '^worktree ')" ]] \
        || die "$dir already has linked worktrees"
    top="${branch%%/*}"
    [[ ! -e "$dir/$top" ]] || die "$dir/$top already exists; it would collide with the worktree for $branch"

    work="$dir/$branch"
    mkdir -p -- "$work"
    # Move the working tree first, then the git directory, so a failure leaves .git in place.
    find "$dir" -mindepth 1 -maxdepth 1 ! -name .git ! -name "$top" -exec mv -n -t "$work/" -- {} +
    [[ -z "$(find "$dir" -mindepth 1 -maxdepth 1 ! -name .git ! -name "$top" -print -quit)" ]] \
        || die "some files could not be moved into $work; nothing else was changed"
    mv -- "$dir/.git" "$dir/.bare"
    printf 'gitdir: ./.bare\n' > "$dir/.git"
    git -C "$dir" config --bool core.bare true
    git -C "$dir" config --unset core.worktree 2>/dev/null || true
    # Without a format version git ignores core.bare and treats $dir as a checkout of HEAD.
    git -C "$dir" config core.repositoryformatversion >/dev/null || git -C "$dir" config core.repositoryformatversion 0

    # git worktree add needs an empty target, so it runs elsewhere and its .git file is moved in.
    staging="$(mktemp -d)"
    git -C "$dir" worktree add --quiet --no-checkout --force "$staging/${branch##*/}" "$branch"
    mv -- "$staging/${branch##*/}/.git" "$work/.git"
    rmdir -- "$staging/${branch##*/}" "$staging"
    git -C "$dir" worktree repair "$work"
    admin="$(git -C "$work" rev-parse --absolute-git-dir)"
    [[ ! -f "$dir/.bare/index" ]] || mv -f -- "$dir/.bare/index" "$admin/index"

    repoint_submodules "$work" "$dir/.git/" "$dir/.bare/" "$dir"
    git -C "$work" status --short >/dev/null
    echo "Converted $dir to .bare with worktree $branch"
    exit 0
fi

[[ ! -e "$dir/.git" && -f "$dir/HEAD" && -d "$dir/objects" && -d "$dir/refs" ]] \
    || die "$dir is neither a normal checkout nor a flat bare repo"

# Worktrees stay put; every other non-dot entry at the root is a git internal.
worktrees=()
tops=()
while IFS= read -r path; do
    [[ "$path" == "$dir/"* ]] || continue
    worktrees+=("$path")
    tops+=(! -name "$(cut -d/ -f1 <<< "${path#"$dir/"}")")
done < <(git -C "$dir" worktree list --porcelain | sed -n 's/^worktree //p')

# Only git's own entries move into .bare; anything else at the root (a nested repo, notes) is the
# user's and stops the conversion rather than being buried in .bare.
internals='^(HEAD|config|description|hooks|info|objects|refs|packed-refs|logs|worktrees|modules|index|FETCH_HEAD|ORIG_HEAD|COMMIT_EDITMSG|AUTO_MERGE|shallow|lfs|branches|rr-cache|MERGE_RR|peer-sync|\.remotes-backup)$'
unknown="$(find "$dir" -mindepth 1 -maxdepth 1 ! -name '.*' "${tops[@]}" -printf '%f\n' | grep -vE "$internals" || true)"
[[ -z "$unknown" ]] || die "$dir has entries that aren't git internals or worktrees, so it wasn't converted: $(tr '\n' ' ' <<< "$unknown")"

mkdir -- "$dir/.bare"
find "$dir" -mindepth 1 -maxdepth 1 "${tops[@]}" -printf '%f\n' | grep -E "$internals" | while IFS= read -r entry; do
    mv -n -- "$dir/$entry" "$dir/.bare/"
done
printf 'gitdir: ./.bare\n' > "$dir/.git"
git --git-dir="$dir/.bare" config core.repositoryformatversion >/dev/null || git --git-dir="$dir/.bare" config core.repositoryformatversion 0

for work in "${worktrees[@]}"; do
    [[ -f "$work/.git" ]] && sed -i "s|^gitdir: $dir/worktrees/|gitdir: $dir/.bare/worktrees/|" "$work/.git"
    repoint_submodules "$work" "$dir/modules/" "$dir/.bare/modules/"
    repoint_submodules "$work" "$dir/worktrees/" "$dir/.bare/worktrees/"
done
(( ${#worktrees[@]} == 0 )) || git -C "$dir" worktree repair "${worktrees[@]}"
git -C "$dir" rev-parse --is-bare-repository >/dev/null
echo "Converted $dir from flat bare to .bare"
