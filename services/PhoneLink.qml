pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Phones and tablets paired through KDE Connect (for "Super devices" in quick settings).
// Nothing runs unless something on screen uses it (addUser() / removeUser()), and then
// only a small shell script every 20 seconds: device list, reachability, type and battery from
// KDE Connect's D-Bus interface. Without KDE Connect installed `available` stays false.
Singleton {
    id: root

    property bool available
    // [{ id, name, type: "phone" | "tablet" | "laptop" | "desktop" | "tv", reachable, charge (-1 when
    //   unknown), charging }]
    property var devices: []
    property int users
    // Device waiting for a file from the picker (utilities/Wrapper.qml owns the picker, so it
    // survives the panel closing).
    property string shareTarget

    signal shareRequested

    function refresh(): void {
        if (!listProc.running)
            listProc.running = true;
    }

    function run(args: list<string>): void {
        Quickshell.execDetached(["kdeconnect-cli"].concat(args));
    }

    // Makes the phone ring loudly (to find it).
    function ring(id: string): void {
        run(["-d", id, "--ring"]);
    }

    function ping(id: string): void {
        run(["-d", id, "--ping"]);
    }

    // Sends this computer's clipboard to the device.
    function sendClipboard(id: string): void {
        Quickshell.execDetached(["sh", "-c", "kdeconnect-cli -d \"$1\" --share-text \"$(wl-paste --no-newline 2>/dev/null)\"", "sh", id]);
    }

    // Sends a file (or opens a link) on the device.
    function share(id: string, path: string): void {
        run(["-d", id, "--share", path]);
    }

    function requestShare(id: string): void {
        shareTarget = id;
        shareRequested();
    }

    function addUser(): void {
        users++;
        refresh();
    }

    function removeUser(): void {
        users = Math.max(0, users - 1);
    }

    function iconFor(type: string): string {
        switch (type) {
        case "tablet":
            return "tablet_android";
        case "laptop":
            return "laptop";
        case "desktop":
            return "desktop_windows";
        case "tv":
            return "tv";
        default:
            return "smartphone";
        }
    }

    Timer {
        running: root.users > 0 && root.available
        repeat: true
        interval: 20000
        onTriggered: root.refresh()
    }

    Process {
        id: listProc

        command: ["sh", "-c", `
            command -v kdeconnect-cli >/dev/null 2>&1 || exit 3
            prop() { busctl --user get-property org.kde.kdeconnect "$1" "$2" "$3" 2>/dev/null | cut -d' ' -f2- | tr -d '"'; }
            kdeconnect-cli -l --id-name-only 2>/dev/null | while read -r id name; do
                [ -n "$id" ] || continue
                dev=/modules/kdeconnect/devices/$id
                printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' "$id" "$name" \\
                    "$(prop $dev org.kde.kdeconnect.device type)" \\
                    "$(prop $dev org.kde.kdeconnect.device isReachable)" \\
                    "$(prop $dev/battery org.kde.kdeconnect.device.battery charge)" \\
                    "$(prop $dev/battery org.kde.kdeconnect.device.battery isCharging)"
            done
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = [];
                for (const line of text.split("\n")) {
                    const f = line.split("\t");
                    if (f.length < 6 || !f[0])
                        continue;
                    const charge = parseInt(f[4]);
                    list.push({
                        id: f[0],
                        name: f[1] || f[0],
                        type: f[2] || "phone",
                        reachable: f[3] === "true",
                        charge: isNaN(charge) ? -1 : charge,
                        charging: f[5] === "true"
                    });
                }
                root.devices = list;
            }
        }
        onExited: code => root.available = code !== 3
    }
}
