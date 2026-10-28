pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Night light through gammastep (started by the Hyprland config; it follows the sun using the
// location provider). gammastep switches itself off and on with SIGUSR1, so a running gammastep
// counts as on; if it is not running, switching on starts it.
Singleton {
    id: root

    property bool available
    property bool on
    property bool running

    function toggle(): void {
        if (!available)
            return;
        if (running) {
            Quickshell.execDetached(["pkill", "-USR1", "-x", "gammastep"]);
            on = !on;
        } else {
            Quickshell.execDetached(["sh", "-c", "gammastep >/dev/null 2>&1 &"]);
            on = true;
            running = true;
        }
    }

    Component.onCompleted: check.running = true

    Process {
        id: check

        command: ["sh", "-c", "command -v gammastep >/dev/null 2>&1 || exit 3; pgrep -x gammastep >/dev/null && exit 0 || exit 1"]
        onExited: code => {
            root.available = code !== 3;
            root.running = code === 0;
            root.on = code === 0;
        }
    }
}
