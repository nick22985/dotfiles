#!/usr/bin/env bash
# Convert a normal checkout into the flat bare layout (git internals at the root, the checked-out
# branch as the worktree <dir>/<branch>) without losing anything: every file, including local
# changes, untracked and ignored files, moves into the worktree, and the old index moves with it
# so staged changes stay staged. Submodules are re-pointed at their moved git directories.
#
#   scripts/convert-to-bare.sh <checkout>
set -euo pipefail

die() { echo "convert-to-bare: $*" >&2; exit 1; }

[[ $# -eq 1 ]] || die "usage: $0 <checkout>"
dir="$(realpath -- "$1")"
[[ -d "$dir/.git" && ! -L "$dir/.git" ]] || die "$dir is not a normal checkout (no .git directory)"
branch="$(git -C "$dir" symbolic-ref -q --short HEAD)" || die "$dir has a detached HEAD"
git -C "$dir" rev-parse -q --verify "HEAD^{commit}" >/dev/null || die "$dir has no commits on $branch"
for state in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG rebase-merge rebase-apply index.lock; do
    [[ ! -e "$dir/.git/$state" ]] || die "$dir has a $state in progress"
done
[[ -z "$(git -C "$dir" worktree list --porcelain | sed -n '2,$p' | grep '^worktree ')" ]] \
    || die "$dir already has linked worktrees"
top="${branch%%/*}"
[[ ! -e "$dir/$top" ]] || die "$dir/$top already exists; it would collide with the worktree for $branch"
[[ ! -e "$dir/.git/$top" ]] || die "branch $branch collides with .git/$top"

work="$dir/$branch"
mkdir -p -- "$work"
# Move the working tree first, then the git directory, so a failure leaves .git in place.
find "$dir" -mindepth 1 -maxdepth 1 ! -name .git ! -name "$top" -exec mv -n -t "$work/" -- {} +
[[ -z "$(find "$dir" -mindepth 1 -maxdepth 1 ! -name .git ! -name "$top" -print -quit)" ]] \
    || die "some files could not be moved into $work; nothing else was changed"
find "$dir/.git" -mindepth 1 -maxdepth 1 -exec mv -n -t "$dir/" -- {} +
rmdir -- "$dir/.git"
git -C "$dir" config --bool core.bare true
git -C "$dir" config --unset core.worktree 2>/dev/null || true

# git worktree add needs an empty target, so it runs elsewhere and its .git file is moved in.
staging="$(mktemp -d)"
git -C "$dir" worktree add --quiet --no-checkout --force "$staging/${branch##*/}" "$branch"
mv -- "$staging/${branch##*/}/.git" "$work/.git"
rmdir -- "$staging/${branch##*/}" "$staging"
git -C "$dir" worktree repair "$work"
admin="$(git -C "$work" rev-parse --absolute-git-dir)"
[[ ! -f "$dir/index" ]] || mv -f -- "$dir/index" "$admin/index"

# Submodule .git files and core.worktree still point through the old <dir>/.git/modules path.
while IFS= read -r -d '' gitfile; do
    submodule="$(dirname -- "$gitfile")"
    target="$(sed -n 's/^gitdir: //p' "$gitfile")"
    [[ "$target" == /* ]] || target="$(realpath -m -- "$dir/${submodule#"$work"/}/$target")"
    [[ "$target" == "$dir/.git/modules/"* ]] || continue
    module_dir="$dir/modules/${target#"$dir/.git/modules/"}"
    [[ -d "$module_dir" ]] || continue
    printf 'gitdir: %s\n' "$(realpath -m --relative-to="$submodule" -- "$module_dir")" > "$gitfile"
    git config -f "$module_dir/config" core.worktree "$(realpath -m --relative-to="$module_dir" -- "$submodule")"
done < <(find "$work" -mindepth 2 -name .git -type f -print0)

git -C "$work" status --short >/dev/null
echo "Converted $dir to flat bare with worktree $branch"
