pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.I18n
import qs.utils

// Events for the dashboard Calendar tab: the user's own events plus any number of calendars
// subscribed to by link (school timetable from portal.sbl.ch, Google "secret address in iCal
// format", Outlook "published calendar" ICS link, Nextcloud, iCloud, holidays ...) or imported
// from an .ics file.
//
// School calendars are read as schulNetz timetables: lessons are matched to subjects
// (services/Subjects.qml) and exams are recognised (see assets/calendar_sync.py). Homework and
// exams typed in by hand live in services/Assignments.qml; upcoming() merges both.
//
// Subscribed calendars are read-only. Their links contain a secret, so they are kept in the
// system keyring through `secret-tool` (package: libsecret) and handed to the sync helper
// through an environment variable, never on a command line. Imported files are copied to
// ~/.local/state/caelestia/calendar-<id>.ics. Everything else (names, colours, own events)
// is in ~/.local/state/caelestia/calendar.json.
Singleton {
    id: root

    // Calendars: [{id, name, colour, kind, file, autoName}]. `colour` is "primary", "secondary",
    // "tertiary" or "error"; `kind` is "school" (schulNetz timetable) or "other"; `file` is the
    // path of an imported .ics (empty for links); `autoName` takes the name the calendar gives itself.
    property var sources: []
    // Ids of calendars (also "local") whose events are hidden.
    property var hidden: []
    // The user's own events: [{id, title, location, allDay, start, end}] with epoch milliseconds.
    property var localEvents: []
    // Events from the calendars, same shape plus `cal`, `kind` ("lesson", "test" or "event"),
    // `code`, `teacher`, `note` and `cancelled` (see assets/calendar_sync.py).
    property var remoteEvents: []
    // Per calendar id: what went wrong on the last sync.
    property var errors: ({})
    // "idle", "syncing" or "error" (the helper itself could not run).
    property string status: "idle"
    property string statusText
    property double lastSync
    property string keyringError
    // "month" or "week": the Calendar tab's view, kept while the shell runs.
    property string view: "month"
    // What the next imported .ics file becomes (set by requestImport()).
    property string importKind: "other"
    property string importName

    // calendar id -> link; only in memory, loaded from and saved to the keyring.
    property var urls: ({})
    property bool urlsLoaded
    property bool syncAgain
    property string pendingInput
    property string pendingSecret

    readonly property string localId: "local"
    readonly property var colourCycle: ["tertiary", "secondary", "error", "primary"]

    // Everything that is shown, from every visible calendar, each with its `subject` id
    // ("" when it has none). Lessons of hidden subjects are left out.
    readonly property var events: {
        const out = [];
        if (!hidden.includes(localId)) {
            for (const e of localEvents)
                out.push(Object.assign({
                    cal: localId,
                    kind: "event",
                    note: "",
                    cancelled: false
                }, e));
        }
        const hiddenSubjects = Subjects.hiddenIds;
        const codes = Subjects.codeIndex;
        for (const e of remoteEvents) {
            if (hidden.includes(e.cal))
                continue;
            const subject = e.code ? (codes[e.code] ?? "") : "";
            if (e.kind === "lesson" && subject !== "" && hiddenSubjects.includes(subject))
                continue;
            out.push(Object.assign({}, e, {
                subject: subject
            }));
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

    // Asks the dashboard (modules/dashboard/Wrapper.qml) to open its .ics file picker.
    signal importRequested

    function keyOf(day: date): string {
        return day.getFullYear() + "-" + day.getMonth() + "-" + day.getDate();
    }

    function eventsOn(day: date): var {
        return byDay[keyOf(day)] ?? [];
    }

    function lessonsOn(day: date): var {
        return eventsOn(day).filter(e => e.kind === "lesson");
    }

    // What is on a day apart from lessons: exams, other events.
    function specialOn(day: date): var {
        return eventsOn(day).filter(e => e.kind !== "lesson");
    }

    // Colours of the dots under a day in the month grid: one per lesson in its subject's colour,
    // then one per other calendar with something that day.
    function dotsOn(day: date): var {
        const found = [];
        const cals = [];
        for (const e of eventsOn(day)) {
            if (e.kind === "lesson") {
                if (!e.cancelled)
                    found.push(Subjects.colourOf(e.subject));
            } else if (e.kind !== "test" && !cals.includes(e.cal)) {
                cals.push(e.cal);
                found.push(colourOf(e.cal));
            }
            if (found.length >= 8)
                break;
        }
        return found;
    }

    // Whether an exam is due that day (from the timetable or typed in).
    function hasExam(day: date): bool {
        return eventsOn(day).some(e => e.kind === "test") || Assignments.on(day).some(i => i.type === "exam" && !i.done);
    }

    // Accent colour of an event: its subject's for school events, its calendar's otherwise.
    function accentOf(e: var): color {
        return e.subject ? Subjects.colourOf(e.subject) : colourOf(e.cal);
    }

    // Readable title: "Mathematik" for a lesson, "Prüfung Deutsch" for "Prüfung D-2e-FiB",
    // the exam's own name otherwise.
    function titleOf(e: var): string {
        const subject = e.subject ? Subjects.nameOf(e.subject) : "";
        if (e.kind === "lesson" && subject !== "")
            return subject;
        if (e.kind === "test" && subject !== "") {
            const token = /\bf?[A-Za-z]{1,5}-\d+[a-z]+(?:,\d+[a-z]+)*-[A-Za-zÄÖÜäöü]{2,5}\b/;
            if (token.test(e.title))
                return e.title.replace(token, subject).replace(/\s+/g, " ").trim();
        }
        return e.title;
    }

    // Second line under a title: exam's subject, room, teacher, note.
    function detailOf(e: var): string {
        const parts = [];
        if (e.kind === "test" && e.subject && !titleOf(e).includes(Subjects.nameOf(e.subject)))
            parts.push(Subjects.nameOf(e.subject));
        if (e.kind === "lesson" && e.note)
            parts.push(e.note);
        if (e.location)
            parts.push(e.location);
        if (e.teacher)
            parts.push(e.teacher);
        return parts.join(" · ");
    }

    // The next lesson of a subject after a moment, or null.
    function nextLesson(subject: string, after: double): var {
        return events.find(e => e.kind === "lesson" && e.subject === subject && !e.cancelled && e.start > after) ?? null;
    }

    // What is coming up, soonest first: exams and events from the calendars (no plain lessons) and
    // open homework, exams and reminders. Items: {id, kind ("event", "test" or "task"), title,
    // detail, start, end, allDay, accent, event | task}.
    function upcoming(count: int): var {
        const now = Date.now();
        const out = [];
        for (const e of events) {
            if (e.kind === "lesson" || (e.end <= now && e.start < now))
                continue;
            out.push({
                id: e.id,
                kind: e.kind === "test" ? "test" : "event",
                title: titleOf(e),
                detail: detailOf(e),
                start: e.start,
                end: e.end,
                allDay: e.allDay,
                accent: accentOf(e),
                event: e,
                task: null
            });
        }
        for (const i of Assignments.upcoming(count, true))
            out.push(taskItem(i));
        return out.sort((a, b) => a.start - b.start).slice(0, count);
    }

    function taskItem(i: var): var {
        return {
            id: i.id,
            kind: "task",
            title: i.title || Subjects.nameOf(i.subject),
            detail: i.subject ? Subjects.nameOf(i.subject) : "",
            start: i.due,
            end: i.due,
            allDay: !i.hasTime,
            accent: i.subject ? Subjects.colourOf(i.subject) : Colours.palette.m3primary,
            event: null,
            task: i
        };
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

    // Subscribes to a calendar by link. Returns an error text, or "" when it was added.
    function addSource(name: string, url: string, kind: string): string {
        const link = url.trim();
        if (!/^(https?|webcals?):\/\/\S+$/i.test(link))
            return Tr.tr("The address has to start with https:// or webcal://");
        const id = newId();
        const label = name.trim() !== "" ? name.trim() : (kind === "school" ? Tr.tr("Timetable") : (/^[a-z]+:\/\/([^\/?#]+)/i.exec(link)?.[1] ?? Tr.tr("Calendar")));
        sources = sources.concat([
            {
                id: id,
                name: label,
                colour: colourCycle[sources.length % colourCycle.length],
                kind: kind === "school" ? "school" : "other",
                file: "",
                autoName: name.trim() === "" && kind !== "school"
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

    // A new calendar for an .ics file the caller has copied to fileFor(id).
    function addFile(id: string, name: string, kind: string): void {
        sources = sources.concat([
            {
                id: id,
                name: name.trim() !== "" ? name.trim() : Tr.tr("Imported calendar"),
                colour: colourCycle[sources.length % colourCycle.length],
                kind: kind === "school" ? "school" : "other",
                file: fileFor(id),
                autoName: name.trim() === ""
            }
        ]);
        save();
        refresh();
    }

    function requestImport(kind: string, name: string): void {
        importKind = kind;
        importName = name;
        importRequested();
    }

    function fileFor(id: string): string {
        return `${Paths.state}/calendar-${id}.ics`;
    }

    function setKind(id: string, kind: string): void {
        sources = sources.map(s => s.id === id ? Object.assign({}, s, {
            kind: kind
        }) : s);
        save();
        refresh();
    }

    function removeSource(id: string): void {
        const src = sourceOf(id);
        if (src?.file)
            Quickshell.execDetached(["rm", "-f", src.file]);
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

    function addEvent(title: string, location: string, allDay: bool, start: double, end: double, subject: string): void {
        localEvents = localEvents.concat([
            {
                id: newId(),
                title: title.trim() !== "" ? title.trim() : Tr.tr("(no title)"),
                location: location.trim(),
                allDay: allDay,
                start: start,
                end: Math.max(end, start),
                subject: subject
            }
        ]);
        save();
    }

    function updateEvent(id: string, changes: var): void {
        localEvents = localEvents.map(e => e.id === id ? Object.assign({}, e, changes) : e);
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
        const calendars = sources.filter(s => s.file || urls[s.id]).map(s => ({
                    id: s.id,
                    url: s.file ? "" : urls[s.id],
                    path: s.file,
                    school: s.kind === "school"
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
                                colour: ["primary", "secondary", "tertiary", "error"].includes(s.colour) ? s.colour : "secondary",
                                kind: s.kind === "school" ? "school" : "other",
                                file: typeof s.file === "string" ? s.file : "",
                                autoName: s.autoName === true
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
                                end: typeof e.end === "number" ? e.end : e.start,
                                subject: typeof e.subject === "string" ? e.subject : ""
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
                    // New course codes become subjects; names the calendars give themselves are used
                    // for calendars added without one.
                    Subjects.detect(root.remoteEvents.filter(e => e.code).map(e => ({
                                code: e.code,
                                teacher: e.teacher
                            })));
                    const names = result.names ?? {};
                    if (root.sources.some(s => s.autoName && names[s.id] && names[s.id] !== s.name)) {
                        root.sources = root.sources.map(s => s.autoName && names[s.id] ? Object.assign({}, s, {
                                name: names[s.id]
                            }) : s);
                        root.save();
                    }
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
