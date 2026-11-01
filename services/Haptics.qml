pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

// "Haptics" for a desktop: very short, very low pulses (40-70 Hz, under 0.1 s) played through the
// speakers. On a setup with a subwoofer they are felt more than heard - a bump when something
// snaps into place, like the haptic engine of a phone. Used by Super devices (and anything else
// that wants a tactile cue). Off in the settings (Audio) or with a volume of 0.
//   tick     something comes into reach (a device near the centre)
//   snap     it locks into place (connected)
//   release  it lets go (disconnected)
Singleton {
    id: root

    property bool enabled: true
    property real volume: 0.7

    function play(kind: string): void {
        if (!enabled || volume <= 0)
            return;
        const file = Quickshell.shellPath(`assets/haptics/${kind}.wav`);
        Quickshell.execDetached(["sh", "-c", "command -v pw-play >/dev/null && exec pw-play --volume \"$1\" \"$2\" || exec paplay \"$2\"", "sh", String(volume), file]);
    }

    function tick(): void {
        play("tick");
    }

    function snap(): void {
        play("snap");
    }

    function release(): void {
        play("release");
    }

    function setEnabled(on: bool): void {
        enabled = on;
        saveTimer.restart();
    }

    function setVolume(v: real): void {
        volume = Math.max(0, Math.min(1, v));
        saveTimer.restart();
    }

    Timer {
        id: saveTimer

        interval: 400
        onTriggered: file.setText(JSON.stringify({
                enabled: root.enabled,
                volume: root.volume
            }))
    }

    FileView {
        id: file

        printErrors: false
        path: `${Paths.state}/haptics.json`
        onLoaded: {
            try {
                const c = JSON.parse(text());
                root.enabled = c.enabled !== false;
                if (typeof c.volume === "number")
                    root.volume = Math.max(0, Math.min(1, c.volume));
            } catch (e) {}
        }
    }
}
