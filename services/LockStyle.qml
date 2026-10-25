pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
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

    function setOption(key: string, value: var): void {
        if (root[key] === value)
            return;
        root[key] = value;
        saveTimer.restart();
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
