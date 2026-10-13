#!/usr/bin/env python3
"""Fit the active window into the padded center of its current monitor."""

import json
import subprocess
import sys


def query(name):
    return json.loads(subprocess.check_output(["hyprctl", name, "-j"], text=True))


def geometry(monitor):
    width, height = monitor["width"], monitor["height"]
    if monitor.get("transform", 0) % 2:
        width, height = height, width
    width = round(width / monitor["scale"])
    height = round(height / monitor["scale"])
    left, top, right, bottom = monitor.get("reserved", [0, 0, 0, 0])
    # Match the game workspace's 1900px side gaps at 7680px wide.
    padding = round(width * 1900 / 7680) if width / height > 3 else 20
    left, right = max(left, padding), max(right, padding)
    window_width = max(1, width - 2 * max(left, right))
    window_height = max(1, height - top - bottom)
    x = monitor["x"] + (width - window_width) // 2
    y = monitor["y"] + top
    return x, y, window_width, window_height


def main():
    window = query("activewindow")
    address = window.get("address")
    if not address:
        return
    monitor = next(m for m in query("monitors") if m["id"] == window["monitor"])
    x, y, width, height = geometry(monitor)
    selector = json.dumps("address:" + address)
    commands = [
        f'fullscreen_state({{ window = {selector}, internal = 0, client = -1, action = "set" }})',
        f'float({{ window = {selector}, action = "set" }})',
        f'resize({{ window = {selector}, x = {width}, y = {height}, relative = false }})',
        f'move({{ window = {selector}, x = {x}, y = {y}, relative = false }})',
    ]
    for command in commands:
        result = subprocess.check_output(
            ["hyprctl", "dispatch", "hl.dsp.window." + command], text=True
        ).strip()
        if result != "ok":
            raise RuntimeError(result)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, StopIteration, subprocess.CalledProcessError, RuntimeError) as error:
        sys.exit(f"center-window: {error}")
