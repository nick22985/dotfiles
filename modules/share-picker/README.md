# Screen share picker

[hyprland-preview-share-picker](https://github.com/WhySoBad/hyprland-preview-share-picker) replaces xdg-desktop-portal-hyprland's picker with one that shows previews of windows and monitors. `env/.config/hypr/xdph.conf` sets it as the portal's `custom_picker_binary`.

`allow_token_by_default` in the same file pre-ticks "allow a restore token". Chromium browsers (Brave) make two portal requests per share, and the token lets the second one through without another prompt.

## Why it's patched

v0.3.0 leaves every preview blank on Hyprland 0.56. Its debug log (`debug: true` in `~/.config/hyprland-preview-share-picker/config.yaml`, written to `/tmp/hyprland-preview-share-picker.log`) shows:

```
Protocol error 4294967295 on object wl_shm_pool@27: The size of the file is not big enough for the shm pool
```

- It sized each window's shm pool as `width * height * 4` in `u32`, ignoring the stride Hyprland asks for. A window with odd dimensions overflows that, and Hyprland kills the connection.
- Every window capture and the monitor view shared that one connection, so one bad window blanked everything.

The fix is on the `fix/shm-pool-size-and-isolated-captures` branch of [the fork](https://github.com/nick22985/hyprland-preview-share-picker). It sizes the pool from `stride * height`, refuses sizes Hyprland can't accept, strips row padding when reading the frame and gives each window capture its own connection. The `PKGBUILD` pins that commit and clones it over SSH, so the machine needs its GitHub key. `install` builds it through `paru -B` as `hyprland-preview-share-picker-patched`, so the AUR package can't replace it.

To move to a newer commit, update `#commit=` in the `PKGBUILD` and bump `pkgrel`.

After changing `xdph.conf`, run `systemctl --user restart xdg-desktop-portal-hyprland`.
