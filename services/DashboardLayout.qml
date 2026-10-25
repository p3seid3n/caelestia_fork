pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.I18n
import qs.utils

// Which dashboard tabs exist, in which order. Edited from the dashboard itself
// (the tune button in the tab bar) and kept in ~/.local/state/caelestia/dashboard-layout.json.
//
// This lives in QML on purpose: the show* flags of the dashboard config belong to the
// C++ config plugin, which this fork leaves untouched. The old flags still work as an
// additional "off" switch for the tabs that have one (Dashboard, Media, Performance, Weather).
Singleton {
    id: root

    // Every tab the dashboard knows, in its default order.
    readonly property var allTabs: ["calendar", "todo", "home", "dashboard", "classic", "media", "performance", "weather"]
    // Tabs that are on until the user changes it.
    readonly property var defaultOn: ["calendar", "todo", "home", "dashboard"]

    // Display order of all tabs (also the hidden ones) and the ones that are switched on.
    property var order: allTabs.slice()
    property var enabledIds: defaultOn.slice()

    // Name and icon of every tab, for the customise sheet.
    readonly property var meta: ({
            calendar: {
                name: Tr.tr("Calendar"),
                icon: "calendar_month"
            },
            todo: {
                name: Tr.tr("To-do"),
                icon: "checklist"
            },
            home: {
                name: Tr.tr("Home"),
                icon: "home"
            },
            dashboard: {
                name: Tr.tr("Dashboard"),
                icon: "dashboard"
            },
            classic: {
                name: Tr.tr("Classic dashboard"),
                icon: "dashboard_customize"
            },
            media: {
                name: Tr.tr("Media"),
                icon: "queue_music"
            },
            performance: {
                name: Tr.tr("Performance"),
                icon: "speed"
            },
            weather: {
                name: Tr.tr("Weather"),
                icon: "cloud"
            }
        })

    // The tabs to show, in order.
    readonly property var visibleTabs: order.filter(id => enabledIds.includes(id))

    function isEnabled(id: string): bool {
        return enabledIds.includes(id);
    }

    function setEnabled(id: string, on: bool): void {
        if (on === isEnabled(id))
            return;
        // There always has to be a tab left to show.
        if (!on && enabledIds.length <= 1)
            return;
        enabledIds = on ? enabledIds.concat([id]) : enabledIds.filter(t => t !== id);
        saveTimer.restart();
    }

    // Moves a tab one step up (-1) or down (+1) in the list.
    function move(id: string, delta: int): void {
        const from = order.indexOf(id);
        const to = from + delta;
        if (from < 0 || to < 0 || to >= order.length)
            return;
        const next = order.slice();
        next.splice(from, 1);
        next.splice(to, 0, id);
        order = next;
        saveTimer.restart();
    }

    function reset(): void {
        order = allTabs.slice();
        enabledIds = defaultOn.slice();
        saveTimer.restart();
    }

    Timer {
        id: saveTimer

        interval: 400
        onTriggered: file.setText(JSON.stringify({
                order: root.order,
                enabled: root.enabledIds
            }))
    }

    FileView {
        id: file

        printErrors: false
        path: `${Paths.state}/dashboard-layout.json`
        onLoaded: {
            try {
                const c = JSON.parse(text());
                // Unknown ids are dropped, tabs added by an update are appended.
                const known = (c.order ?? []).filter(id => root.allTabs.includes(id));
                root.order = known.concat(root.allTabs.filter(id => !known.includes(id)));
                const on = (c.enabled ?? []).filter(id => root.allTabs.includes(id));
                if (on.length > 0)
                    root.enabledIds = on;
            } catch (error) {
                console.warn("DashboardLayout: could not parse layout:", error);
            }
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => setText(JSON.stringify({
                        order: root.allTabs,
                        enabled: root.defaultOn
                    })));
        }
    }
}
