import QtQuick

// The greeter's content for one screen (clock, password bar, animations).
// Lives in a layer-shell panel (preview inside Hyprland) or a plain window (cage kiosk).
Item {
    id: win

    required property var greeter
    property bool main: true
    property real prog: win.greeter.awake ? 1 : 0

    // win.greeter.qml drives everything; `greeter` is its root object.

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

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
            if (win.greeter.leaving)
                leaveAnim.start();
        }

        target: win.greeter
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
                color: Qt.alpha(win.greeter.onSurfaceColour, 0.5)
                font.family: "Google Sans Flex"
                font.pointSize: 12
                opacity: win.greeter.buffer ? 0 : 1

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
                visible: !win.greeter.showPassword

                Repeater {
                    model: win.greeter.buffer.length

                    Rectangle {
                        width: 10
                        height: 10
                        radius: 5
                        color: win.greeter.onSurfaceColour
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
                visible: win.greeter.showPassword
                text: win.greeter.buffer
                color: win.greeter.onSurfaceColour
                font.family: "Google Sans Flex"
                font.pointSize: 13
            }

            // Show / hide password
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                text: win.greeter.showPassword ? "visibility_off" : "visibility"
                color: win.greeter.onSurfaceColour
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
