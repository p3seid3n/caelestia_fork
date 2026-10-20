pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components.misc
import qs.services

Scope {
    property alias lock: lock

    WlSessionLock {
        id: lock

        signal unlock

        // KairosOS: "style" in ~/.config/caelestia/kairos-lock.json picks the lock screen.
        surface: LockStyle.kairos ? kairosSurface : caelestiaSurface
    }

    Component {
        id: kairosSurface

        KairosSurface {
            lock: lock
            pam: pam
        }
    }

    Component {
        id: caelestiaSurface

        LockSurface {
            lock: lock
            pam: pam
        }
    }

    Pam {
        id: pam

        lock: lock
    }

    Loader {
        asynchronous: true
        active: true
        onLoaded: active = false

        // Force a load of a screencopy so the one in the lock works
        // My guess is the ICC backend loads async on first request, which if the lock is
        // the first request it fails to capture (because it's async and the compositor
        // refuses capture when locked)
        sourceComponent: ScreencopyView {
            captureSource: Quickshell.screens[0]
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "lock"
        description: "Lock the current session"
        onPressed: lock.locked = true
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "unlock"
        description: "Unlock the current session"
        onPressed: lock.unlock()
    }

    // KairosOS: lock screen as login screen.
    // With greetd autologin, the session is started with KAIROS_LOCK_ON_START=1 and the
    // shell locks itself once per login. A marker in $XDG_RUNTIME_DIR (cleared at logout/
    // reboot) stops it from locking again when the shell is merely restarted.
    Process {
        running: Quickshell.env("KAIROS_LOCK_ON_START") === "1"
        command: ["sh", "-c", "m=\"${XDG_RUNTIME_DIR:-/tmp}/kairos-startlock\"; [ -e \"$m\" ] && exit 1; touch \"$m\""]
        onExited: code => {
            if (code === 0)
                lock.locked = true;
        }
    }

    IpcHandler {
        function lock(): void {
            lock.locked = true;
        }

        function unlock(): void {
            lock.unlock();
        }

        function isLocked(): bool {
            return lock.locked;
        }

        target: "lock"
    }
}
