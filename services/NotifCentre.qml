pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

// The notification centre: a popup at the top right corner of the screen that opens when the
// pointer touches the right part of the top edge, like the dashboard does in the middle and the
// utilities popup in the bottom right corner (modules/notifcentre). Its settings are kept in
// ~/.local/state/caelestia/notifcentre.json.
//
// It also finds out who receives the system's notifications: only one program can, and when
// another one (mako, dunst, swaync, ...) got there first, the shell never sees a notification.
Singleton {
    id: root

    property bool enabled: true
    // Width of the strip of the top edge that opens it, from the right corner.
    property int triggerWidth: 420

    // Program that owns org.freedesktop.Notifications ("" while unknown).
    property string owner
    readonly property bool conflict: owner !== "" && !/quickshell|caelestia|^qs$/i.test(owner)

    function setEnabled(on: bool): void {
        enabled = on;
        saveTimer.restart();
    }

    function checkOwner(): void {
        ownerCheck.running = true;
    }

    // Stops the other notification daemon and keeps it from starting again with the session.
    function stopOther(): void {
        if (!conflict)
            return;
        const name = owner.replace(/[^A-Za-z0-9_.-]/g, "");
        Quickshell.execDetached(["sh", "-c", `systemctl --user disable --now '${name}.service' 2>/dev/null; systemctl --user mask '${name}.service' 2>/dev/null; pkill -x '${name}'; sleep 1; true`]);
        recheck.restart();
    }

    Component.onCompleted: checkOwner()

    Timer {
        id: recheck

        interval: 2500
        onTriggered: root.checkOwner()
    }

    Timer {
        id: saveTimer

        interval: 400
        onTriggered: file.setText(JSON.stringify({
                enabled: root.enabled,
                triggerWidth: root.triggerWidth
            }))
    }

    FileView {
        id: file

        printErrors: false
        path: `${Paths.state}/notifcentre.json`
        onLoaded: {
            try {
                const c = JSON.parse(text());
                root.enabled = c.enabled !== false;
                if (typeof c.triggerWidth === "number")
                    root.triggerWidth = Math.max(80, Math.min(1200, Math.round(c.triggerWidth)));
            } catch (error) {
                console.warn("NotifCentre: could not parse notifcentre.json:", error);
            }
        }
    }

    // The PID that owns the notification name, then its command name.
    Process {
        id: ownerCheck

        command: ["sh", "-c", "pid=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s org.freedesktop.Notifications 2>/dev/null | awk '{print $2}'); [ -n \"$pid\" ] && cat /proc/$pid/comm 2>/dev/null; true"]
        stdout: StdioCollector {
            onStreamFinished: root.owner = text.trim()
        }
    }
}
