import QtQuick
import Quickshell

// The greeter's content for one screen (clock, password bar, animations).
// Lives in a layer-shell panel (preview inside Hyprland) or a plain window (cage kiosk).
Item {
    id: win

    required property var greeter
    property bool main: true
    property real prog: win.greeter.awake ? 1 : 0
    // Burn-in protection for the always-on clock, as on the lock screen.
    property real driftX
    property real driftY
    // Power button waiting for its second click ("" for none).
    property string armed

    // win.greeter.qml drives everything; `greeter` is its root object.

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    Behavior on prog {
        Motion {
            type: "emphasized"
        }
    }

    Behavior on driftX {
        NumberAnimation {
            duration: 4000
            easing.type: Easing.InOutSine
        }
    }

    Behavior on driftY {
        NumberAnimation {
            duration: 4000
            easing.type: Easing.InOutSine
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: !win.greeter.awake && win.greeter.drift
        onTriggered: {
            win.driftX = Math.round((Math.random() - 0.5) * 24);
            win.driftY = Math.round((Math.random() - 0.5) * 24);
        }
    }

    Timer {
        id: disarm

        interval: 3500
        onTriggered: win.armed = ""
    }

    Connections {
        function onFailed(): void {
            shake.restart();
        }

        function onLeavingChanged(): void {
            if (win.greeter.leaving)
                leaveAnim.start();
        }

        target: win.greeter
    }

    // Success: same motion as the lock screen's unlock, ending on pure black.
    SequentialAnimation {
        id: leaveAnim

        ParallelAnimation {
            Motion {
                target: stage
                property: "scale"
                to: 1.12
                type: "emphasized"
            }
            Motion {
                target: stage
                property: "opacity"
                to: 0
                type: "standard"
            }
        }
        PauseAnimation {
            duration: 100
        }
        ScriptAction {
            script: {
                if (win.main)
                    win.greeter.launch();
            }
        }
    }

    Item {
        anchors.fill: parent
        focus: win.main

        Keys.onPressed: event => {
            if (win.greeter.leaving)
                return;
            event.accepted = true;

            if (event.key === Qt.Key_Escape) {
                win.greeter.buffer = "";
                win.greeter.awake = false;
                return;
            }

            win.greeter.wake();

            if (win.greeter.busy)
                return;

            if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
                win.greeter.submit();
            } else if (event.key === Qt.Key_Backspace) {
                win.greeter.buffer = event.modifiers & Qt.ControlModifier ? "" : win.greeter.buffer.slice(0, -1);
            } else if (/^[^\x00-\x1F\x7F-\x9F]+$/.test(event.text)) {
                win.greeter.buffer += event.text;
                win.greeter.message = "";
            }
        }
    }

    MouseArea {
        property point last

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: win.greeter.awake ? Qt.ArrowCursor : Qt.BlankCursor
        onPositionChanged: mouse => {
            const moved = Math.abs(mouse.x - last.x) + Math.abs(mouse.y - last.y) > 12;
            last = Qt.point(mouse.x, mouse.y);
            if (moved && !arm.running)
                win.greeter.wake();
        }
        onPressed: win.greeter.wake()
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
            Motion {
                type: "standardLarge"
            }
        }

        Behavior on scale {
            Motion {
                type: "emphasized"
            }
        }

        // Clock (same proportions as the lock screen)
        Column {
            id: clock

            readonly property real pointSize: Math.max(24, win.height * 0.17)

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: win.driftX * (1 - win.prog)
            y: ((win.height - height) / 2 + win.driftY) * (1 - win.prog) + win.height * 0.1 * win.prog
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
                        colour: win.greeter.hourColour
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
                        colour: win.greeter.minuteColour
                        pointSize: clock.pointSize
                        boldness: win.prog
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                topPadding: clock.pointSize * 0.1
                text: Qt.formatDate(time.date, "dddd, d MMMM")
                color: win.greeter.accentColour
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
            color: win.greeter.surfaceColour
            border.width: 1
            border.color: Qt.alpha(win.greeter.accentColour, win.greeter.buffer ? 0.6 : 0.15)
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
                text: win.greeter.busy ? "progress_activity" : "lock"
                color: win.greeter.accentColour
                font.family: "Material Symbols Rounded"
                font.pixelSize: 24

                RotationAnimation on rotation {
                    running: win.greeter.busy
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
                text: win.greeter.busy ? "Signing in…" : win.greeter.preview ? "Preview — any password" : "Enter your password"
                color: Qt.alpha(win.greeter.textColour, 0.5)
                font.family: "Google Sans Flex"
                font.pointSize: 12
                opacity: win.greeter.buffer ? 0 : 1

                Behavior on opacity {
                    Motion {
                        type: "defaultEffects"
                    }
                }
            }

            // Typed characters: same shape-morph animation as the lock screen.
            PasswordChars {
                anchors.fill: parent
                anchors.leftMargin: 56
                anchors.rightMargin: 56
                buffer: win.greeter.buffer
                showPassword: win.greeter.showPassword
                colour: win.greeter.textColour
            }

            // Show / hide password
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: win.greeter.showPassword ? "visibility_off" : "visibility"
                color: win.greeter.textColour
                opacity: win.greeter.buffer ? 0.8 : 0.3
                font.family: "Material Symbols Rounded"
                font.pixelSize: 22

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.greeter.showPassword = !win.greeter.showPassword
                }
            }
        }

        Text {
            anchors.top: bar.bottom
            anchors.topMargin: 18
            anchors.horizontalCenter: parent.horizontalCenter
            text: win.greeter.message
            color: win.greeter.errorColour
            font.family: "Google Sans Flex"
            font.pointSize: 11
            opacity: win.prog
        }

        // Sleep, restart, shut down; restart and shut down need a second click.
        Row {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 48
            spacing: 10
            opacity: win.prog
            visible: opacity > 0 && !win.greeter.preview && win.greeter.powerButtons

            Repeater {
                model: [
                    {
                        key: "suspend",
                        icon: "bedtime",
                        label: "Sleep",
                        confirm: false
                    },
                    {
                        key: "reboot",
                        icon: "restart_alt",
                        label: "Restart?",
                        confirm: true
                    },
                    {
                        key: "poweroff",
                        icon: "power_settings_new",
                        label: "Shut down?",
                        confirm: true
                    }
                ]

                Rectangle {
                    id: powerButton

                    required property var modelData
                    readonly property bool isArmed: win.armed === modelData.key

                    width: isArmed ? powerLabel.implicitWidth + 64 : 48
                    height: 48
                    radius: height / 2
                    color: isArmed ? win.greeter.errorColour : Qt.alpha(win.greeter.surfaceColour, 0.9)

                    Behavior on width {
                        Motion {
                            type: "fastSpatial"
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: 200
                        }
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: powerButton.isArmed ? 8 : 0

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: powerButton.modelData.icon
                            color: powerButton.isArmed ? "black" : win.greeter.textColour
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 22
                        }

                        Text {
                            id: powerLabel

                            anchors.verticalCenter: parent.verticalCenter
                            visible: powerButton.isArmed
                            text: powerButton.modelData.label
                            color: "black"
                            font.family: "Google Sans Flex"
                            font.pointSize: 11
                            font.weight: Font.DemiBold
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            win.greeter.wake();
                            if (powerButton.modelData.confirm && !powerButton.isArmed) {
                                win.armed = powerButton.modelData.key;
                                disarm.restart();
                                return;
                            }
                            win.armed = "";
                            Quickshell.execDetached(["systemctl", powerButton.modelData.key]);
                        }
                    }
                }
            }
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
        Motion {
            target: shakeOffset
            property: "x"
            to: 0
            type: "fastSpatial"
        }
    }
}
