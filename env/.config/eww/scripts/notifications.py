#!/usr/bin/env python3
"""Notification history for the control center's Notifications page.

    notifications.py listen        print {"count", "items"} as JSON whenever the history changes
    notifications.py dismiss <id>  close one notification
    notifications.py open <id>     focus the window of the app that sent it, then close it
    notifications.py clear         close every notification

swaync has no way to list its notifications, so the listener watches the notification traffic on
the session bus instead: every Notify call is kept, and a notification goes when swaync reports it
dismissed or closed. Popups that time out stay, as they do in swaync's own panel. Closing goes
through swaync too, so both lists agree. The history lives in the runtime directory, so it
survives an eww restart but not a reboot.

Notifications come from other programs, so their text is only ever shown as label text and
commands carry the numeric id.
"""

import fcntl
import html
import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
from contextlib import contextmanager
from pathlib import Path
from queue import Empty, Queue

RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/eww-{os.getuid()}")
STATE = RUNTIME / "eww-notifications.json"
LOCK = RUNTIME / "eww-notifications.lock"
PID = RUNTIME / "eww-notifications.pid"
LIMIT = 50
BODY_LIMIT = 160
BUS_NAME = "org.freedesktop.Notifications"
BUS_PATH = "/org/freedesktop/Notifications"
# NotificationClosed reasons that mean the notification is gone, not just its popup.
GONE = {2, 3, 4}
ICON_DIRS = [
    Path.home() / ".local/share/icons",
    Path("/usr/share/icons"),
]
ICON_SIZES = ["scalable", "48x48", "64x64", "128x128", "256x256", "32x32", "48"]
ICON_KINDS = ["apps", "status", "devices", "categories", "actions"]

reload_requested = threading.Event()


@contextmanager
def locked():
    """Holds the history's lock for the duration of a with block."""
    RUNTIME.mkdir(parents=True, exist_ok=True)
    with open(LOCK, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def load():
    try:
        items = json.loads(STATE.read_text(encoding="utf-8"))
        return items if isinstance(items, list) else []
    except (OSError, ValueError):
        return []


def save(items):
    part = STATE.with_suffix(".part")
    part.write_text(json.dumps(items[:LIMIT]), encoding="utf-8")
    part.replace(STATE)


def change(edit):
    """Applies edit to the stored history under the lock and returns the result."""
    with locked():
        items = edit(load())
        save(items)
    return items


def plain(text, limit):
    """Notification markup as one line of plain text."""
    text = re.sub(r"<[^>]*>", " ", text or "")
    text = re.sub(r"\s+", " ", html.unescape(text)).strip()
    text = text if len(text) <= limit else text[: limit - 1].rstrip() + "…"
    # A break chance inside long runs such as links, so one long word can't widen the panel.
    return re.sub(r"(\S{24})(?=\S)", "\\1\u200b", text)


def icon_theme():
    for settings in (Path.home() / ".config/gtk-3.0/settings.ini", Path("/etc/gtk-3.0/settings.ini")):
        try:
            match = re.search(r"^gtk-icon-theme-name\s*=\s*(.+)$", settings.read_text(), re.M)
        except OSError:
            continue
        if match:
            return match.group(1).strip().strip('"')
    return ""


def find_icon(name):
    """A file for an icon given as a path, a file:// url or a theme icon name; "" if none."""
    if not name:
        return ""
    if name.startswith("file://"):
        name = name[len("file://"):]
    if name.startswith("/"):
        # Shown through a CSS url(), so only plain paths.
        return name if re.fullmatch(r"[\w./+ -]+", name) and os.path.isfile(name) else ""
    if not re.fullmatch(r"[\w.+-]+", name):
        return ""
    themes = [theme for theme in (icon_theme(), "hicolor", "Adwaita") if theme]
    for theme in themes:
        for base in ICON_DIRS:
            for size in ICON_SIZES:
                for kind in ICON_KINDS:
                    for extension in ("svg", "png"):
                        path = base / theme / size / kind / f"{name}.{extension}"
                        if path.is_file():
                            return str(path)
    for extension in ("svg", "png"):
        path = Path("/usr/share/pixmaps") / f"{name}.{extension}"
        if path.is_file():
            return str(path)
    return ""


def hint(hints, key):
    value = hints.get(key)
    return value.get("data") if isinstance(value, dict) else None


def entry(data, timestamp):
    """A history entry from a Notify call's arguments, or None for one swaync wouldn't keep."""
    app, _replaces, app_icon, summary, body, _actions, hints, _timeout = data
    hints = hints if isinstance(hints, dict) else {}
    if hint(hints, "transient"):
        return None
    desktop = hint(hints, "desktop-entry") or ""
    icon = find_icon(hint(hints, "image-path") or "") or find_icon(app_icon) or find_icon(desktop) or find_icon(desktop.lower())
    urgency = hint(hints, "urgency")
    return {
        "id": 0,
        "sync": hint(hints, "x-canonical-private-synchronous") or "",
        "app": plain(app, 40),
        "desktop": desktop,
        "summary": plain(summary, 80),
        "body": plain(body, BODY_LIMIT),
        "icon": icon,
        "urgency": {0: "low", 2: "critical"}.get(urgency, "normal"),
        "time": int(timestamp),
    }


def add(items, new):
    """Puts new at the top, in place of the notification it replaces."""
    def replaced(item):
        return item["id"] == new["id"] or (new["sync"] and item.get("sync") == new["sync"] and item["app"] == new["app"])

    return [new] + [item for item in items if not replaced(item)]


def ago(timestamp, now):
    seconds = max(0, now - timestamp)
    if seconds < 60:
        return "now"
    if seconds < 3600:
        return f"{seconds // 60}m"
    if seconds < 86400:
        return f"{seconds // 3600}h"
    return time.strftime("%a" if seconds < 6 * 86400 else "%d %b", time.localtime(timestamp))


def render(items):
    now = int(time.time())
    shown = [
        {key: item[key] for key in ("id", "app", "summary", "body", "icon", "urgency")} | {"ago": ago(item["time"], now)}
        for item in items
    ]
    return json.dumps({"count": len(shown), "items": shown}, ensure_ascii=False, separators=(",", ":"))


def watch_bus(queue):
    """Feeds every bus message to and from the notification server into queue, restarting busctl if it stops."""
    command = ["stdbuf", "-oL", "busctl", "--user", "monitor", "--json=short", BUS_NAME]
    while True:
        try:
            with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True) as process:
                for line in process.stdout:
                    try:
                        queue.put(json.loads(line))
                    except ValueError:
                        pass
        except OSError:
            pass
        time.sleep(2)


