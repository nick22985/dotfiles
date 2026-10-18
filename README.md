# Installer design

The runner first resolves and prints a complete plan. Only `apply` mutates the
machine. Run it as the normal user; the runner obtains sudo only when a selected
module requires it.

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
./run list
./run list profiles
./run list modules
./run show docker
./run show development
```

Bare `./run` shows help. An option-only invocation is rejected. `apply` uses an
exclusive lock, so two installs cannot run concurrently. A failed prerequisite
causes its dependent modules to be skipped and the run to fail.
Module `install` scripts are private to the runner and reject direct use.

`./run list` shows every profile (with the platforms it runs on) and every module
in run order. `./run show NAME` describes one profile or module: what it includes,
which profiles and hosts use it, its dependencies, and the packages, services,
groups and files it manages on each platform.

`self-update` is separate from `apply`. It refuses dirty worktrees and detached
HEADs, pulls with `--ff-only`, updates pinned submodules, and exits.

## Profiles and desktops

Profiles are additive. `core` is always included.

- `core`: shell, Git, user dotfiles, tmux, periodic TRIM, and package cache cleanup
- `development`: Java, pinned mise tools (Node, Bun, Rust), Docker, repositories, private home files, sbx, snd, shot, Syncthing project sync, and git peer fetches
- `desktop`: Flatpaks, defaults, clipboard tools, Bluetooth, and a desktop selection
- `system`: GRUB, multiboot, Timeshift snapshot boot entries, weekly mirror refresh, and system monitors
- `virtualization`: QEMU, libvirt, and VM tools
- `hardware`: device, SDR, firmware update checks, and printing tools
- `security`: network and host security packages, Tailscale, and the ufw firewall
- `media`: audio, recording, and media packages
- `ssh-server`: opt-in key-only SSH daemon configuration
- `gpu-amd`, `gpu-intel`, `gpu-nvidia`: graphics drivers for the machine's GPUs (NVIDIA also enables its suspend handling)
- `laptop`: power profiles, thermal management, and fingerprint sudo
- `kube`: Ubuntu Kubernetes nodes; mise with pinned kubectl, helm, neovim, starship and fd, and on k3s servers the admin kubeconfig copied to `~/.kube/config`
- `full`: all general workstation profiles, excluding `ssh-server`, the GPU
  profiles, and `laptop`

Desktop selections are `hyprland`, `plasma`, and `both`. Hyprland is the default
for an explicitly selected desktop profile.

`hosts/default.conf` supplies the selection used when no `--profile`,
`--desktop`, or `--host` option is given. This installation defaults to the
`desktop` profile with both desktops. Explicit selection options bypass it, so
`./run plan --profile core` remains a core-only plan.

Host presets in `hosts/*.conf` save selections without embedding
secrets or hardware identifiers:

```text
platform arch
profile development
profile desktop
desktop both
skip snap
```

`include NAME` loads another preset first, so machines share one base selection
and add only their hardware. `common.conf` holds the profiles every machine
gets; `overlord.conf` and `kirito.conf` include it and add their GPU and laptop
profiles. `kube.conf` is the Ubuntu server selection for Kube-01..04: `core` plus `kube`. Presets may include several others (for example a shared `laptop`
preset), and each preset loads once however often it is included.

## Desired-state files

The installer and auditor consume the same manifests. Each step of a run is a module:

- `modules/order.list`: the order modules run in, one name per line
- `modules/<name>/module.conf`: `description`, `root yes|no`, `depends a b`, `platforms arch ubuntu`, `risk normal|high`
- `modules/<name>/install`: the module script on Arch and Ubuntu; `install.ps1` on Windows
- `modules/<name>/packages.list`: packages the module owns
- `modules/<name>/services.<platform>.list`: system and user units
- `modules/<name>/groups.<platform>.list`: required user groups
- `modules/<name>/files.<platform>.list`: privileged files, modes, and sources relative to the module (`system/etc/...`)
- `modules/flatpak/apps.list`: user-level Flatpak IDs
- `modules/defaults/defaults.list`: user desktop properties applied through xdg-settings

Each profile is a directory:

- `profiles/<name>/profile.conf`: `description`, `platforms`, `include <profile>` (expanded first), `module <name>`, and `desktop <selection>` for the desktop variants
- `profiles/<name>/packages.list`: profile packages
- `profiles/<name>/dotfiles.list`: profile-scoped paths below `env/`
- `profiles/<name>/tools.list`: exact versions installed through mise

`desktop-hyprland` and `desktop-plasma` are not selected directly; `desktop`
pulls them in according to the desktop selection. `full` includes every general
workstation profile.

A `packages.list` is a table: a `package <platform>...` header naming the
platform columns it has, then one row per package. Each cell says how that
platform installs the package:

```
package        arch            ubuntu            windows
git            =               =                 Git.Git
base-devel     =               build-essential   -
paru           aur:paru        -                 -
```

`=` uses the row name, a plain name renames it, `source:name` also picks the
source, and `-` leaves it out. Default sources are `repo` on Arch, `apt` on
Ubuntu and `winget` on Windows. A platform without a column installs nothing
from that table. `./run doctor` checks every table's shape on every platform.
The tables in `tests/fixtures/package-tables/` record what each platform's
parser must resolve (`# expect <platform>: ...`); `tests/run` checks the bash
parser and `tests/windows` the PowerShell one against them.

On Arch, package sources are `repo`, `multilib`, `aur`, and `group`. `multilib` packages
enable the multilib repository in `/etc/pacman.conf` first (backed up into the
run receipt). On first use of an AUR package, the Arch backend builds `paru` from
source from the official AUR repository at the exact commit in
`modules/packages/paru.conf`, falling back to the `paru` branch of the
GitHub AUR mirror when the AUR is unreachable. Later runs reuse the installed `paru`.
Review the upstream PKGBUILD before intentionally updating that pin.

On Ubuntu, package sources are `apt` for the Ubuntu archive or the name of a
third-party repository in `modules/packages/apt-repositories.list`. A repository is
added the first time one of its packages is needed, only if its downloaded signing
key has the pinned fingerprint; the keyring and `.sources` file get a `dotfiles-`
prefix and their removal is written to the run receipt.

Dotfile directories merge at file level. The installer never replaces an
entire `~/.gnupg`, `~/.local/bin`, or other shared directory. Conflicting
managed files are moved into the run receipt before a symlink is created.

## Safety and recovery

Every apply writes a receipt below
`${XDG_STATE_HOME:-~/.local/state}/dotfiles/runs/` containing the plan, Git
commit, module results (`modules.tsv`), exit status, backup identifier, and
changed-file backups. `latest` points to the newest receipt. Each change a module
makes adds a record to `restore.d/user/` or `restore.d/system/`; the generated
`restore-user.sh` and `restore-system.sh` run those records newest first, so a
path changed twice in one run goes back to how it was before the run.

Modules marked `high` require a configured Timeshift snapshot and fail closed if
one cannot be created. SSH uses a managed drop-in and validates the effective
configuration before restarting. GRUB edits use receipt backups and atomic
configuration generation. Remote GRUB theme installers are intentionally not
run.

Repository sync accepts only `owner/repository` declarations or canonical
GitHub URLs, writes only below the configured roots in `$HOME`, refuses non-Git
collisions, and clones through a temporary directory before the final rename.

## Audit

`audit` uses `hosts/default.conf` when no selection option is supplied and is
read-only. It checks selected
packages and package groups, user Flatpaks, exact managed-file links and modes,
privileged file contents and modes, enabled and active services, required group
membership, and unmanaged config or executable candidates.

`--check` exits 0 when selected state matches, 1 for visible drift, and 2 when a
required check cannot run. `.audit-install-ignore` supports scoped exceptions;
`--show-hidden` ignores those exceptions.

## Windows

`run.ps1` is the Windows runner. It reads the same `modules/`, `profiles/` and
`hosts/` and works in Windows PowerShell 5.1 and PowerShell 7:

```powershell
powershell -ExecutionPolicy Bypass -File .\run.ps1 list
powershell -ExecutionPolicy Bypass -File .\run.ps1 plan --host windows
powershell -ExecutionPolicy Bypass -File .\run.ps1 apply --host windows --dry
powershell -ExecutionPolicy Bypass -File .\run.ps1 apply --host windows
powershell -ExecutionPolicy Bypass -File .\run.ps1 audit --host windows --check
powershell -ExecutionPolicy Bypass -File .\run.ps1 doctor
```

Modules whose `platforms` include `windows` have an `install.ps1`:

- `packages`: the `windows` column through winget, sources `winget` and `msstore`.
  Needs winget (App Installer from the Microsoft Store).
- `git`: checks Git, SSH keys and the GPG key `env/.gitconfig` signs with, and
  sets `gpg.program` in `~/.gitconfig.local` to Gpg4win's gpg (Git for Windows
  otherwise uses its bundled gpg and keyring). Import the signing key with
  `gpg --import`; commits fail until it is there.
- `dotfiles`: the links below.
- `mise`: the `tools.list` pins, as on Linux, and `%LOCALAPPDATA%\mise\shims` on
  the user PATH. Add `--profile development` to get mise and its tools.

Other development modules and the desktop profiles are Linux-only.

`audit` checks the selected packages, dotfile links and mise tools, read-only.
With `--check` it exits 1 for differences and 2 when winget or mise is missing.

Windows programs read config from their own places, so
`modules/dotfiles/links.windows.list` maps a path below `env/` to its Windows
target (`~` is the user profile, `%VAR%` is expanded). A link applies when its
path is in a selected profile's `dotfiles.list`. Directories become symbolic
links, or junctions when symlinks are not allowed; files need symbolic links, so
turn on Developer Mode (Settings > System > For developers) or run from an
administrator shell. Clone with `git -c core.symlinks=true` so links inside the
repository stay links.

Receipts are in `%LOCALAPPDATA%\dotfiles\runs\<id>\`. A replaced file or
directory is moved into the receipt's `backups\user`, and `restore-user.ps1`
runs the `restore.d\user` records newest first: it removes the links (never what
they point at), moves the backups back and undoes the PATH and `gpg.program`
changes.

`tests/windows` runs `run.ps1` under PowerShell 7 on Linux with fake winget,
mise and gpg commands; `tests/run` runs it too when `pwsh` is installed.

## Platform boundary

Arch Linux, Ubuntu and Windows are implemented. Platform detection and activation live in
`lib/platforms.sh`; package operations live in `lib/platforms/arch.sh` and
`lib/platforms/ubuntu.sh`, and the systemd, group and system file operations both
share are in `lib/platforms/common.sh`. Another OS adds a backend and
platform-specific manifests without changing profile, host, module, receipt, or
audit concepts. A profile module the platform has no version of (the `platforms`
line of its `module.conf`) is left out of the plan; profiles whose `platforms` line excludes
the platform, and dependencies on such modules fail during planning, before mutation.
