# Screen share picker

[hyprland-preview-share-picker](https://github.com/WhySoBad/hyprland-preview-share-picker) replaces xdg-desktop-portal-hyprland's picker with one that shows previews of windows and monitors. `env/.config/hypr/xdph.conf` sets it, through the wrapper below, as the portal's `custom_picker_binary`.

`allow_token_by_default` in the same file pre-ticks "allow a restore token". Chromium browsers (Brave) make two portal requests per share, and the token lets the second one through without another prompt.

## Why it's patched

v0.3.0 leaves every preview blank on Hyprland 0.56. Its debug log (`debug: true` in `~/.config/hyprland-preview-share-picker/config.yaml`, written to `/tmp/hyprland-preview-share-picker.log`) shows:

```
Protocol error 4294967295 on object wl_shm_pool@27: The size of the file is not big enough for the shm pool
```

- It sized each window's shm pool as `width * height * 4` in `u32`, ignoring the stride Hyprland asks for. A window with odd dimensions overflows that, and Hyprland kills the connection.
- Every window capture and the monitor view share that one connection, so one bad window blanked everything.

The fix is on the `fix/shm-pool-size-and-isolated-captures` branch of [the fork](https://github.com/nick22985/hyprland-preview-share-picker). It sizes the pool from `stride * height`, strips row padding when reading the frame and refuses sizes Hyprland can't accept before asking for the pool, so a bad window fails on its own and the shared connection survives. Each buffer's size is in the debug log. The `PKGBUILD` pins that commit and clones it over SSH, so the machine needs its GitHub key. `install` builds it through `paru -B` as `hyprland-preview-share-picker-patched`, so the AUR package can't replace it.

To move to a newer commit, update `#commit=` in the `PKGBUILD` and bump `pkgrel`.

## When a preview fails

The original failure couldn't be reproduced later, so xdph launches the picker through `hyprland-preview-share-picker-traced`, which the package installs next to it. Each share gets a directory in `~/.local/state/share-picker/` with:

- `picker.log`: the picker's debug log. A failed window shows as `unable to capture frame for toplevel <id>: unsupported buffer size …`, and the `toplevel = …` line with that id gives its title and address.
- `clients.json` and `monitors.json`: `hyprctl` snapshots from just before the picker opened, to look up what Hyprland reported for that address.

When a capture fails it sends a notification and marks the directory `failed`, which keeps it. Otherwise only the last 20 shares are kept. Changing the wrapper needs a `pkgrel` bump too, since `install` only rebuilds when the version changes.

After changing `xdph.conf`, run `systemctl --user restart xdg-desktop-portal-hyprland`.
