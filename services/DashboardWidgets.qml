pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.I18n
import qs.utils

// The widgets on the dashboard board and where they sit: an ordered list that the board packs onto
// an 8 column grid (first free spot, left to right, top to bottom), like the Home tab does with
// devices. Edited from the board itself and kept in ~/.local/state/caelestia/dashboard-widgets.json.
Singleton {
    id: root

    readonly property int columns: 8

    // The kinds of widget there are. w/h are the starting size and min*/max* the limits for resizing,
    // all counted in grid cells.
    readonly property var types: ({
            clock: {
                name: Tr.tr("Clock"),
                icon: "schedule",
                info: Tr.tr("Time and date."),
                w: 2,
                h: 2,
                minW: 2,
                minH: 1,
                maxW: 4,
                maxH: 2
            },
            weather: {
                name: Tr.tr("Weather"),
                icon: "partly_cloudy_day",
                info: Tr.tr("Current weather at your location."),
                w: 2,
                h: 2,
                minW: 2,
                minH: 1,
                maxW: 4,
                maxH: 2
            },
            month: {
                name: Tr.tr("Month"),
                icon: "calendar_month",
                info: Tr.tr("This month, with a dot on days that have events."),
                w: 4,
                h: 4,
                minW: 3,
                minH: 3,
                maxW: 5,
                maxH: 4
            },
            agenda: {
                name: Tr.tr("Agenda"),
                icon: "event_upcoming",
                info: Tr.tr("What is coming up in your calendars."),
                w: 4,
                h: 2,
                minW: 2,
                minH: 2,
                maxW: 5,
                maxH: 4
            },
            todo: {
                name: Tr.tr("To-do"),
                icon: "checklist",
                info: Tr.tr("Open tasks you can tick off."),
                w: 3,
                h: 3,
                minW: 2,
                minH: 2,
                maxW: 5,
                maxH: 4
            },
            media: {
                name: Tr.tr("Media"),
                icon: "music_note",
                info: Tr.tr("What is playing, with the controls."),
                w: 4,
                h: 2,
                minW: 3,
                minH: 2,
                maxW: 5,
                maxH: 2
            },
            resources: {
                name: Tr.tr("System"),
                icon: "speed",
                info: Tr.tr("Processor, memory and disk use."),
                w: 3,
                h: 2,
                minW: 2,
                minH: 2,
                maxW: 5,
                maxH: 3
            }
        })

    readonly property var typeIds: ["clock", "weather", "month", "agenda", "todo", "media", "resources"]

    // [{id, type, w, h}] in packing order.
    property var widgets: defaults()

    readonly property var byId: {
        const map = {};
        for (const w of widgets)
            map[w.id] = w;
        return map;
    }

    function defaults(): var {
        return [
            {
                id: "clock",
                type: "clock",
                w: 2,
                h: 2
            },
            {
                id: "weather",
                type: "weather",
                w: 2,
                h: 2
            },
            {
                id: "month",
                type: "month",
                w: 4,
                h: 4
            },
            {
                id: "agenda",
                type: "agenda",
                w: 4,
                h: 2
            }
        ];
    }

    function clamp(type: string, w: int, h: int): var {
        const t = types[type];
        return {
            w: Math.max(t.minW, Math.min(t.maxW, w)),
            h: Math.max(t.minH, Math.min(t.maxH, h))
        };
    }

    function add(type: string): void {
        const t = types[type];
        if (!t)
            return;
        const id = type + "-" + Date.now().toString(36) + Math.random().toString(36).slice(2, 5);
        widgets = widgets.concat([
            {
                id: id,
                type: type,
                w: t.w,
                h: t.h
            }
        ]);
        saveTimer.restart();
    }

    function remove(id: string): void {
        widgets = widgets.filter(w => w.id !== id);
        saveTimer.restart();
    }

    // Moves the widget at index `from` to index `to`.
    function move(from: int, to: int): void {
        if (from < 0 || to < 0 || from >= widgets.length || to >= widgets.length || from === to)
            return;
        const next = widgets.slice();
        next.splice(to, 0, next.splice(from, 1)[0]);
        widgets = next;
        saveTimer.restart();
    }

    function resize(id: string, w: int, h: int): void {
        const cur = byId[id];
        if (!cur)
            return;
        const size = clamp(cur.type, w, h);
        if (size.w === cur.w && size.h === cur.h)
            return;
        widgets = widgets.map(x => x.id === id ? Object.assign({}, x, size) : x);
        saveTimer.restart();
    }

    function reset(): void {
        widgets = defaults();
        saveTimer.restart();
    }

    Timer {
        id: saveTimer

        interval: 400
        onTriggered: file.setText(JSON.stringify({
                widgets: root.widgets
            }))
    }

    FileView {
        id: file

        printErrors: false
        path: `${Paths.state}/dashboard-widgets.json`
        onLoaded: {
            try {
                const c = JSON.parse(text());
                if (!Array.isArray(c.widgets))
                    return;
                const seen = new Set();
                root.widgets = c.widgets.filter(w => typeof w.id === "string" && root.types[w.type] && !seen.has(w.id) && seen.add(w.id)).map(w => Object.assign({
                            id: w.id,
                            type: w.type
                        }, root.clamp(w.type, Math.round(Number(w.w)) || root.types[w.type].w, Math.round(Number(w.h)) || root.types[w.type].h)));
            } catch (error) {
                console.warn("DashboardWidgets: could not parse layout:", error);
            }
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => setText(JSON.stringify({
                        widgets: root.defaults()
                    })));
        }
    }
}
