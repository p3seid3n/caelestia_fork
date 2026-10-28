pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.I18n
import qs.utils

// KairosOS lock screen settings, in ~/.config/caelestia/kairos-lock.json. Edited from
// Settings → Lock screen, or by hand; every key is optional and an empty colour means
// "use the Material You theme colour".
//
// {
//     "style": "kairos",            // "kairos" (black AoD clock) or "caelestia" (original lock screen)
//     "hourColour": "",             // e.g. "#F7D51D"
//     "minuteColour": "",           // e.g. "#0046AF"
//     "accentColour": "",           // password bar and date, e.g. "#E60012"
//     "aodTimeout": 20,             // seconds without input before falling back to the AoD clock
//     "faceOnWake": true,           // start Howdy face unlock as soon as the screen wakes
//     "wallpaperWhenAwake": true,   // blurred wallpaper behind the awake lock (AoD stays black)
//     "showMedia": true,            // what is playing, with controls
//     "showNotifications": true,    // the latest notifications (also see lock.hideNotifs)
//     "powerButtons": true,         // sleep, restart and shut down
//     "drift": true                 // move the AoD clock a little now and then (OLED burn-in)
// }
Singleton {
    id: root

    property string style: "kairos"
    property string hourColour
    property string minuteColour
    property string accentColour
    property int aodTimeout: 20
    property bool faceOnWake: true
    property bool wallpaperWhenAwake: true
    property bool showMedia: true
    property bool showNotifications: true
    property bool powerButtons: true
    property bool drift: true

    readonly property bool kairos: style !== "caelestia"

    // "", "busy", "done" or "failed": the last "Use on the login screen".
    property string greeterSync

    // Writes these settings (colours resolved against the current theme, so the login screen
    // looks like the lock screen now) to /etc/kairos/greeter.json and copies the greeter from
    // this shell to /usr/share/kairos-greeter. Asks for the admin password (pkexec).
    function exportToGreeter(): void {
        if (greeterSync === "busy")
            return;
        let base = {};
        try {
            base = JSON.parse(greeterFile.text() || "{}");
        } catch (error) {
            base = {};
        }
        const p = Colours.palette;
        const hex = c => {
            const h = v => {
                const x = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16);
                return x.length < 2 ? "0" + x : x;
            };
            return "#" + h(c.r) + h(c.g) + h(c.b);
        };
        const conf = Object.assign({}, base, {
            user: base.user || Quickshell.env("USER"),
            command: base.command ?? ["/usr/bin/start-hyprland"],
            hourColour: hourColour || hex(p.m3primary),
            minuteColour: minuteColour || hex(p.m3secondary),
            accentColour: accentColour || hex(p.m3primary),
            surfaceColour: hex(p.m3surfaceContainer),
            textColour: hex(p.m3onSurface),
            errorColour: hex(p.m3error),
            aodTimeout,
            drift,
            powerButtons
        });
        greeterProc.payload = JSON.stringify(conf, null, 4) + "\n";
        greeterSync = "busy";
        greeterProc.running = true;
    }

    function setOption(key: string, value: var): void {
        if (root[key] === value)
            return;
        root[key] = value;
        saveTimer.restart();
    }

    FileView {
        id: greeterFile

        path: "/etc/kairos/greeter.json"
        printErrors: false
    }

    Process {
        id: greeterProc

        property string payload

        command: ["pkexec", "sh", "-c", "mkdir -p /etc/kairos /usr/share/kairos-greeter && cat > /etc/kairos/greeter.json && chmod 644 /etc/kairos/greeter.json && cp -r \"$1\"/. /usr/share/kairos-greeter/", "sh", `${Quickshell.shellDir}/greeter`]
        stdinEnabled: true
        onStarted: {
            write(payload);
            stdinEnabled = false;
        }
        onExited: code => {
            stdinEnabled = true;
            root.greeterSync = code === 0 ? "done" : "failed";
            greeterFile.reload();
            if (code === 0)
                Toaster.toast(Tr.tr("Login screen updated"), Tr.tr("It looks like the lock screen from the next login on"), "login");
            else
                Toaster.toast(Tr.tr("Login screen not updated"), Tr.tr("The admin password was not given, or writing to /etc failed"), "error");
        }
    }

    Timer {
        id: saveTimer

        interval: 300
        onTriggered: file.setText(JSON.stringify({
                style: root.style,
                hourColour: root.hourColour,
                minuteColour: root.minuteColour,
                accentColour: root.accentColour,
                aodTimeout: root.aodTimeout,
                faceOnWake: root.faceOnWake,
                wallpaperWhenAwake: root.wallpaperWhenAwake,
                showMedia: root.showMedia,
                showNotifications: root.showNotifications,
                powerButtons: root.powerButtons,
                drift: root.drift
            }, null, 4))
    }

    FileView {
        id: file

        path: `${Paths.config}/kairos-lock.json`
        watchChanges: true
        blockLoading: true // the lock can be requested right at shell start
        printErrors: false

        onFileChanged: reload()
        onLoaded: {
            try {
                const c = JSON.parse(text());
                root.style = c.style ?? "kairos";
                root.hourColour = c.hourColour ?? "";
                root.minuteColour = c.minuteColour ?? "";
                root.accentColour = c.accentColour ?? "";
                root.aodTimeout = c.aodTimeout ?? 20;
                root.faceOnWake = c.faceOnWake ?? true;
                root.wallpaperWhenAwake = c.wallpaperWhenAwake ?? true;
                root.showMedia = c.showMedia ?? true;
                root.showNotifications = c.showNotifications ?? true;
                root.powerButtons = c.powerButtons ?? true;
                root.drift = c.drift ?? true;
            } catch (error) {
                console.warn("LockStyle: could not parse kairos-lock.json:", error);
            }
        }
    }
}
