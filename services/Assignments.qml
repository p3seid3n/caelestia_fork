pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

// Homework, exams and reminders the user adds in the Calendar tab, each with a due date (and
// optionally a time) and usually a subject. Kept in ~/.local/state/caelestia/calendar-tasks.json.
// Exams that come with the school timetable are calendar events (services/Calendars.qml), these
// are the ones typed in by hand.
Singleton {
    id: root

    readonly property var types: ["homework", "exam", "reminder"]

    // [{id, title, type, subject, due, hasTime, done, notes, created}]
    property var items: []

    readonly property var byId: {
        const map = {};
        for (const i of items)
            map[i.id] = i;
        return map;
    }

    readonly property var open: items.filter(i => !i.done).sort((a, b) => a.due - b.due)

    function newId(): string {
        return "t" + Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
    }

    function sameDay(ms: double, day: date): bool {
        const d = new Date(ms);
        return d.getFullYear() === day.getFullYear() && d.getMonth() === day.getMonth() && d.getDate() === day.getDate();
    }

    // Everything due on a day, open ones first.
    function on(day: date): var {
        return items.filter(i => sameDay(i.due, day)).sort((a, b) => (a.done === b.done ? a.due - b.due : a.done ? 1 : -1));
    }

    // Open items from `from` on (overdue ones included when `withOverdue`), soonest first.
    function upcoming(count: int, withOverdue: bool): var {
        const start = new Date();
        start.setHours(0, 0, 0, 0);
        return open.filter(i => withOverdue || i.due >= start.getTime()).slice(0, count);
    }

    function add(title: string, type: string, subject: string, due: double, hasTime: bool, notes: string): string {
        const id = newId();
        items = items.concat([
            {
                id: id,
                title: title.trim(),
                type: types.includes(type) ? type : "homework",
                subject: subject,
                due: due,
                hasTime: hasTime,
                done: false,
                notes: notes.trim(),
                created: Date.now()
            }
        ]);
        saveTimer.restart();
        return id;
    }

    function update(id: string, changes: var): void {
        items = items.map(i => i.id === id ? Object.assign({}, i, changes) : i);
        saveTimer.restart();
    }

    function toggle(id: string): void {
        const i = byId[id];
        if (i)
            update(id, {
                done: !i.done
            });
    }

    function remove(id: string): void {
        items = items.filter(i => i.id !== id);
        saveTimer.restart();
    }

    function clearDone(): void {
        items = items.filter(i => !i.done);
        saveTimer.restart();
    }

    Timer {
        id: saveTimer

        interval: 400
        onTriggered: file.setText(JSON.stringify({
                items: root.items
            }))
    }

    FileView {
        id: file

        printErrors: false
        path: `${Paths.state}/calendar-tasks.json`
        onLoaded: {
            try {
                const c = JSON.parse(text());
                root.items = (c.items ?? []).filter(i => typeof i.id === "string" && typeof i.due === "number").map(i => ({
                            id: i.id,
                            title: String(i.title ?? ""),
                            type: root.types.includes(i.type) ? i.type : "homework",
                            subject: String(i.subject ?? ""),
                            due: i.due,
                            hasTime: i.hasTime === true,
                            done: i.done === true,
                            notes: String(i.notes ?? ""),
                            created: typeof i.created === "number" ? i.created : i.due
                        }));
            } catch (error) {
                console.warn("Assignments: could not parse calendar-tasks.json:", error);
            }
        }
    }
}