def swaync_count():
    try:
        return int(subprocess.run(["swaync-client", "-c"], capture_output=True, text=True, timeout=2).stdout.strip())
    except (OSError, ValueError, subprocess.SubprocessError):
        return None


def listen():
    queue = Queue()
    pending = {}
    PID.parent.mkdir(parents=True, exist_ok=True)
    PID.write_text(str(os.getpid()))
    signal.signal(signal.SIGUSR1, lambda *_: reload_requested.set())
    threading.Thread(target=watch_bus, args=(queue,), daemon=True).start()

    # Whatever swaync dropped while eww wasn't running is gone for good.
    items = change(lambda items: [] if swaync_count() == 0 else items)
    last = ""
    while True:
        output = render(items)
        if output != last:
            print(output, flush=True)
            last = output
        # A short wait, so a reload request and the "5m ago" times never lag far behind.
        try:
            message = queue.get(timeout=1)
        except Empty:
            message = None
        if reload_requested.is_set():
            reload_requested.clear()
            with locked():
                items = load()
        if message is None:
            continue
        kind, member = message.get("type"), message.get("member")
        data = (message.get("payload") or {}).get("data") or []
        if kind == "method_call" and member == "Notify" and len(data) == 8:
            new = entry(data, message.get("timestamp-realtime", time.time() * 1e6) / 1e6)
            if new:
                pending[(message.get("sender"), message.get("cookie"))] = new
                while len(pending) > 100:
                    pending.pop(next(iter(pending)))
        elif kind == "method_return":
            new = pending.pop((message.get("destination"), message.get("reply_cookie")), None)
            if new and data:
                new["id"] = data[0]
                items = change(lambda items: add(items, new))
        elif kind == "signal" and member == "NotificationClosed" and len(data) == 2 and data[1] in GONE:
            items = change(lambda items: [item for item in items if item["id"] != data[0]])


def poke():
    """Has the listener reload the history."""
    try:
        os.kill(int(PID.read_text()), signal.SIGUSR1)
    except (OSError, ValueError):
        pass


def close(notification):
    subprocess.run(
        ["gdbus", "call", "--session", "--dest", BUS_NAME, "--object-path", BUS_PATH,
         "--method", f"{BUS_NAME}.CloseNotification", str(notification)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3,
    )


def dismiss(notification):
    close(notification)
    change(lambda items: [item for item in items if item["id"] != notification])
    poke()


def open_app(notification):
    """Focuses the newest window whose class matches the sending app, if there is one."""
    found = next((item for item in load() if item["id"] == notification), None)
    if found:
        names = {name.lower() for name in (found.get("desktop"), found.get("app")) if name}
        try:
            clients = json.loads(subprocess.run(["hyprctl", "-j", "clients"], capture_output=True, text=True, timeout=2).stdout)
        except (OSError, ValueError, subprocess.SubprocessError):
            clients = []
        matches = [client for client in clients if client.get("class", "").lower() in names]
        if matches:
            newest = min(matches, key=lambda client: client.get("focusHistoryID", 1 << 30))
            subprocess.run(["hyprctl", "dispatch", "focuswindow", f"address:{newest['address']}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
    dismiss(notification)


def clear():
    subprocess.run(["swaync-client", "-C", "-sw"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3)
    change(lambda items: [])
    poke()


def notification_id(argument):
    if not re.fullmatch(r"[0-9]+", argument or ""):
        sys.exit(f"Invalid notification id: {argument}")
    return int(argument)


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    argument = sys.argv[2] if len(sys.argv) > 2 else ""
    if command == "listen":
        listen()
    elif command == "dismiss":
        dismiss(notification_id(argument))
    elif command == "open":
        open_app(notification_id(argument))
    elif command == "clear":
        clear()
    else:
        sys.exit(f"Usage: {sys.argv[0]} {{listen|dismiss <id>|open <id>|clear}}")


if __name__ == "__main__":
    main()
