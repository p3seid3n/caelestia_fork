pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

// Monitors for Settings → Display: resolution and refresh rate, scale, rotation, variable refresh
// rate and turning outputs on or off. A change is tried live first; unless it is kept within
// 15 seconds it is undone, like on Windows and macOS, so a mode the screen cannot show fixes
// itself. Kept settings are remembered per monitor (by its description, so they follow the screen
// to another port) in ~/.local/state/caelestia/displays.json and applied again on shell start and
// after Hyprland config reloads.
Singleton {
    id: root

    // From `hyprctl -j monitors all`.
    property var monitors: []
    // description -> {mode, scale, transform, vrr, disabled}
    property var saved: ({})

    // A change waiting to be kept: {name, desc, previous, next}
    property var pending: null
    property int countdown

    readonly property bool lua: Hypr.usingLua
    property bool listed

    function refresh(): void {
        lister.running = true;
    }

    function byName(name: string): var {
        return monitors.find(m => m.name === name) ?? null;
    }

    function currentOf(m: var): var {
        return {
            mode: `${m.width}x${m.height}@${Number(m.refreshRate).toFixed(2)}`,
            scale: Number(m.scale),
            transform: m.transform ?? 0,
            vrr: m.vrr ? 1 : 0,
            disabled: m.disabled === true,
            position: `${m.x}x${m.y}`
        };
    }

    // Modes as "2560x1440@165.00", best first, without duplicates.
    function modesOf(m: var): var {
        const seen = new Set();
        const out = [];
        for (const raw of m?.availableModes ?? []) {
            const match = /^(\d+)x(\d+)@([\d.]+)/.exec(raw);
            if (!match)
                continue;
            const key = `${match[1]}x${match[2]}@${Number(match[3]).toFixed(2)}`;
            if (seen.has(key))
                continue;
            seen.add(key);
            out.push({
                key: key,
                w: parseInt(match[1]),
                h: parseInt(match[2]),
                hz: Number(match[3])
            });
        }
        return out.sort((a, b) => b.w * b.h - a.w * a.h || b.hz - a.hz);
    }

    function message(name: string, s: var): string {
        if (lua) {
            if (s.disabled)
                return `eval hl.monitor({ output = "${name}", disabled = true })`;
            return `eval hl.monitor({ output = "${name}", mode = "${s.mode}", position = "${s.position ?? "auto"}", scale = ${s.scale}, transform = ${s.transform}, vrr = ${s.vrr} })`;
        }
        if (s.disabled)
            return `keyword monitor ${name},disable`;
        return `keyword monitor ${name},${s.mode},${s.position ?? "auto"},${s.scale},transform,${s.transform},vrr,${s.vrr}`;
    }

    // Tries `changes` on a monitor; keep() or revert() follows (revert() by itself after 15 s).
    function tryChange(name: string, changes: var): void {
        const m = byName(name);
        if (!m)
            return;
        if (pending)
            revert();
        const previous = currentOf(m);
        const next = Object.assign({}, previous, changes);
        // Turning off the last screen would leave nothing to click "Keep" on.
        if (next.disabled && monitors.filter(x => !x.disabled).length <= 1)
            return;
        pending = {
            name: name,
            desc: m.description,
            previous: previous,
            next: next
        };
        Hypr.extras.message(message(name, next));
        countdown = 15;
        revertTimer.restart();
        refreshLater.restart();
    }

    function keep(): void {
        if (!pending)
            return;
        const next = Object.assign({}, saved);
        const s = Object.assign({}, pending.next);
        delete s.position;
        next[pending.desc] = s;
        saved = next;
        pending = null;
        revertTimer.stop();
        saveTimer.restart();
    }

    function revert(): void {
        if (!pending)
            return;
        Hypr.extras.message(message(pending.name, pending.previous));
        pending = null;
        revertTimer.stop();
        refreshLater.restart();
    }

    // Forgets the remembered settings of a monitor; the Hyprland config applies again.
    function forget(desc: string): void {
        const next = Object.assign({}, saved);
        delete next[desc];
        saved = next;
        saveTimer.restart();
        Hypr.extras.message("reload");
    }

    function applySaved(): void {
        const msgs = [];
        for (const m of monitors) {
            const s = saved[m.description];
            if (s)
                msgs.push(message(m.name, Object.assign({
                    position: `${m.x}x${m.y}`
                }, s)));
        }
        for (const msg of msgs)
            Hypr.extras.message(msg);
        if (msgs.length > 0)
            refreshLater.restart();
    }

    Component.onCompleted: refresh()

    Connections {
        function onConfigReloaded(): void {
            startApply.restart();
        }

        target: Hypr
    }

    Timer {
        id: revertTimer

        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown -= 1;
            if (root.countdown <= 0)
                root.revert();
        }
    }

    Timer {
        id: refreshLater

        interval: 700
        onTriggered: root.refresh()
    }

    Timer {
        id: startApply

        interval: 900
        onTriggered: root.applySaved()
    }

    Timer {
        id: saveTimer

        interval: 400
        onTriggered: file.setText(JSON.stringify({
                displays: root.saved
            }))
    }

    FileView {
        id: file

        printErrors: false
        path: `${Paths.state}/displays.json`
        onLoaded: {
            try {
                const c = JSON.parse(text());
                const out = {};
                for (const desc in c.displays ?? {}) {
                    const s = c.displays[desc];
                    if (typeof s.mode === "string" && /^\d+x\d+@[\d.]+$/.test(s.mode))
                        out[desc] = {
                            mode: s.mode,
                            scale: Number(s.scale) > 0 ? Number(s.scale) : 1,
                            transform: Math.max(0, Math.min(7, parseInt(s.transform) || 0)),
                            vrr: s.vrr ? 1 : 0,
                            disabled: s.disabled === true
                        };
                }
                root.saved = out;
            } catch (error) {
                console.warn("Displays: could not parse displays.json:", error);
            }
            startApply.restart();
        }
    }

    Process {
        id: lister

        command: ["hyprctl", "-j", "monitors", "all"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const list = JSON.parse(text);
                    if (Array.isArray(list))
                        root.monitors = list;
                    // Remembered settings go on once the monitors are known.
                    if (!root.listed) {
                        root.listed = true;
                        startApply.restart();
                    }
                } catch (error) {
                    console.warn("Displays: could not read monitors:", error);
                }
            }
        }
    }

    IpcHandler {
        function keep(): void {
            root.keep();
        }

        function revert(): void {
            root.revert();
        }

        target: "displays"
    }
}
