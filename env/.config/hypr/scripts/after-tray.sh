#!/bin/bash
# Runs a command once the tray watcher is on the session bus, giving up the wait after 10s. Electron
# apps such as Discord and Slack only look for it when they start, and never show a tray icon without it.

for _ in {1..100}; do
    busctl --user status org.kde.StatusNotifierWatcher >/dev/null 2>&1 && break
    sleep 0.1
done
exec "$@"
