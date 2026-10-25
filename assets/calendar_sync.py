#!/usr/bin/env python3
"""Reads iCalendar (.ics) subscription links and prints their events in a date range as JSON.

Used by the dashboard Calendar tab (services/Calendars.qml). Standard library only.

Input (environment variable KAIROS_CAL_INPUT, so links never show up on a command line):
    {"from": "2026-10-01", "to": "2027-02-01",
     "calendars": [{"id": "abc", "url": "https://..."}]}

Output (stdout):
    {"events": [{"id", "cal", "uid", "title", "location", "allDay", "start", "end"}],
     "errors": [{"cal": "abc", "message": "HTTP 403"}]}

`start` and `end` are epoch milliseconds. All-day events run from local midnight of the
first day to local midnight after the last day. Recurring events are expanded for the
range, with exceptions (EXDATE) and single changed occurrences (RECURRENCE-ID) applied.
"""

import calendar
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

MAX_BYTES = 20 * 1024 * 1024
MAX_STEPS = 20000

# Outlook and Exchange name their time zones the Windows way.
WINDOWS_ZONES = {
    "UTC": "UTC",
    "GMT Standard Time": "Europe/London",
    "Greenwich Standard Time": "Atlantic/Reykjavik",
    "W. Europe Standard Time": "Europe/Berlin",
    "Central Europe Standard Time": "Europe/Budapest",
    "Central European Standard Time": "Europe/Warsaw",
    "Romance Standard Time": "Europe/Paris",
    "E. Europe Standard Time": "Europe/Chisinau",
    "FLE Standard Time": "Europe/Kiev",
    "GTB Standard Time": "Europe/Bucharest",
    "Turkey Standard Time": "Europe/Istanbul",
    "Russian Standard Time": "Europe/Moscow",
    "Eastern Standard Time": "America/New_York",
    "Central Standard Time": "America/Chicago",
    "Mountain Standard Time": "America/Denver",
    "Pacific Standard Time": "America/Los_Angeles",
    "India Standard Time": "Asia/Kolkata",
    "China Standard Time": "Asia/Shanghai",
    "Tokyo Standard Time": "Asia/Tokyo",
    "AUS Eastern Standard Time": "Australia/Sydney",
}

WEEKDAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]


def local_zone():
    """The machine's time zone as a real zone (so daylight saving time works), if it can be found."""
    candidates = [os.environ.get("TZ", "").lstrip(":")]
    path = os.path.realpath("/etc/localtime")
    if "zoneinfo/" in path:
        candidates.append(path.split("zoneinfo/", 1)[1])
    for name in candidates:
        if name:
            try:
                return ZoneInfo(name)
            except Exception:
                pass
    return datetime.now().astimezone().tzinfo


LOCAL = local_zone()


def zone_for(tzid):
    """Time zone for a TZID parameter; the local one when it is not understood."""
    if not tzid:
        return LOCAL
    tzid = tzid.strip('"')
    name = WINDOWS_ZONES.get(tzid, tzid)
    for candidate in (name, "/".join(name.split("/")[-2:]), name.split("/")[-1]):
        try:
            return ZoneInfo(candidate)
        except Exception:
            continue
    return LOCAL


# ---------------------------------------------------------------- parsing


def unfold(text):
    lines = []
    for raw in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if raw[:1] in (" ", "\t") and lines:
            lines[-1] += raw[1:]
        elif raw:
            lines.append(raw)
    return lines


def split_unquoted(text, sep):
    parts, current, quoted = [], [], False
    for ch in text:
        if ch == '"':
            quoted = not quoted
        if ch == sep and not quoted:
            parts.append("".join(current))
            current = []
        else:
            current.append(ch)
    parts.append("".join(current))
    return parts


def parse_line(line):
    """'NAME;P=V:value' -> (NAME, {P: V}, value)"""
    quoted = False
    for i, ch in enumerate(line):
        if ch == '"':
            quoted = not quoted
        elif ch == ":" and not quoted:
            head, value = line[:i], line[i + 1 :]
            break
    else:
        return None
    bits = split_unquoted(head, ";")
    params = {}
    for bit in bits[1:]:
        if "=" in bit:
            key, val = bit.split("=", 1)
            params[key.upper()] = val.strip('"')
    return bits[0].upper(), params, value


def unescape(value):
    out, i = [], 0
    while i < len(value):
        if value[i] == "\\" and i + 1 < len(value):
            nxt = value[i + 1]
            out.append("\n" if nxt in "nN" else nxt)
            i += 2
        else:
            out.append(value[i])
            i += 1
    return "".join(out)


