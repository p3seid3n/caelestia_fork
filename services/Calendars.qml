pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.I18n
import qs.utils

// Events for the dashboard Calendar tab: the user's own events plus any number of
// online calendars that are subscribed to by link (Google "secret address in iCal format",
// Outlook "published calendar" ICS link, Nextcloud, iCloud public links, holiday calendars ...).
//
// Online calendars are read-only. Their links contain a secret, so they are kept in the
// system keyring through `secret-tool` (package: libsecret) and handed to the sync helper
// (assets/calendar_sync.py) through an environment variable, never on a command line.
// Everything else (names, colours, own events) is in ~/.local/state/caelestia/calendar.json.
Singleton {
    id: root

    // Subscribed calendars: [{id, name, colour}]. `colour` is "primary", "secondary", "tertiary" or "error".
    property var sources: []
    // Ids of calendars (also "local") whose events are hidden.
    property var hidden: []
    // The user's own events: [{id, title, location, allDay, start, end}] with epoch milliseconds.
    property var localEvents: []
    // Events from the online calendars, same shape plus `cal`.
    property var remoteEvents: []
    // Per calendar id: what went wrong on the last sync.
    property var errors: ({})
    // "idle", "syncing" or "error" (the helper itself could not run).
    property string status: "idle"
    property string statusText
    property double lastSync
    property string keyringError

    // calendar id -> link; only in memory, loaded from and saved to the keyring.
    property var urls: ({})
    property bool urlsLoaded
    property bool syncAgain
    property string pendingInput
    property string pendingSecret

    readonly property string localId: "local"
    readonly property var colourCycle: ["tertiary", "secondary", "error", "primary"]

    // Everything that is shown, newest data from every visible calendar.
    readonly property var events: {
        const out = [];
        if (!hidden.includes(localId)) {
            for (const e of localEvents)
                out.push(Object.assign({
                    cal: localId
                }, e));
        }
        for (const e of remoteEvents) {
            if (!hidden.includes(e.cal))
                out.push(e);
        }
        out.sort((a, b) => (a.allDay === b.allDay ? 0 : a.allDay ? -1 : 1) || a.start - b.start);
        return out;
    }

    // Event id -> event, for lists that only hold ids.
    readonly property var byId: {
        const map = {};
        for (const e of events)
            map[e.id] = e;
        return map;
    }

    // "year-month-day" -> events touching that day, all-day ones first.
    readonly property var byDay: {
        const map = {};
        for (const e of events) {
            const first = new Date(e.start);
            first.setHours(0, 0, 0, 0);
            // A timed event ending exactly at midnight does not belong to the next day.
            const last = new Date(Math.max(e.start, e.end - 1));
            let day = first;
            for (let i = 0; i < 62 && day.getTime() <= last.getTime(); i++) {
                const key = keyOf(day);
                if (!map[key])
                    map[key] = [];
                map[key].push(e);
                day = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1);
            }
        }
        return map;
    }

    function keyOf(day: date): string {
        return day.getFullYear() + "-" + day.getMonth() + "-" + day.getDate();
    }

    function eventsOn(day: date): var {
        return byDay[keyOf(day)] ?? [];
    }

    // Colours (palette keys) of the calendars that have something on a day, at most three.
    function dotsOn(day: date): var {
        const found = [];
        for (const e of eventsOn(day)) {
            const colour = colourKeyOf(e.cal);
            if (!found.includes(colour))
                found.push(colour);
            if (found.length >= 3)
                break;
        }
        return found;
    }

    // The next events that have not ended yet, soonest first.
    function upcoming(count: int): var {
        const now = Date.now();
        return events.filter(e => e.end > now || e.start >= now).slice().sort((a, b) => a.start - b.start).slice(0, count);
    }

    function sourceOf(id: string): var {
        return sources.find(s => s.id === id) ?? null;
    }

    function nameOf(id: string): string {
        return id === localId ? Tr.tr("My events") : (sourceOf(id)?.name ?? "");
    }

    function colourKeyOf(id: string): string {
        return id === localId ? "primary" : (sourceOf(id)?.colour ?? "secondary");
    }

    function colourFor(key: string): color {
        switch (key) {
        case "secondary":
            return Colours.palette.m3secondary;
        case "tertiary":
            return Colours.palette.m3tertiary;
        case "error":
            return Colours.palette.m3error;
        default:
            return Colours.palette.m3primary;
        }
    }

    function colourOf(id: string): color {
        return colourFor(colourKeyOf(id));
    }

    function nextColour(key: string): string {
        const i = colourCycle.indexOf(key);
        return colourCycle[(i + 1) % colourCycle.length];
    }

    function isVisible(id: string): bool {
        return !hidden.includes(id);
    }

    function setVisible(id: string, on: bool): void {
        if (on === isVisible(id))
            return;
        hidden = on ? hidden.filter(h => h !== id) : hidden.concat([id]);
        save();
    }

    function hostOf(id: string): string {
        const m = /^[a-z]+:\/\/([^\/?#]+)/i.exec(urls[id] ?? "");
        return m ? m[1] : "";
    }

    function newId(): string {
        return Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
    }

    // Subscribes to an online calendar. Returns an error text, or "" when it was added.
    function addSource(name: string, url: string, colour: string): string {
        const link = url.trim();
        if (!/^(https?|webcal):\/\/\S+$/i.test(link))
            return Tr.tr("The address has to start with https:// or webcal://");
        const id = newId();
        const label = name.trim() !== "" ? name.trim() : (/^[a-z]+:\/\/([^\/?#]+)/i.exec(link)?.[1] ?? Tr.tr("Calendar"));
        sources = sources.concat([
            {
                id: id,
                name: label,
                colour: colour || colourCycle[sources.length % colourCycle.length]
            }
        ]);
        const next = Object.assign({}, urls);
        next[id] = link;
        urls = next;
        save();
        saveUrls();
        refresh();
        return "";
    }

    function removeSource(id: string): void {
        sources = sources.filter(s => s.id !== id);
        hidden = hidden.filter(h => h !== id);
        remoteEvents = remoteEvents.filter(e => e.cal !== id);
        const next = Object.assign({}, urls);
        delete next[id];
        urls = next;
        save();
        saveUrls();
    }

    function setColour(id: string, colour: string): void {
        sources = sources.map(s => s.id === id ? Object.assign({}, s, {
            colour: colour
        }) : s);
        save();
    }

    function addEvent(title: string, location: string, allDay: bool, start: double, end: double): void {
        localEvents = localEvents.concat([
            {
                id: newId(),
                title: title.trim() !== "" ? title.trim() : Tr.tr("(no title)"),
                location: location.trim(),
                allDay: allDay,
                start: start,
                end: Math.max(end, start)
            }
        ]);
        save();
    }

    function removeEvent(id: string): void {
        localEvents = localEvents.filter(e => e.id !== id);
        save();
    }

    function isoDate(day: date): string {
        const pad = n => (n < 10 ? "0" : "") + n;
        return day.getFullYear() + "-" + pad(day.getMonth() + 1) + "-" + pad(day.getDate());
    }

    // Fetches all online calendars again (a window from last month to a year ahead).
    function refresh(): void {
        if (!urlsLoaded)
            return;
        const calendars = sources.filter(s => urls[s.id]).map(s => ({
                    id: s.id,
                    url: urls[s.id]
                }));
        if (calendars.length === 0) {
            remoteEvents = [];
            errors = {};
            status = "idle";
            return;
        }
        if (sync.running) {
            syncAgain = true;
            return;
        }
        const now = new Date();
        pendingInput = JSON.stringify({
            from: isoDate(new Date(now.getFullYear(), now.getMonth() - 1, 1)),
            to: isoDate(new Date(now.getFullYear(), now.getMonth() + 14, 1)),
            calendars: calendars
        });
        status = "syncing";
        sync.running = true;
    }

    function save(): void {
        saveTimer.restart();
    }

    function saveUrls(): void {
        pendingSecret = JSON.stringify(urls);
        storeUrls.running = true;
    }

    Component.onCompleted: lookupUrls.running = true

    Timer {
        id: saveTimer

        interval: 400
        onTriggered: file.setText(JSON.stringify({
                sources: root.sources,
                hidden: root.hidden,
                events: root.localEvents
            }))
    }

    Timer {
        interval: 15 * 60 * 1000
        running: root.urlsLoaded
        repeat: true
        onTriggered: root.refresh()
    }

    FileView {
        id: file

        printErrors: false
        path: `${Paths.state}/calendar.json`
        onLoaded: {
            try {
                const c = JSON.parse(text());
                if (Array.isArray(c.sources))
                    root.sources = c.sources.filter(s => typeof s.id === "string" && typeof s.name === "string").map(s => ({
                                id: s.id,
                                name: s.name,
                                colour: ["primary", "secondary", "tertiary", "error"].includes(s.colour) ? s.colour : "secondary"
                            }));
                if (Array.isArray(c.hidden))
                    root.hidden = c.hidden.filter(h => typeof h === "string");
                if (Array.isArray(c.events))
                    root.localEvents = c.events.filter(e => typeof e.id === "string" && typeof e.start === "number").map(e => ({
                                id: e.id,
                                title: String(e.title ?? ""),
                                location: String(e.location ?? ""),
                                allDay: e.allDay === true,
                                start: e.start,
                                end: typeof e.end === "number" ? e.end : e.start
                            }));
            } catch (error) {
                console.warn("Calendars: could not parse calendar.json:", error);
            }
            root.refresh();
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => setText(JSON.stringify({
                        sources: [],
                        hidden: [],
                        events: []
                    })));
        }
    }

    // The links, as one JSON object in a single keyring entry.
    Process {
        id: lookupUrls

        command: ["secret-tool", "lookup", "service", "kairos-calendar", "account", "sources"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const value = JSON.parse(text.trim() || "{}");
                    if (value && typeof value === "object")
                        root.urls = value;
                } catch (error) {
                    console.warn("Calendars: could not read the saved calendar links:", error);
                }
                root.urlsLoaded = true;
                root.refresh();
            }
        }
    }

    Process {
        id: storeUrls

        command: ["sh", "-c", "printf %s \"$KAIROS_CAL_VALUE\" | secret-tool store --label='KairosOS calendar links' service kairos-calendar account sources"]
        environment: ({
                KAIROS_CAL_VALUE: root.pendingSecret
            })
        onExited: code => {
            root.keyringError = code === 0 ? "" : Tr.tr("The calendar links could not be saved to the keyring (is libsecret installed and the keyring unlocked?).");
            root.pendingSecret = "";
        }
    }

    Process {
        id: sync

        command: ["python3", Quickshell.shellPath("assets/calendar_sync.py")]
        environment: ({
                KAIROS_CAL_INPUT: root.pendingInput
            })
        stdout: StdioCollector {
            onStreamFinished: {
                root.pendingInput = "";
                try {
                    const result = JSON.parse(text);
                    root.remoteEvents = (result.events ?? []).filter(e => typeof e.start === "number");
                    const errs = {};
                    for (const e of result.errors ?? [])
                        errs[e.cal] = e.message;
                    root.errors = errs;
                    root.status = "idle";
                    root.statusText = "";
                    root.lastSync = Date.now();
                } catch (error) {
                    root.status = "error";
                    root.statusText = Tr.tr("The calendar helper did not run (is python3 installed?).");
                }
            }
        }
        onExited: {
            if (root.syncAgain) {
                root.syncAgain = false;
                root.refresh();
            }
        }
    }
}
