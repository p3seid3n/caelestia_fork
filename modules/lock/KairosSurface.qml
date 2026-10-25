pragma ComponentBehavior: Bound

import "kairos"
import "center"
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.images
import qs.services

// KairosOS lock / login screen.
// Black background, big stacked clock (AoD state) with one quiet line for notifications and music,
// drifting a little now and then against burn-in. Any key or mouse movement wakes it: the clock
// thickens and moves up, the blurred wallpaper fades in behind, the password bar appears with the
// latest notifications, what is playing and sleep / restart / shut down along the bottom. Typing
// goes straight into the password, there is nothing to click.
// Settings: Settings → Lock screen (services/LockStyle.qml).
WlSessionLockSurface {
    id: root

    required property WlSessionLock lock
    required property Pam pam

    readonly property alias unlocking: unlockAnim.running
    property bool awake
    // Burn-in protection: where the AoD clock sits right now (pixels off centre).
    property real driftX
    property real driftY
    // 0 = AoD, 1 = awake. Everything below is driven by this one value.
    property real prog: awake ? 1 : 0

    // tryFace: start Howdy right away (pointer wake). Not on key wake: typing would abort it anyway.
    function wake(tryFace: bool): void {
        if (!awake) {
            awake = true;
            if (tryFace && LockStyle.faceOnWake && pam.howdy.canAttempt && !pam.howdy.active)
                pam.howdy.start();
        }
        idle.restart();
    }

    function sleep(): void {
        pam.buffer = "";
        awake = false;
    }

    contentItem.Config.screen: screen.name
    contentItem.Tokens.screen: screen.name

    color: "transparent"

    Behavior on prog {
        Anim {
            type: Anim.EmphasizedLarge
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

    Connections {
        function onUnlock(): void {
            unlockAnim.start();
        }

        target: root.lock
    }

    Connections {
        function onFlashMsg(): void {
            root.wake(false);
            if (root.pam.state === Pam.Failed || root.pam.state === Pam.Error || root.pam.state === Pam.MaxTries)
                shake.restart();
        }

        target: root.pam
    }

    // Back to the AoD clock after a while without input.
    Timer {
        id: idle

        interval: Math.max(5, LockStyle.aodTimeout) * 1000
        running: root.awake && !root.pam.buffer && !root.pam.passwd.active && !root.pam.howdy.active
        onTriggered: root.awake = false
    }

    // AoD: move the clock a few pixels every minute, so no pixel shows the same thing all night.
    Timer {
        interval: 60000
        repeat: true
        running: LockStyle.drift && !root.awake
        onTriggered: {
            root.driftX = Math.round((Math.random() - 0.5) * 24);
            root.driftY = Math.round((Math.random() - 0.5) * 24);
        }
    }

    // Ignore the pointer for a moment after locking, so the lock doesn't wake itself.
    Timer {
        id: armPointer

        interval: 800
        running: true
    }

    ParallelAnimation {
        id: initAnim

        running: true

        Anim {
            target: black
            property: "opacity"
            to: 1
            type: Anim.StandardLarge
        }
        Anim {
            target: stage
            property: "opacity"
            to: 1
            type: Anim.StandardLarge
        }
        Anim {
            target: stage
            property: "scale"
            to: 1
            type: Anim.EmphasizedLarge
        }
    }

    SequentialAnimation {
        id: unlockAnim

        ParallelAnimation {
            Anim {
                target: stage
                property: "scale"
                to: 1.12
                type: Anim.EmphasizedLarge
            }
            Anim {
                target: stage
                property: "opacity"
                to: 0
                type: Anim.Standard
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: Tokens.anim.durations.small
                }
                Anim {
                    target: black
                    property: "opacity"
                    to: 0
                    type: Anim.StandardLarge
                }
            }
        }
        PropertyAction {
            target: root.lock
            property: "locked"
            value: false
        }
    }

    Rectangle {
        id: black

        anchors.fill: parent
        color: "black"
        opacity: 0
    }

    // Awake: the wallpaper, blurred and darkened, fades in; the AoD state stays pure black.
    Item {
        anchors.fill: parent
        visible: LockStyle.wallpaperWhenAwake && opacity > 0
        opacity: black.opacity * root.prog
        scale: 1.06 - 0.06 * root.prog

        layer.enabled: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1
            blurMax: 64
            blurMultiplier: 1
            brightness: -0.25
        }

        CachingImage {
            anchors.fill: parent
            path: Wallpapers.current
        }

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.35
        }
    }

    // Keyboard: wake on the first key and pass it on, so typing starts the password at once.
    Item {
        anchors.fill: parent
        focus: true

        onActiveFocusChanged: {
            if (!activeFocus)
                forceActiveFocus();
        }

        Keys.onPressed: event => {
            if (root.unlocking)
                return;

            if (event.key === Qt.Key_Escape) {
                root.sleep();
                return;
            }

            root.wake(false);

            if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return)
                inputField.placeholder.animate = false;

            root.pam.handleKey(event);
        }
    }

    MouseArea {
        property point last

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.awake ? Qt.ArrowCursor : Qt.BlankCursor

        onPositionChanged: mouse => {
            const moved = Math.abs(mouse.x - last.x) + Math.abs(mouse.y - last.y) > 12;
            last = Qt.point(mouse.x, mouse.y);
            if (moved && !armPointer.running)
                root.wake(true);
        }
        onPressed: {
            if (!armPointer.running)
                root.wake(true);
        }
    }

    Item {
        id: stage

        anchors.fill: parent
        opacity: 0
        scale: 0.94

        KairosClock {
            id: clock

            readonly property real awakeScale: 0.6

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.horizontalCenterOffset: root.driftX * (1 - root.prog)
            // AoD: centred on screen. Awake: shrinks towards the upper part.
            y: ((root.height - height) / 2 + root.driftY) * (1 - root.prog) + root.height * 0.1 * root.prog
            transformOrigin: Item.Top
            scale: 1 - (1 - awakeScale) * root.prog

            pointSize: Math.max(24, root.height * 0.17)
            boldness: root.prog
        }

        // Notifications and music, under the date; moves with the clock.
        Glance {
            anchors.horizontalCenter: clock.horizontalCenter
            anchors.horizontalCenterOffset: clock.anchors.horizontalCenterOffset
            y: clock.y + clock.height * clock.scale + Tokens.spacing.medium
            pointSize: clock.pointSize * clock.scale
            colour: LockStyle.accentColour || Colours.palette.m3onSurfaceVariant
            boldness: root.prog
        }

        // Password bar: not clickable, just shows what is typed.
        StyledRect {
            id: bar

            anchors.horizontalCenter: parent.horizontalCenter
            y: root.height * 0.66 + (1 - root.prog) * Tokens.padding.extraLarge * 2

            implicitWidth: Math.min(root.height * 0.42, 460)
            implicitHeight: row.implicitHeight + Tokens.padding.small * 2

            radius: Tokens.rounding.full
            color: Colours.palette.m3surfaceContainer
            border.width: 1
            border.color: Qt.alpha(LockStyle.accentColour || Colours.palette.m3primary, root.pam.buffer ? 0.6 : 0.15)

            opacity: root.prog
            scale: 0.92 + 0.08 * root.prog
            visible: opacity > 0
            transform: Translate {
                id: shakeOffset
            }

            Behavior on border.color {
                CAnim {}
            }

            RowLayout {
                id: row

                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.medium
                anchors.rightMargin: Tokens.padding.small
                spacing: Tokens.spacing.small

                // Status icon: lock, face (Howdy ready) or spinner while checking.
                Item {
                    implicitWidth: 28
                    implicitHeight: 28

                    AnimLoader {
                        anchors.centerIn: parent
                        sourceComp: root.pam.passwd.active || root.pam.howdy.active ? spinner : statusIcon
                    }

                    Component {
                        id: statusIcon

                        MaterialIcon {
                            animate: true
                            text: root.unlocking ? "check_circle" : root.pam.howdy.canAttempt ? "face" : "lock"
                            color: LockStyle.accentColour || Colours.palette.m3primary
                            fill: 1
                        }
                    }

                    Component {
                        id: spinner

                        LoadingIndicator {
                            implicitSize: 24
                        }
                    }
                }

                InputField {
                    id: inputField

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 40

                    centerScale: 1
                    pam: root.pam
                }

                // Caps lock is on / keyboard layout when there is more than one.
                StyledRect {
                    visible: Hypr.capsLock || (Hypr.keyboard?.layout ?? "").includes(",")
                    implicitWidth: chipText.implicitWidth + Tokens.padding.medium * 2
                    implicitHeight: 26
                    radius: Tokens.rounding.full
                    color: Hypr.capsLock ? Colours.palette.m3errorContainer : Colours.tPalette.m3surfaceContainerHighest

                    StyledText {
                        id: chipText

                        anchors.centerIn: parent
                        text: Hypr.capsLock ? "CAPS" : Hypr.kbLayout.toUpperCase()
                        font: Tokens.font.body.builders.small.weight(Font.DemiBold).build()
                        color: Hypr.capsLock ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSurfaceVariant
                    }
                }

                // Show / hide the typed password.
                IconButton {
                    type: IconButton.Text
                    isRound: true
                    icon: inputField.showPassword ? "visibility_off" : "visibility"
                    disabled: !root.pam.buffer
                    onClicked: inputField.showPassword = !inputField.showPassword
                }
            }
        }

        StateMessage {
            anchors.top: bar.bottom
            anchors.topMargin: Tokens.spacing.large
            anchors.horizontalCenter: parent.horizontalCenter
            width: bar.implicitWidth * 1.4

            pam: root.pam
            opacity: root.prog
        }

        // Along the bottom while awake: notifications, music, power.
        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Tokens.padding.extraLarge * 2
            height: Math.max(notifCards.implicitHeight, media.implicitHeight, power.implicitHeight)
            opacity: root.prog
            visible: opacity > 0
            transform: Translate {
                y: (1 - root.prog) * Tokens.padding.extraLarge * 2
            }

            NotifCards {
                id: notifCards

                anchors.left: parent.left
                anchors.bottom: parent.bottom
                visible: LockStyle.showNotifications
            }

            MediaPill {
                id: media

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                visible: LockStyle.showMedia && Players.active !== null
            }

            PowerButtons {
                id: power

                anchors.right: parent.right
                anchors.bottom: parent.bottom
                visible: LockStyle.powerButtons
            }
        }
    }

    SequentialAnimation {
        id: shake

        Anim {
            target: shakeOffset
            property: "x"
            to: -18
            duration: 60
        }
        Anim {
            target: shakeOffset
            property: "x"
            to: 14
            duration: 80
        }
        Anim {
            target: shakeOffset
            property: "x"
            to: -8
            duration: 80
        }
        Anim {
            target: shakeOffset
            property: "x"
            to: 0
            type: Anim.FastSpatial
        }
    }
}