def parse_events(text):
    """All VEVENTs as dicts of {NAME: [(params, value), ...]}."""
    events, current = [], None
    for line in unfold(text):
        parsed = parse_line(line)
        if not parsed:
            continue
        name, params, value = parsed
        if name == "BEGIN" and value.upper() == "VEVENT":
            current = {}
        elif name == "END" and value.upper() == "VEVENT":
            if current is not None:
                events.append(current)
            current = None
        elif current is not None:
            current.setdefault(name, []).append((params, value))
    return events


def parse_when(params, value):
    """A DATE (-> date) or DATE-TIME (-> aware datetime)."""
    value = value.strip()
    if params.get("VALUE") == "DATE" or (len(value) == 8 and "T" not in value):
        return datetime.strptime(value[:8], "%Y%m%d").date()
    if value.endswith("Z"):
        return datetime.strptime(value[:-1], "%Y%m%dT%H%M%S").replace(tzinfo=timezone.utc)
    return datetime.strptime(value[:15], "%Y%m%dT%H%M%S").replace(tzinfo=zone_for(params.get("TZID")))


def parse_duration(value):
    sign = -1 if value.startswith("-") else 1
    value = value.lstrip("+-")[1:]  # drop P
    days = hours = minutes = seconds = 0
    number = ""
    in_time = False
    for ch in value:
        if ch == "T":
            in_time = True
        elif ch.isdigit():
            number += ch
        else:
            n = int(number or 0)
            number = ""
            if ch == "W":
                days += 7 * n
            elif ch == "D":
                days += n
            elif ch == "H" and in_time:
                hours += n
            elif ch == "M" and in_time:
                minutes += n
            elif ch == "S" and in_time:
                seconds += n
    return sign * timedelta(days=days, hours=hours, minutes=minutes, seconds=seconds)


def parse_rrule(value):
    rule = {}
    for part in value.split(";"):
        if "=" in part:
            key, val = part.split("=", 1)
            rule[key.upper()] = val
    return rule


# ---------------------------------------------------------------- recurrence


def add_months(year, month, delta):
    index = year * 12 + (month - 1) + delta
    return index // 12, index % 12 + 1


def nth_weekday(year, month, weekday, nth):
    """Date of the nth (1.., or -1 for last) given weekday (0 = Monday) in a month, or None."""
    days = [d for d in range(1, calendar.monthrange(year, month)[1] + 1) if date(year, month, d).weekday() == weekday]
    try:
        return date(year, month, days[nth - 1 if nth > 0 else nth])
    except IndexError:
        return None


def parse_byday(items):
    out = []
    for item in items:
        item = item.strip().upper()
        if len(item) < 2 or item[-2:] not in WEEKDAYS:
            continue
        nth = int(item[:-2]) if item[:-2] else 0
        out.append((nth, WEEKDAYS.index(item[-2:])))
    return out


def month_days(year, month, rule, start_day, byday, bymonthday):
    """Days of a month that a MONTHLY/YEARLY rule picks."""
    last = calendar.monthrange(year, month)[1]
    picked = set()
    if bymonthday:
        for n in bymonthday:
            d = n if n > 0 else last + 1 + n
            if 1 <= d <= last:
                picked.add(d)
    elif byday:
        for nth, weekday in byday:
            if nth:
                found = nth_weekday(year, month, weekday, nth)
                if found:
                    picked.add(found.day)
            else:
                picked.update(d for d in range(1, last + 1) if date(year, month, d).weekday() == weekday)
    elif start_day <= last:
        picked.add(start_day)
    return sorted(picked)


