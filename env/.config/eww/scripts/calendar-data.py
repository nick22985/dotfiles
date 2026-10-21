#!/usr/bin/env python3
"""Month grid and events for the eww calendar popup.

    calendar-data.py month YYYY-MM [--quick]   print the month's grid and each shown day's events as JSON;
                                                --quick prints the cached month, or the bare grid if the
                                                cache is stale, without reading any calendar
    calendar-data.py sync [--force]            download calendars older than 15 minutes

Calendars are listed in ~/.config/calendars/sources.ini. Their addresses are private, so that file
comes from the private repository, not these dotfiles:

    [Personal]
    url = https://calendar.google.com/calendar/ical/.../basic.ics
    colour = #8aadf4

For Google, the url is the calendar's "Secret address in iCal format" (Settings, then the calendar,
then Integrate calendar). Any other iCal feed works too, and path = names a local .ics file instead.
"""

import configparser
import datetime as dt
import hashlib
import http.client
import json
import os
import re
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "calendars" / "sources.ini"
CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "eww" / "calendar"
ERRORS = CACHE / "errors.json"
STALE_AFTER = 15 * 60
# Bump when the output changes, so cached months are rebuilt.
FORMAT = 1
COLOURS = ["#8aadf4", "#a6da95", "#f5a97f", "#c6a0f6", "#ed8796", "#eed49f"]
ONE_DAY = dt.timedelta(days=1)
MISSING_LIBRARIES = "Install python-icalendar and python-recurring-ical-events to show events"


def sources():
    """The calendars in sources.ini as (name, colour, url, file); url is "" for a local file."""
    parser = configparser.ConfigParser(interpolation=None)
    try:
        parser.read(CONFIG, encoding="utf-8")
    except (configparser.Error, UnicodeDecodeError):
        return []
    found = []
    for index, name in enumerate(parser.sections()):
        section = parser[name]
        colour = section.get("colour", section.get("color", "")).strip()
        if not re.fullmatch(r"#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3})?", colour):
            colour = COLOURS[index % len(COLOURS)]
        url = section.get("url", "").strip()
        if url.startswith("webcal://"):
            url = "https://" + url[len("webcal://"):]
        if url:
            file = CACHE / (hashlib.sha1(url.encode()).hexdigest()[:16] + ".ics")
        elif section.get("path", "").strip():
            file = Path(section["path"].strip()).expanduser()
        else:
            continue
        found.append((name, colour, url, file))
    return found


def download(source, force):
    """Fetches one calendar feed; returns (name, error)."""
    name, _, url, file = source
    # Checked separately from the feed's own mtime, so an unchanged feed keeps its cached months.
    checked = file.with_suffix(".checked")
    try:
        if not force and dt.datetime.now().timestamp() - checked.stat().st_mtime < STALE_AFTER:
            return name, None
    except FileNotFoundError:
        pass
    try:
        request = urllib.request.Request(url, headers={"User-Agent": "eww-calendar"})
        with urllib.request.urlopen(request, timeout=20) as response:
            body = response.read()
    except (OSError, ValueError, http.client.HTTPException):
        return name, f"Couldn't refresh {name}"
    if b"BEGIN:VCALENDAR" not in body[:512]:
        return name, f"{name} isn't an iCal feed"
    if not file.exists() or file.read_bytes() != body:
        part = file.with_suffix(".part")
        part.write_bytes(body)
        part.replace(file)
    checked.touch()
    return name, None


def sync(force):
    CACHE.mkdir(parents=True, exist_ok=True)
    feeds = [source for source in sources() if source[2]]
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(lambda source: download(source, force), feeds))
    errors = {name: error for name, error in results if error}
    ERRORS.write_text(json.dumps(errors))
    # Feeds for calendars no longer listed.
    kept = {source[3] for source in feeds}
    for file in CACHE.glob("*.ics"):
        if file not in kept:
            file.unlink(missing_ok=True)
            file.with_suffix(".checked").unlink(missing_ok=True)


def shift(year, month, delta):
    index = year * 12 + month - 1 + delta
    return index // 12, index % 12 + 1


def grid(year, month):
    """The six weeks shown for a month, Monday first."""
    first = dt.date(year, month, 1)
    start = first - dt.timedelta(days=first.weekday())
    return [start + dt.timedelta(days=offset) for offset in range(42)]


def local(value):
    """A DTSTART/DTEND value as a naive local datetime, or the date itself for an all-day value."""
    if isinstance(value, dt.datetime):
        return value.astimezone().replace(tzinfo=None) if value.tzinfo else value
    return value


def clock(moment):
    return f"{moment.hour % 12 or 12}:{moment.minute:02d} {'am' if moment.hour < 12 else 'pm'}"


def span(start, end):
    if end <= start:
        return clock(start)
    if (start.hour < 12) == (end.hour < 12):
        return f"{clock(start)[:-3]} – {clock(end)}"
    return f"{clock(start)} – {clock(end)}"


def occurrences(calendars, start, end):
    """Every event between two dates as (colour, calendar name, event), plus calendars that failed to read."""
    import icalendar
    import recurring_ical_events

    found, problems = [], []
    for name, colour, url, file in calendars:
        try:
            parsed = icalendar.Calendar.from_ical(file.read_bytes())
            events = recurring_ical_events.of(parsed, skip_bad_series=True).between(start, end)
        except FileNotFoundError:
            # A feed not downloaded yet is reported by sync instead.
            if not url:
                problems.append(f"Couldn't find {name}")
            continue
        except Exception:
            problems.append(f"Couldn't read {name}")
            continue
        found.extend((colour, name, event) for event in events)
    return found, problems


