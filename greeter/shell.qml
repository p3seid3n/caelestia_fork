//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd

// KairosOS greeter (login screen) for greetd.
// Same look as the Kairos lock screen: black, stacked AoD clock, minimal password bar.
// The password is checked by greetd/PAM BEFORE the session starts. On success the clock
// zooms away into black and Hyprland is launched with KAIROS_FROM_GREETER=1, so the
// shell can fade the desktop in from black (modules/Handoff.qml).
//
// Settings: /etc/kairos/greeter.json (see greeter.example.json).
// Preview without greetd: `qs -p ~/caelestia_fork/greeter` (any password, Enter finishes).
ShellRoot {
    id: shell

    // Config
    property string user
    property list<string> command: ["/usr/bin/start-hyprland"]
    property color hourColour: "#c4c0ff"
    property color minuteColour: "#c6c4dd"
    property color accentColour: "#c4c0ff"
    property color surfaceColour: "#201f23"
    property color textColour: "#e5e1e7"
    property color errorColour: "#ffb4ab"
    // Same meaning as on the lock screen (services/LockStyle.qml); written together with the
    // colours by Settings → Lock screen → "Use on the login screen".
    property int aodTimeout: 20
    property bool drift: true
    property bool powerButtons: true

    // State
    readonly property bool preview: !Greetd.available
    property bool awake
    property string buffer
    property bool showPassword
    property bool waitingForPrompt: true // greetd hasn't asked for the password yet
    property bool submitPending // Enter pressed before greetd asked
    property bool busy
    property bool leaving
    property string message

    signal failed

    function wake(): void {
        awake = true;
        idle.restart();
    }

    function submit(): void {
        if (busy || leaving)
            return;
        if (preview) {
            busy = true;
            previewDone.start();
            return;
        }
        if (buffer.length === 0)
            return;
        if (waitingForPrompt) {
            submitPending = true;
            busy = true;
            return;
        }
        busy = true;
        message = "";
        Greetd.respond(buffer);
        waitingForPrompt = true;
    }

    function startSession(): void {
        waitingForPrompt = true;
        submitPending = false;
        if (preview)
            return;
        if (!user) {
            console.warn("kairos-greeter: no user set in /etc/kairos/greeter.json");
            message = "No user set in /etc/kairos/greeter.json";
            return;
        }
        // A session left over (a failed try) has to be closed before a new one can start.
        if (Greetd.state !== GreetdState.Inactive)
            Greetd.cancelSession();
        console.info(`kairos-greeter: starting a session for ${user}`);
        Greetd.createSession(user);
    }

    function fail(text: string): void {
        busy = false;
        buffer = "";
        message = text;
        failed();
        startSession();
    }


    FileView {
        path: "/etc/kairos/greeter.json"
        blockLoading: true
        printErrors: false

        onLoaded: {
            try {
                const c = JSON.parse(text());
                shell.user = c.user ?? "";
                if (c.command)
                    shell.command = c.command;
                for (const key of ["hourColour", "minuteColour", "accentColour", "surfaceColour", "textColour", "errorColour"])
                    if (c[key])
                        shell[key] = c[key];
                if (typeof c.aodTimeout === "number")
                    shell.aodTimeout = Math.max(5, Math.min(600, c.aodTimeout));
                if (typeof c.drift === "boolean")
                    shell.drift = c.drift;
                if (typeof c.powerButtons === "boolean")
                    shell.powerButtons = c.powerButtons;
            } catch (error) {
                shell.message = "Invalid /etc/kairos/greeter.json";
            }
            // The session starts once the settings (with the user name) are read, not before.
            Qt.callLater(shell.startSession);
        }
        onLoadFailed: {
            if (!shell.preview)
                shell.message = "Missing /etc/kairos/greeter.json";
        }
    }

    Connections {
        function onAuthMessage(message: string, error: bool, responseRequired: bool, echoResponse: bool): void {
            console.info(`kairos-greeter: auth message "${message}" (error ${error}, needs answer ${responseRequired})`);
            if (responseRequired) {
                shell.waitingForPrompt = false;
                if (shell.submitPending) {
                    shell.submitPending = false;
                    shell.busy = false;
                    shell.submit();
                }
            } else if (message) {
                // PAM notes (an expired password, a locked account, ...) are worth seeing.
                shell.message = message;
            }
        }

        function onAuthFailure(message: string): void {
            console.warn(`kairos-greeter: auth failure "${message}"`);
            shell.fail(message && !/authentication failure/i.test(message) ? message : "Wrong password");
        }

        function onError(error: string): void {
            console.warn(`kairos-greeter: greetd error "${error}"`);
            shell.fail(error);
        }

        function onReadyToLaunch(): void {
            console.info("kairos-greeter: signed in, launching " + shell.command.join(" "));
            shell.leaving = true;
        }

        target: Greetd
    }

    Timer {
        id: idle

        interval: shell.aodTimeout * 1000
        running: shell.awake && !shell.buffer && !shell.busy
        onTriggered: shell.awake = false
    }

    // Never hang on "Signing in…": if greetd doesn't answer, start over with a message.
    Timer {
        interval: 12000
        running: shell.busy && !shell.leaving && !shell.preview
        onTriggered: {
            console.warn(`kairos-greeter: no answer from greetd (state ${Greetd.state}, waiting for prompt ${shell.waitingForPrompt})`);
            shell.fail(shell.waitingForPrompt ? "The login service didn't ask for a password — try again" : "No answer from the login service — try again");
        }
    }

    // Same if the session doesn't start after the exit animation.
    Timer {
        interval: 15000
        running: shell.leaving && !shell.preview
        onTriggered: {
            console.warn(`kairos-greeter: launch didn't happen (state ${Greetd.state})`);
            shell.leaving = false;
            shell.fail("Couldn't start the desktop: " + shell.command.join(" "));
        }
    }

    Timer {
        id: previewDone

        interval: 600
        onTriggered: shell.leaving = true
    }

    // Runs once the exit animation has finished (see leaveAnim below).
    function launch(): void {
        if (preview)
            Qt.quit();
        else
            // Hyprland's startup output goes to the journal (journalctl -t hyprland) instead
            // of flashing on the screen between the greeter and the desktop.
            Greetd.launch(["systemd-cat", "-t", "hyprland", "--"].concat(command), ["KAIROS_FROM_GREETER=1"], true);
    }

    // Inside cage (KAIROS_GREETER_KIOSK=1) there is no layer shell: use one plain window,
    // which cage shows full-screen. Elsewhere (preview) use layer-shell panels per screen.
    readonly property bool kiosk: Quickshell.env("KAIROS_GREETER_KIOSK") === "1"

    LazyLoader {
        active: !shell.kiosk

        Variants {
            model: Quickshell.screens

            PanelWindow {
                id: panel

                required property ShellScreen modelData
                readonly property bool main: modelData === Quickshell.screens[0]

                screen: modelData
                color: "black"
                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "kairos-greeter"
                WlrLayershell.keyboardFocus: main ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

                Stage {
                    anchors.fill: parent
                    focus: true
                    greeter: shell
                    main: panel.main
                }
            }
        }
    }

    LazyLoader {
        active: shell.kiosk

        FloatingWindow {
            color: "black"

            Stage {
                anchors.fill: parent
                focus: true
                greeter: shell
            }
        }
    }
}