def occurrences(start, rule, limit):
    """Wall-clock starts of a recurring event (naive datetimes or dates), oldest first, up to `limit`."""
    all_day = not isinstance(start, datetime)
    first = start if all_day else start.replace(tzinfo=None)
    clock = None if all_day else first.time()
    freq = rule.get("FREQ", "").upper()
    interval = max(1, int(rule.get("INTERVAL", "1") or 1))
    count = int(rule["COUNT"]) if rule.get("COUNT") else None
    until = None
    if rule.get("UNTIL"):
        u = parse_when({}, rule["UNTIL"])
        if isinstance(u, datetime):
            until = u.astimezone(start.tzinfo or LOCAL).replace(tzinfo=None) if not all_day else u.date()
        else:
            until = u if all_day else datetime.combine(u, time.max)
    bymonth = {int(m) for m in rule["BYMONTH"].split(",")} if rule.get("BYMONTH") else set()
    bymonthday = [int(d) for d in rule["BYMONTHDAY"].split(",")] if rule.get("BYMONTHDAY") else []
    byday = parse_byday(rule["BYDAY"].split(",")) if rule.get("BYDAY") else []
    wkst = WEEKDAYS.index(rule.get("WKST", "MO").upper()) if rule.get("WKST", "MO").upper() in WEEKDAYS else 0
    first_day = first if all_day else first.date()

    def build(day):
        return day if all_day else datetime.combine(day, clock)

    def candidates(k):
        """Days (dates) of period number k, oldest first."""
        if freq == "DAILY":
            day = first_day + timedelta(days=k * interval)
            ok = (not bymonth or day.month in bymonth) and (not bymonthday or day.day in [d if d > 0 else calendar.monthrange(day.year, day.month)[1] + 1 + d for d in bymonthday]) and (not byday or day.weekday() in [w for _, w in byday])
            return [day] if ok else []
        if freq == "WEEKLY":
            week_start = first_day - timedelta(days=(first_day.weekday() - wkst) % 7) + timedelta(weeks=k * interval)
            weekdays = sorted({w for _, w in byday} or {first_day.weekday()}, key=lambda w: (w - wkst) % 7)
            days = [week_start + timedelta(days=(w - wkst) % 7) for w in weekdays]
            return [d for d in days if not bymonth or d.month in bymonth]
        if freq == "MONTHLY":
            year, month = add_months(first_day.year, first_day.month, k * interval)
            if bymonth and month not in bymonth:
                return []
            return [date(year, month, d) for d in month_days(year, month, rule, first_day.day, byday, bymonthday)]
        if freq == "YEARLY":
            year = first_day.year + k * interval
            months = sorted(bymonth) if bymonth else [first_day.month]
            out = []
            for month in months:
                out += [date(year, month, d) for d in month_days(year, month, rule, first_day.day, byday, bymonthday)]
            return out
        return []

    if freq not in ("DAILY", "WEEKLY", "MONTHLY", "YEARLY"):
        yield first
        return

    produced = 0
    for k in range(MAX_STEPS):
        for day in candidates(k):
            moment = build(day)
            if moment < first:
                continue
            if until is not None and moment > until:
                return
            if moment > limit:
                return
            yield moment
            produced += 1
            if count is not None and produced >= count:
                return
        # Past the limit with nothing more to find in later periods.
        if candidates(k) and build(candidates(k)[0]) > limit:
            return
    return


# ---------------------------------------------------------------- events


def as_instant(value):
    """Comparable key for an occurrence start: epoch seconds, or an ordinal for all-day."""
    if isinstance(value, datetime):
        return ("t", int(value.timestamp()))
    return ("d", value.toordinal())


def local_midnight_ms(day):
    return int(datetime.combine(day, time.min, tzinfo=LOCAL).timestamp() * 1000)


def event_span(raw):
    """(start, end, all_day) of the first/only instance of a raw event."""
    start = parse_when(*raw["DTSTART"][0])
    all_day = not isinstance(start, datetime)
    if "DTEND" in raw:
        end = parse_when(*raw["DTEND"][0])
    elif "DURATION" in raw:
        end = start + parse_duration(raw["DURATION"][0][1])
    else:
        end = start + timedelta(days=1) if all_day else start
    if all_day and not isinstance(end, date):
        end = end.date()
    if all_day and end <= start:
        end = start + timedelta(days=1)
    return start, end, all_day


def first_text(raw, name):
    return unescape(raw[name][0][1]).strip() if name in raw else ""


