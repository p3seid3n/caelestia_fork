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
        if (!preview && user)
            Greetd.createSession(user);
    }

    function fail(text: string): void {
        busy = false;
        buffer = "";
        message = text;
        failed();
        startSession();
    }

    Component.onCompleted: startSession()

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
            } catch (error) {
                shell.message = "Invalid /etc/kairos/greeter.json";
            }
        }
        onLoadFailed: {
            if (!shell.preview)
                shell.message = "Missing /etc/kairos/greeter.json";
        }
    }

    Connections {
        function onAuthMessage(message: string, error: bool, responseRequired: bool, echoResponse: bool): void {
            if (responseRequired) {
                shell.waitingForPrompt = false;
                if (shell.submitPending) {
                    shell.submitPending = false;
                    shell.busy = false;
                    shell.submit();
                }
            } else if (error) {
                shell.message = message;
            }
        }

        function onAuthFailure(message: string): void {
            shell.fail("Wrong password");
        }

        function onError(error: string): void {
            shell.fail(error);
        }

        function onReadyToLaunch(): void {
            shell.leaving = true;
        }

        target: Greetd
    }

    Timer {
        id: idle

        interval: 20000
        running: shell.awake && !shell.buffer && !shell.busy
        onTriggered: shell.awake = false
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
            Greetd.launch(command, ["KAIROS_FROM_GREETER=1"], true);
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
