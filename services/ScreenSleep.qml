pragma Singleton

import QtQuick
import Quickshell

// Screens going to sleep and waking up, without the hard cut: the picture fades to black
// before the monitors switch off, and fades back in once they are on again. Moving the mouse
// while it fades out cancels it. `cover` (0..1) is the black drawn over everything
// (modules/SleepFade.qml on the desktop, the lock screens draw it themselves).
Singleton {
    id: root

    property real cover
    // The monitors are off (dpms).
    property bool off

    function dpms(on: bool): void {
        Hypr.dispatch(Hypr.usingLua ? `hl.dsp.dpms({ action = "${on ? "enable" : "disable"}" })` : `dpms ${on ? "on" : "off"}`);
    }

    function sleep(): void {
        if (off || fadeOut.running)
            return;
        fadeIn.stop();
        fadeOut.restart();
    }

    function wake(): void {
        if (fadeOut.running) {
            // Woken while still fading: just come back.
            fadeOut.stop();
            cancel.restart();
            return;
        }
        if (!off)
            return;
        off = false;
        dpms(true);
        cover = 1;
        fadeIn.restart();
    }

    SequentialAnimation {
        id: fadeOut

        NumberAnimation {
            target: root
            property: "cover"
            to: 1
            duration: 1100
            easing.type: Easing.InOutSine
        }
        ScriptAction {
            script: {
                root.off = true;
                root.dpms(false);
            }
        }
    }

    NumberAnimation {
        id: cancel

        target: root
        property: "cover"
        to: 0
        duration: 260
        easing.type: Easing.OutCubic
    }

    SequentialAnimation {
        id: fadeIn

        // Monitors take a moment to show a picture again; fading before that is wasted.
        PauseAnimation {
            duration: 450
        }
        NumberAnimation {
            target: root
            property: "cover"
            to: 0
            duration: 700
            easing.type: Easing.OutCubic
        }
    }
}