def place(found, days, first_shown, last_shown):
    """Adds each event to every shown day it covers."""
    for colour, name, event in found:
        if str(event.get("STATUS", "")).upper() == "CANCELLED" or "DTSTART" not in event:
            continue
        start = local(event["DTSTART"].dt)
        if "DTEND" in event:
            end = local(event["DTEND"].dt)
        elif "DURATION" in event:
            end = start + event["DURATION"].dt
        else:
            end = start + ONE_DAY if not isinstance(start, dt.datetime) else start
        all_day = not isinstance(start, dt.datetime)
        if all_day:
            end = end.date() if isinstance(end, dt.datetime) else end
            first, last = start, max(end - ONE_DAY, start)
        else:
            end = end if isinstance(end, dt.datetime) else dt.datetime.combine(end, dt.time())
            first = start.date()
            last = max((end - dt.timedelta(microseconds=1)).date(), first)
        # Free/busy-only feeds have no summary.
        title = " ".join(str(event.get("SUMMARY", "")).split()) or "Busy"
        location = str(event.get("LOCATION", "")).strip()
        where = location.splitlines()[0] if location else name

        day = max(first, first_shown)
        while day <= min(last, last_shown):
            if all_day or first < day < last:
                when, order = "All day", -1
            elif first == last:
                when, order = span(start, end), start.hour * 60 + start.minute
            elif day == first:
                when, order = f"From {clock(start)}", start.hour * 60 + start.minute
            else:
                when, order = f"Until {clock(end)}", -1
            days[day].append((order, title, {"title": title, "when": when, "where": where, "color": colour}))
            day += ONE_DAY


def month_data(year, month, days, configured, problems):
    shown = grid(year, month)
    events = {day: [entry for _, _, entry in sorted(days.get(day, []), key=lambda item: item[:2])] for day in shown}
    weeks = []
    for week in range(6):
        weeks.append([{
            "day": str(day.day),
            "date": day.isoformat(),
            "out": day.month != month,
            # One dot per calendar with events that day.
            "dots": list(dict.fromkeys(entry["color"] for entry in events[day]))[:3],
        } for day in shown[week * 7:week * 7 + 7]])
    return {
        "title": dt.date(year, month, 1).strftime("%B"),
        "year": str(year),
        "weeks": weeks,
        "days": {day.isoformat(): {
            "label": f"{day:%A} {day.day} {day:%B}",
            "count": len(events[day]),
            "events": events[day],
        } for day in shown},
        "configured": configured,
        "problems": problems,
        "loading": False,
    }


def cache_key(calendars):
    key = [FORMAT]
    for file in [CONFIG] + [source[3] for source in calendars]:
        try:
            info = file.stat()
            key.append([str(file), info.st_mtime_ns, info.st_size])
        except OSError:
            key.append([str(file), None])
    return key


def month_cache(year, month):
    return CACHE / "months" / f"{year:04d}-{month:02d}.json"


def cached(year, month, key):
    try:
        stored = json.loads(month_cache(year, month).read_text())
    except (OSError, ValueError):
        return None
    return stored["data"] if stored.get("key") == key else None


def build(year, month, calendars, key):
    """The month with its events, caching it and the months either side, which share the work."""
    months = [shift(year, month, delta) for delta in (-1, 0, 1)]
    first_shown = grid(*months[0])[0]
    last_shown = grid(*months[-1])[-1]
    days = {first_shown + dt.timedelta(days=offset): [] for offset in range((last_shown - first_shown).days + 1)}
    try:
        found, problems = occurrences(calendars, first_shown, last_shown + ONE_DAY)
    except ImportError:
        return month_data(year, month, {}, True, [MISSING_LIBRARIES])
    place(found, days, first_shown, last_shown)
    (CACHE / "months").mkdir(parents=True, exist_ok=True)
    result = None
    for shown_year, shown_month in months:
        data = month_data(shown_year, shown_month, days, True, problems)
        month_cache(shown_year, shown_month).write_text(json.dumps({"key": key, "data": data}))
        if (shown_year, shown_month) == (year, month):
            result = data
    return result


def month_command(argument, quick):
    match = re.fullmatch(r"(\d{4})-(\d{2})", argument)
    if not match or not 1 <= int(match[2]) <= 12:
        sys.exit(f"Not a month: {argument}")
    year, month = int(match[1]), int(match[2])
    calendars = sources()
    if not calendars:
        data = month_data(year, month, {}, False, [])
    else:
        key = cache_key(calendars)
        data = cached(year, month, key)
        if data is None and quick:
            data = month_data(year, month, {}, True, [])
            data["loading"] = True
        elif data is None:
            data = build(year, month, calendars, key)

    try:
        errors = list(json.loads(ERRORS.read_text()).values()) if calendars else []
    except (OSError, ValueError):
        errors = []
    problems = errors + data.pop("problems")
    if not data["configured"]:
        data["note"] = f"Add calendars to {str(CONFIG).replace(str(Path.home()), '~', 1)}"
    elif problems:
        data["note"] = " · ".join(problems)
    else:
        data["note"] = "Loading events…" if data["loading"] else ""
    data["note_error"] = bool(problems)
    print(json.dumps(data, separators=(",", ":")))


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "month" and len(sys.argv) > 2:
        month_command(sys.argv[2], "--quick" in sys.argv[3:])
    elif command == "sync":
        sync("--force" in sys.argv[2:])
    else:
        sys.exit("Usage: calendar-data.py {month YYYY-MM [--quick]|sync [--force]}")


if __name__ == "__main__":
    main()
