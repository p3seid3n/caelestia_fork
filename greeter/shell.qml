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
    property list<string> command: ["Hyprland"]
    property color hourColour: "#c4c0ff"
    property color minuteColour: "#c6c4dd"
    property color accentColour: "#c4c0ff"
    property color surfaceColour: "#201f23"
    property color onSurfaceColour: "#e5e1e7"
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
                for (const key of ["hourColour", "minuteColour", "accentColour", "surfaceColour", "onSurfaceColour", "errorColour"])
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

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property ShellScreen modelData
            readonly property bool main: modelData === Quickshell.screens[0]
            property real prog: shell.awake ? 1 : 0

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

            Behavior on prog {
                M3Anim {
                    duration: 600
                }
            }

            Connections {
                function onFailed(): void {
                    shake.restart();
                }

                function onLeavingChanged(): void {
                    if (shell.leaving)
                        leaveAnim.start();
                }

                target: shell
            }

            // Success: same motion as the lock screen's unlock, ending on pure black.
            SequentialAnimation {
                id: leaveAnim

                ParallelAnimation {
                    M3Anim {
                        target: stage
                        property: "scale"
                        to: 1.12
                        duration: 600
                    }
                    M3Anim {
                        target: stage
                        property: "opacity"
                        to: 0
                        duration: 400
                    }
                }
                PauseAnimation {
                    duration: 100
                }
                ScriptAction {
                    script: {
                        if (win.main)
                            shell.launch();
                    }
                }
            }

            Item {
                anchors.fill: parent
                focus: win.main

                Keys.onPressed: event => {
                    if (shell.leaving)
                        return;
                    event.accepted = true;

                    if (event.key === Qt.Key_Escape) {
                        shell.buffer = "";
                        shell.awake = false;
                        return;
                    }

                    shell.wake();

                    if (shell.busy)
                        return;

                    if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                        shell.submit();
                    } else if (event.key === Qt.Key_Backspace) {
                        shell.buffer = event.modifiers & Qt.ControlModifier ? "" : shell.buffer.slice(0, -1);
                    } else if (/^[^\x00-\x1F\x7F-\x9F]+$/.test(event.text)) {
                        shell.buffer += event.text;
                        shell.message = "";
                    }
                }
            }

            MouseArea {
                property point last

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: shell.awake ? Qt.ArrowCursor : Qt.BlankCursor
                onPositionChanged: mouse => {
                    const moved = Math.abs(mouse.x - last.x) + Math.abs(mouse.y - last.y) > 12;
                    last = Qt.point(mouse.x, mouse.y);
                    if (moved && !arm.running)
                        shell.wake();
                }
                onPressed: shell.wake()
            }

            Timer {
                id: arm

                interval: 800
                running: true
            }

            Item {
                id: stage

                anchors.fill: parent
                visible: win.main
                opacity: 0
                scale: 0.94

                Component.onCompleted: {
                    opacity = 1;
                    scale = 1;
                }

                Behavior on opacity {
                    M3Anim {
                        duration: 700
                    }
                }

                Behavior on scale {
                    M3Anim {
                        duration: 900
                    }
                }

                // Clock (same proportions as the lock screen)
                Column {
                    id: clock

                    readonly property real pointSize: Math.max(24, win.height * 0.17)

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: (win.height - height) / 2 * (1 - win.prog) + win.height * 0.1 * win.prog
                    transformOrigin: Item.Top
                    scale: 1 - 0.4 * win.prog
                    spacing: pointSize * 0.12

                    SystemClock {
                        id: time

                        precision: SystemClock.Minutes
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: clock.pointSize * 0.04

                        Repeater {
                            model: 2

                            Digit {
                                required property int index

                                digit: Qt.formatTime(time.date, "hh").charAt(index)
                                colour: shell.hourColour
                                pointSize: clock.pointSize
                                boldness: win.prog
                            }
                        }
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: clock.pointSize * 0.04

                        Repeater {
                            model: 2

                            Digit {
                                required property int index

                                digit: Qt.formatTime(time.date, "mm").charAt(index)
                                colour: shell.minuteColour
                                pointSize: clock.pointSize
                                boldness: win.prog
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        topPadding: clock.pointSize * 0.1
                        text: Qt.formatDate(time.date, "dddd, d MMMM")
                        color: shell.accentColour
                        font.family: "Google Sans Flex"
                        font.pointSize: Math.round(clock.pointSize * 0.13)
                        font.weight: Font.Medium
                        opacity: 0.6 + 0.4 * win.prog
                    }
                }

                // Password bar
                Rectangle {
                    id: bar

                    anchors.horizontalCenter: parent.horizontalCenter
                    y: win.height * 0.66 + (1 - win.prog) * 40
                    width: Math.min(win.height * 0.42, 460)
                    height: 56
                    radius: height / 2
                    color: shell.surfaceColour
                    border.width: 1
                    border.color: Qt.alpha(shell.accentColour, shell.buffer ? 0.6 : 0.15)
                    opacity: win.prog
                    scale: 0.92 + 0.08 * win.prog
                    visible: opacity > 0
                    transform: Translate {
                        id: shakeOffset
                    }

                    Behavior on border.color {
                        ColorAnimation {
                            duration: 200
                        }
                    }

                    Text {
                        id: statusIcon

                        anchors.left: parent.left
                        anchors.leftMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        text: shell.busy ? "progress_activity" : "lock"
                        color: shell.accentColour
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 24

                        RotationAnimation on rotation {
                            running: shell.busy
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 900
                            onStopped: statusIcon.rotation = 0
                        }
                    }

                    // Placeholder
                    Text {
                        anchors.centerIn: parent
                        text: shell.busy ? "Signing in…" : shell.preview ? "Preview — any password" : "Enter your password"
                        color: Qt.alpha(shell.onSurfaceColour, 0.5)
                        font.family: "Google Sans Flex"
                        font.pointSize: 12
                        opacity: shell.buffer ? 0 : 1

                        Behavior on opacity {
                            M3Anim {
                                duration: 200
                            }
                        }
                    }

                    // Dots / revealed text
                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        visible: !shell.showPassword

                        Repeater {
                            model: shell.buffer.length

                            Rectangle {
                                width: 10
                                height: 10
                                radius: 5
                                color: shell.onSurfaceColour
                                scale: 0

                                Component.onCompleted: scale = 1

                                Behavior on scale {
                                    M3Anim {
                                        duration: 300
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 120
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideLeft
                        visible: shell.showPassword
                        text: shell.buffer
                        color: shell.onSurfaceColour
                        font.family: "Google Sans Flex"
                        font.pointSize: 13
                    }

                    // Show / hide password
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: shell.showPassword ? "visibility_off" : "visibility"
                        color: shell.onSurfaceColour
                        opacity: shell.buffer ? 0.8 : 0.3
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 22

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            cursorShape: Qt.PointingHandCursor
                            onClicked: shell.showPassword = !shell.showPassword
                        }
                    }
                }

                Text {
                    anchors.top: bar.bottom
                    anchors.topMargin: 18
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: shell.message
                    color: shell.errorColour
                    font.family: "Google Sans Flex"
                    font.pointSize: 11
                    opacity: win.prog
                }
            }

            SequentialAnimation {
                id: shake

                NumberAnimation {
                    target: shakeOffset
                    property: "x"
                    to: -18
                    duration: 60
                }
                NumberAnimation {
                    target: shakeOffset
                    property: "x"
                    to: 14
                    duration: 80
                }
                NumberAnimation {
                    target: shakeOffset
                    property: "x"
                    to: -8
                    duration: 80
                }
                M3Anim {
                    target: shakeOffset
                    property: "x"
                    to: 0
                    duration: 250
                }
            }
        }
    }
}
