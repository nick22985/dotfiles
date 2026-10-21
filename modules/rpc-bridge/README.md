# Discord in Proton games with Flatpak Discord

Two parts, because Flatpak Discord misses two different things from Proton games:

| Part | What it gives | Files |
| --- | --- | --- |
| rpc-bridge | Rich Presence from games that send their own (status text, party, timers) | this module, `env/.config/hypr/conf/env.lua`, `env/.config/hypr/conf/autostart.lua` |
| game-presence | Game detection: "Playing …", Registered Games, game activity for Discord's game badges | `env/.local/bin/game-presence`, `env/.config/systemd/user/game-presence.service` |

Rich Presence alone doesn't count as playing a detected game, so the badges need game-presence.

## rpc-bridge

Windows games talk to Discord through a named pipe (`\\.\pipe\discord-ipc-0`). Under Proton that pipe only exists inside Wine, so Discord on the host never sees it. [rpc-bridge](https://github.com/EnderIce2/rpc-bridge)'s `bridge.exe` runs inside each game's Wine prefix, creates the pipe and forwards it to Discord's `discord-ipc-*` socket on the host. Flatpak Discord exposes that socket by itself.

- `install` downloads `bridge.exe` to `~/.local/share/rpc-bridge/` and checks its sha256.
- `hypr/conf/env.lua` sets these for the whole session:
  - `PROTON_REMOTE_DEBUG_CMD` makes Proton start `bridge.exe --steam` alongside every game.
  - `PRESSURE_VESSEL_FILESYSTEMS_RW` makes `bridge.exe` visible inside Steam's runtime container.
  - `BRIDGE_PATH` is where rpc-bridge's own scripts look for it.

  This is what rpc-bridge's per-game launch option (`bridge.sh %command%`) does, but for every game.
- `hypr/conf/autostart.lua` passes the variables on to the user services, so Steam started from walker gets them too. Steam started from a terminal that predates the session won't have them.

### Why it's pinned to 1.4.1.2

Proton's Wine has no `AF_UNIX` sockets, so the bridge can't open Discord's socket through Wine. It falls back to raw Linux syscalls instead. Since 1.4.1.3, rpc-bridge only uses that fallback when it detects a Wine Staging build. Proton isn't Staging, so 1.4.1.3 quits. There is no newer release, and the AUR package (`rpc-bridge-bin`) would update to 1.4.1.3, so the module installs 1.4.1.2 itself.

If presence stops working, check the bridge log for `v1.4.1.3` or a `Wine Staging` message.

## game-presence

Discord detects games by scanning running processes. Flatpak Discord's sandbox only sees its own processes, so it never detects a game. game-presence runs on the host, finds the game and starts a fake process inside Discord's sandbox that looks like the game.

1. Every week it caches Discord's list of detectable games (`https://discord.com/api/v9/applications/detectable`) in `~/.cache/game-presence/games.tsv`. Each game lists Windows executable path suffixes (`overwatch.exe`, `_retail_/wow.exe`), and Steam games also list their Steam app id.
2. Every 10 seconds it matches the host's processes against that list by their Windows path (`S:\steamapps\common\Overwatch\Overwatch.exe`), trying the last few path components.
3. When a game matches, it joins Discord's sandbox:
   ```
   flatpak run --parent-pid=<Discord's pid> --parent-share-pids --die-with-parent --command=bash com.discordapp.Discord
   ```
   There it copies `sleep` to the game's path under the sandbox's `/tmp` (`/tmp/game-presence/steamapps/common/Overwatch/Overwatch.exe`) and runs it with `exec -a 'S:\steamapps\common\Overwatch\Overwatch.exe'`.
4. When the game exits, the stand-in is killed. It also ends when Discord quits.

### Gotchas

- Discord matches on the executable path, the process name and the command line. Renaming argv0 alone isn't detected, so the stand-in has to be a real file with the game's name.
- Discord's image loaders and renderers run in sandboxes of their own, and `flatpak ps` lists them as `com.discordapp.Discord` too. Joining one of those puts the stand-in where Discord can't see it. game-presence picks the instance whose command line runs `-- com.discordapp.Discord`.
- Over half of Discord's detectable apps list no executables (MECCHA CHAMELEON, for one). For those, game-presence reads the `SteamAppId` that Steam sets in the game's environment, looks up the game's name and names the stand-in `MECCHA CHAMELEON.exe`. Discord detects that by name, without adding the game by hand.
- Executables with launch arguments, or names starting with `>`, only match particular command lines, which the stand-in doesn't copy, so they're skipped. Launchers are skipped too.

### Checking it

```
systemctl --user status game-presence
pgrep -af game-presence | cut -c1-160
```

While a game runs, Discord's Settings → Activity Settings → Registered Games should show it as playing.
