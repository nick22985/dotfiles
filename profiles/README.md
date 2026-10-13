# Installer design

The runner first resolves and prints a complete plan. Only `apply` mutates the
machine. Run it as the normal user; the runner obtains sudo only when a selected
stage requires it.

```bash
./run plan
./run apply
./run plan --profile desktop --desktop plasma
./run apply --profile desktop --desktop both
./run plan --host overlord
./run apply --host overlord --skip snap
./run audit --host overlord
./run audit --host overlord --check
./run doctor
./run self-update
./run list profiles
./run list stages
```

Bare `./run` shows help. An option-only invocation is rejected. `apply` uses an
exclusive lock, so two installs cannot run concurrently. A failed prerequisite
causes its dependent stages to be skipped and the run to fail.
Files below `runs/` are private stage implementations and reject direct use.

`self-update` is separate from `apply`. It refuses dirty worktrees and detached
HEADs, pulls with `--ff-only`, updates pinned submodules, and exits.

## Profiles and desktops

Profiles are additive. `core` is always included.

- `core`: shell, Git, user dotfiles, and tmux
- `development`: Java, pinned JavaScript runtimes, Docker, repositories, and sbx
- `desktop`: Flatpaks, defaults, clipboard tools, Bluetooth, and a desktop selection
- `system`: GRUB and multiboot configuration
- `virtualization`: QEMU, libvirt, and VM tools
- `hardware`: device, SDR, GPU, and printing tools
- `security`: network and host security packages
- `media`: audio, recording, and media packages
- `ssh-server`: opt-in key-only SSH daemon configuration
- `full`: all general workstation profiles, excluding `ssh-server`

Desktop selections are `hyprland`, `plasma`, and `both`. Hyprland is the default
for an explicitly selected desktop profile.

`profiles/default.conf` supplies the selection used when no `--profile`,
`--desktop`, or `--host` option is given. This installation defaults to the
`desktop` profile with both desktops. Explicit selection options bypass it, so
`./run plan --profile core` remains a core-only plan.

Host presets in `profiles/hosts/*.conf` save selections without embedding
secrets or hardware identifiers:

```text
platform arch
profile development
profile desktop
desktop both
skip snap
```

## Desired-state files

The installer and auditor consume the same manifests:

- `stages.tsv`: order, sudo requirement, dependencies, platform, risk, description
- `default.conf`: selection used when no profile, desktop, or host is specified
- `*.runs`: stages selected by each profile
- `packages/arch/*.list`: profile packages
- `packages/arch/stages/*.list`: packages owned by one stage
- `apps/*.flatpak`: user-level Flatpak IDs
- `dotfiles/*.list`: profile-scoped paths below `env/`
- `services/arch/*.list`: system and user units
- `groups/arch/*.list`: required user groups
- `files/arch/*.list`: privileged files, source paths, and modes
- `tools/*.list`: exact versions installed through mise
- `defaults/*.list`: user desktop properties applied through xdg-settings

Package sources are `repo`, `multilib`, `aur`, and `group`. `multilib` packages
enable the multilib repository in `/etc/pacman.conf` first (backed up into the
run receipt). On first use of an AUR package, the Arch backend builds `paru` from
source from the official AUR repository at the exact commit in
`bootstrap/arch/paru.conf`, falling back to the `paru` branch of the
GitHub AUR mirror when the AUR is unreachable. Later runs reuse the installed `paru`.
Review the upstream PKGBUILD before intentionally updating that pin.

Dotfile directories merge at file level. The installer never replaces an
entire `~/.gnupg`, `~/.local/bin`, or other shared directory. Conflicting
managed files are moved into the run receipt before a symlink is created.

## Safety and recovery

Every apply writes a receipt below
`${XDG_STATE_HOME:-~/.local/state}/dotfiles/runs/` containing the plan, Git
commit, stage results, exit status, backup identifier, and changed-file backups.
`latest` points to the newest receipt. Generated `restore-user.sh` and
`restore-system.sh` scripts provide explicit file recovery.

Stages marked `high` require a configured Timeshift snapshot and fail closed if
one cannot be created. SSH uses a managed drop-in and validates the effective
configuration before restarting. GRUB edits use receipt backups and atomic
configuration generation. Remote GRUB theme installers are intentionally not
run.

Repository sync accepts only `owner/repository` declarations or canonical
GitHub URLs, writes only below the configured roots in `$HOME`, refuses non-Git
collisions, and clones through a temporary directory before the final rename.

## Audit

`audit` uses `profiles/default.conf` when no selection option is supplied and is
read-only. It checks selected
packages and package groups, user Flatpaks, exact managed-file links and modes,
privileged file contents and modes, enabled and active services, required group
membership, and unmanaged config or executable candidates.

`--check` exits 0 when selected state matches, 1 for visible drift, and 2 when a
required check cannot run. `.audit-install-ignore` supports scoped exceptions;
`--show-hidden` ignores those exceptions.

## Platform boundary

Only Arch Linux is implemented. Platform detection and activation live in
`lib/platforms.sh`; Arch operations live in `lib/platforms/arch.sh`. Future OS
support adds a backend and platform-specific manifests without changing profile,
host, stage, receipt, or audit concepts. Unsupported platforms fail during
planning, before mutation.
