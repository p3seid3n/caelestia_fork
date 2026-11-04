pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.I18n
import qs.utils

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

    // Huawei-style links (dragging a device onto this PC in Super devices):
    //   tablet -> drawing tablet / second screen through Weylus; its browser opens the page itself
    //   phone  -> its screen in a window through scrcpy (needs USB debugging or `adb pair` once)
    property bool hasWeylus
    property bool hasScrcpy
    property string extendedTo // device id Weylus was started for
    property string mirroring // device id scrcpy was started for
    // Weylus' access code, made once and kept (only sent to your own devices).
    property string accessCode

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

    // Starts Weylus (headless, Wayland capture) and opens its page on the tablet, with the code.
    function extend(id: string): void {
        if (!hasWeylus)
            return;
        if (!accessCode)
            accessCode = String(Math.floor(100000 + Math.random() * 900000));
        extendedTo = id;
        Quickshell.execDetached(["sh", "-c", `
            pgrep -x weylus >/dev/null || (weylus --no-gui --auto-start --wayland-support --access-code "$2" >/dev/null 2>&1 &)
            ip=$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \\([0-9.]*\\).*/\\1/p')
            sleep 1
            [ -n "$ip" ] && kdeconnect-cli -d "$1" --share "http://$ip:1701/?access_code=$2"
        `, "sh", id, accessCode]);
        saveTimer.restart();
    }

    function stopExtend(): void {
        extendedTo = "";
        Quickshell.execDetached(["pkill", "-x", "weylus"]);
    }

    // Shows the phone's screen in a window (scrcpy over adb).
    function mirror(id: string, name: string): void {
        if (!hasScrcpy)
            return;
        mirroring = id;
        // Wireless debugging often lists one phone twice (ip:port and an mDNS name), which scrcpy
        // refuses; pick one entry (the ip:port one when there is one) and say so if it still fails.
        mirrorProc.command = ["sh", "-c", `
            list=$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device" {print $1}')
            serial=$(printf '%s\\n' "$list" | grep -E '^[0-9.]+:[0-9]+$' | head -n1)
            [ -n "$serial" ] || serial=$(printf '%s\\n' "$list" | head -n1)
            [ -n "$serial" ] || { echo "No device found by adb" >&2; exit 1; }
            exec scrcpy -s "$serial" --window-title "$1" --stay-awake --turn-screen-off
        `, "sh", name || "Phone"];
        mirrorProc.running = true;
    }

    function stopMirror(): void {
        mirroring = "";
        mirrorProc.running = false;
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
        id: mirrorProc

        stderr: StdioCollector {
            id: mirrorErr
        }

        onExited: code => {
            if (root.mirroring !== "" && code !== 0 && code !== 15) {
                // scrcpy's own last error line says what is wrong.
                const lines = mirrorErr.text.split("\n").map(l => l.replace(/^ERROR:\s*/, "").trim()).filter(l => l && !l.startsWith("-->"));
                Toaster.toast(Tr.tr("Phone screen"), lines.length > 0 ? lines[lines.length - 1] : Tr.tr("Couldn't reach the phone over adb. Turn on wireless debugging and pair it once, then try again."), "mobile_off");
            }
            root.mirroring = "";
        }
    }

    Timer {
        id: saveTimer

        interval: 300
        onTriggered: codeFile.setText(JSON.stringify({
                accessCode: root.accessCode
            }))
    }

    FileView {
        id: codeFile

        printErrors: false
        path: `${Paths.state}/phonelink.json`
        onLoaded: {
            try {
                root.accessCode = JSON.parse(text()).accessCode ?? "";
            } catch (e) {}
        }
    }

    Process {
        id: listProc

        command: ["sh", "-c", `
            printf '#tools\\t%s\\t%s\\n' "$(command -v weylus >/dev/null && echo 1)" "$(command -v scrcpy >/dev/null && echo 1)"
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
                    if (f[0] === "#tools") {
                        root.hasWeylus = f[1] === "1";
                        root.hasScrcpy = f[2] === "1";
                        continue;
                    }
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