def expand(cal_id, raws, range_start, range_end):
    """Events of one calendar that overlap [range_start, range_end), as output dicts."""
    overrides = {}
    for raw in raws:
        if "RECURRENCE-ID" in raw and "UID" in raw:
            overrides[(raw["UID"][0][1], as_instant(parse_when(*raw["RECURRENCE-ID"][0])))] = raw

    out = []

    def emit(raw, start, end, all_day):
        if all_day:
            start_ms, end_ms = local_midnight_ms(start), local_midnight_ms(end)
        else:
            start_ms, end_ms = int(start.timestamp() * 1000), int(end.timestamp() * 1000)
        if end_ms < int(range_start.timestamp() * 1000) or start_ms >= int(range_end.timestamp() * 1000):
            if not (start_ms == end_ms and range_start.timestamp() * 1000 <= start_ms < range_end.timestamp() * 1000):
                return
        uid = first_text(raw, "UID") or f"{cal_id}-{start_ms}"
        out.append(
            {
                "id": f"{cal_id}:{uid}:{start_ms}",
                "cal": cal_id,
                "uid": uid,
                "title": first_text(raw, "SUMMARY") or "(no title)",
                "location": first_text(raw, "LOCATION"),
                "allDay": all_day,
                "start": start_ms,
                "end": max(end_ms, start_ms),
            }
        )

    for raw in raws:
        if "DTSTART" not in raw or "RECURRENCE-ID" in raw or first_text(raw, "STATUS").upper() == "CANCELLED":
            continue
        try:
            start, end, all_day = event_span(raw)
        except Exception:
            continue
        if "RRULE" not in raw and "RDATE" not in raw:
            emit(raw, start, end, all_day)
            continue

        uid = raw["UID"][0][1] if "UID" in raw else ""
        zone = start.tzinfo if not all_day else LOCAL
        length = (end - start) if all_day else (end - start)
        skipped = set()
        for params, value in raw.get("EXDATE", []):
            for part in value.split(","):
                try:
                    skipped.add(as_instant(parse_when(params, part)))
                except Exception:
                    pass

        wall_limit = (range_end.astimezone(zone).replace(tzinfo=None) if not all_day else range_end.astimezone(LOCAL).date()) + timedelta(days=1)
        wall = []
        if "RRULE" in raw:
            wall.extend(occurrences(start, parse_rrule(raw["RRULE"][0][1]), wall_limit))
        else:
            wall.append(start.replace(tzinfo=None) if not all_day else start)
        for params, value in raw.get("RDATE", []):
            for part in value.split(","):
                try:
                    moment = parse_when(params, part)
                    wall.append(moment.replace(tzinfo=None) if isinstance(moment, datetime) else moment)
                except Exception:
                    pass

        for moment in sorted(set(wall)):
            occ_start = moment if all_day else moment.replace(tzinfo=zone)
            key = as_instant(occ_start)
            if key in skipped:
                continue
            if (uid, key) in overrides:
                continue
            occ_end = occ_start + length
            emit(raw, occ_start, occ_end, all_day)

    # Single changed occurrences are events of their own.
    for raw in overrides.values():
        if first_text(raw, "STATUS").upper() == "CANCELLED":
            continue
        try:
            start, end, all_day = event_span(raw)
        except Exception:
            continue
        emit(raw, start, end, all_day)
    return out


def fetch(url):
    url = url.strip()
    if url.lower().startswith("webcal://"):
        url = "https://" + url[9:]
    allowed = ("https://", "http://") + (("file://",) if os.environ.get("KAIROS_CAL_ALLOW_FILE") else ())
    if not url.lower().startswith(allowed):
        raise ValueError("Address must start with https://")
    request = urllib.request.Request(url, headers={"User-Agent": "KairosOS-calendar/1.0", "Accept": "text/calendar, */*"})
    with urllib.request.urlopen(request, timeout=20) as response:
        data = response.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise ValueError("Calendar is too large")
    return data.decode("utf-8", errors="replace")


def main():
    job = json.loads(os.environ.get("KAIROS_CAL_INPUT", "{}"))
    range_start = datetime.combine(date.fromisoformat(job["from"]), time.min, tzinfo=LOCAL)
    range_end = datetime.combine(date.fromisoformat(job["to"]), time.min, tzinfo=LOCAL)
    events, errors = [], []
    for cal in job.get("calendars", []):
        cal_id = str(cal.get("id", ""))
        try:
            text = fetch(cal.get("url", ""))
            if "BEGIN:VCALENDAR" not in text.upper():
                raise ValueError("Not a calendar file")
            events.extend(expand(cal_id, parse_events(text), range_start, range_end))
        except urllib.error.HTTPError as error:
            errors.append({"cal": cal_id, "message": f"HTTP {error.code}"})
        except urllib.error.URLError:
            errors.append({"cal": cal_id, "message": "Could not reach the server"})
        except Exception as error:  # a broken calendar must not take the others down
            errors.append({"cal": cal_id, "message": str(error)[:120] or "Could not read the calendar"})
    json.dump({"events": events, "errors": errors}, sys.stdout)


if __name__ == "__main__":
    main()
