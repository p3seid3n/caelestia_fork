pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services

// Super + Tab, like Alt + Tab on Windows: while Super is held, Tab (Shift + Tab back) walks
// through the windows of the current workspace, most recently used first; letting go of Super
// focuses (and in floating mode raises) the chosen one. modules/switcher draws it.
// The order is kept here from Hyprland's focus changes, so opening needs no IPC round trip.
Singleton {
    id: root

    property bool open
    property int index
    // Snapshot taken when the switcher opens: [HyprlandToplevel]
    property var entries: []
    // Most recently focused first (normalised addresses).
    property var recent: []
    // Super's release also reaches the launcher shortcut; it is ignored right after the switcher.
    property bool swallowSuper

    function norm(address: string): string {
        return String(address ?? "").toLowerCase().replace(/^0x/, "");
    }

    function snapshot(): var {
        const ws = Hypr.focusedWorkspace;
        const list = (ws?.toplevels.values ?? []).filter(t => t && !String(t.workspace?.name ?? "").startsWith("special"));
        const rank = t => {
            const i = recent.indexOf(norm(t.address));
            if (i >= 0)
                return i;
            const h = t.lastIpcObject?.focusHistoryID;
            return typeof h === "number" ? 1000 + h : 100000;
        };
        return list.sort((a, b) => rank(a) - rank(b));
    }

    // Tab: opens the switcher on the previous window, or moves on.
    function next(): void {
        step(1);
    }

    function prev(): void {
        step(-1);
    }

    function step(by: int): void {
        if (!open) {
            const list = snapshot();
            if (list.length === 0)
                return;
            entries = list;
            index = list.length > 1 ? (by > 0 ? 1 : list.length - 1) : 0;
            swallowSuper = true;
            swallowTimer.stop();
            open = true;
            return;
        }
        if (entries.length > 0)
            index = (index + by + entries.length) % entries.length;
    }

    function select(i: int): void {
        if (open && i >= 0 && i < entries.length)
            index = i;
    }

    function commit(): void {
        if (!open)
            return;
        const t = entries[index] ?? null;
        close();
        if (!t)
            return;
        const a = "0x" + norm(t.address);
        if (Hypr.usingLua)
            Hypr.dispatch(`hl.dsp.focus({ window = "address:${a}" })`);
        else
            Hypr.extras.batchMessage([`dispatch focuswindow address:${a}`, `dispatch alterzorder top,address:${a}`]);
    }

    function close(): void {
        open = false;
        entries = [];
        swallowTimer.restart();
    }

    Connections {
        function onActiveToplevelChanged(): void {
            const t = Hyprland.activeToplevel;
            if (!t)
                return;
            const a = root.norm(t.address);
            const next = root.recent.filter(r => r !== a);
            next.unshift(a);
            root.recent = next.slice(0, 64);
        }

        target: Hyprland
    }

    Timer {
        id: swallowTimer

        interval: 400
        onTriggered: root.swallowSuper = false
    }
}
