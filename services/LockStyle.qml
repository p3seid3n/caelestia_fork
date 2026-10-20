pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

// KairosOS lock screen settings, read from ~/.config/caelestia/kairos-lock.json.
// Every key is optional; an empty colour means "use the Material You theme colour".
//
// {
//     "style": "kairos",        // "kairos" (black AoD clock) or "caelestia" (original lock screen)
//     "hourColour": "",         // e.g. "#F7D51D"
//     "minuteColour": "",       // e.g. "#0046AF"
//     "accentColour": "",       // password bar and date, e.g. "#E60012"
//     "aodTimeout": 20,         // seconds without input before falling back to the AoD clock
//     "faceOnWake": true        // start Howdy face unlock as soon as the screen wakes
// }
Singleton {
    id: root

    property string style: "kairos"
    property string hourColour
    property string minuteColour
    property string accentColour
    property int aodTimeout: 20
    property bool faceOnWake: true

    readonly property bool kairos: style !== "caelestia"

    FileView {
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
            } catch (error) {
                console.warn("LockStyle: could not parse kairos-lock.json:", error);
            }
        }
    }
}
