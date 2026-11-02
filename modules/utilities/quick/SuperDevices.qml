pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Bluetooth
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services
import qs.utils

// "Super devices", the way Huawei / HyperOS do it: this PC as a glowing disc in the middle, the
// devices it can work with floating around it. Drag a device onto the PC to connect it, drag it
// away to disconnect.
//   - Bluetooth devices that are paired (earbuds, speakers, controllers, ...): (dis)connect.
//   - Tablets from KDE Connect: become a drawing tablet / second screen (Weylus); the tablet's
//     browser opens the page by itself.
//   - Phones from KDE Connect: their screen in a window (scrcpy); tapping one shows Find,
//     clipboard and file sending.
// Loose devices drift slowly around the PC; connected ones sit right next to it, linked to it.
// Coming into reach, snapping in and letting go each give a short pulse (services/Haptics.qml).
// Only animates and looks up phones while the panel is open (`active`).
StyledClippingRect {
    id: root

    property bool active
    property string selected
    // Optimistic state while a connection is being made: key -> wanted (bool).
    property var pending: ({})
    // A device is being dragged within reach of the PC.
    property bool zoneHot
    // Drives the drifting (0 -> 2π, over and over, only while on screen).
    property real phase

    readonly property real cx: ring.width / 2
    readonly property real cy: ring.height / 2
    readonly property real reach: 64 // drop zone round the PC
    readonly property var btDevices: Bluetooth.devices.values.filter(d => d.paired || d.connected) // qmllint disable unresolved-type
    // Plain string keys keep each bubble (and its animation) when the devices' details change.
    readonly property var keys: PhoneLink.devices.map(d => "kde:" + d.id).concat(btDevices.map(d => "bt:" + d.address)).slice(0, 8)
    readonly property var linkedKeys: keys.filter(k => isLinked(k))
    readonly property var freeKeys: keys.filter(k => !isLinked(k))

    function phoneFor(key: string): var {
        return key.startsWith("kde:") ? (PhoneLink.devices.find(d => "kde:" + d.id === key) ?? null) : null;
    }

    function btFor(key: string): var {
        return key.startsWith("bt:") ? (btDevices.find(d => d.address === key.slice(3)) ?? null) : null;
    }

    function realLinked(key: string): bool {
        const bt = btFor(key);
        if (bt)
            return bt.connected;
        const p = phoneFor(key);
        if (!p)
            return false;
        return PhoneLink.extendedTo === p.id || PhoneLink.mirroring === p.id;
    }

    function isLinked(key: string): bool {
        const want = pending[key];
        return want === undefined ? realLinked(key) : want;
    }

    function setPending(key: string, want: var): void {
        const next = Object.assign({}, pending);
        if (want === undefined)
            delete next[key];
        else
            next[key] = want;
        pending = next;
    }

    function settle(): void {
        for (const k of Object.keys(pending))
            if (realLinked(k) === pending[k] || !keys.includes(k))
                setPending(k, undefined);
    }

    function infoFor(key: string): var {
        const p = phoneFor(key);
        if (p)
            return {
                name: p.name,
                icon: PhoneLink.iconFor(p.type),
                reachable: p.reachable,
                busy: false,
                battery: p.charge >= 0 ? p.charge / 100 : -1,
                tablet: p.type === "tablet"
            };
        const d = btFor(key);
        if (!d)
            return null;
        return {
            name: d.name,
            icon: Icons.getBluetoothIcon(d.icon),
            reachable: true,
            busy: d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting, // qmllint disable unresolved-type
            battery: d.batteryAvailable ? d.battery : -1,
            tablet: false
        };
    }

    // Where a device rests: connected ones close round the PC, the others on the outer orbit.
    function spotFor(key: string): point {
        const inner = linkedKeys.indexOf(key);
        if (inner >= 0) {
            const n = linkedKeys.length;
            const a = (n === 1 ? -40 : -90 + 360 * inner / n) * Math.PI / 180;
            return Qt.point(cx + Math.cos(a) * 70, cy + Math.sin(a) * 62);
        }
        const i = freeKeys.indexOf(key);
        const n = Math.max(1, freeKeys.length);
        const a = (n === 1 ? 180 : n === 2 ? 160 + 220 * i : 200 + 360 * i / n) * Math.PI / 180;
        const rx = Math.min(ring.width / 2 - 52, 158);
        return Qt.point(cx + Math.cos(a) * rx, cy + Math.sin(a) * (ring.height / 2 - 52));
    }

    function connect(key: string): void {
        const bt = btFor(key);
        const p = phoneFor(key);
        if (bt) {
            setPending(key, true);
            bt.connected = true;
        } else if (p && p.reachable) {
            const info = infoFor(key);
            if (info.tablet && PhoneLink.hasWeylus) {
                setPending(key, true);
                PhoneLink.extend(p.id);
            } else if (!info.tablet && PhoneLink.hasScrcpy) {
                setPending(key, true);
                PhoneLink.mirror(p.id, p.name);
            } else {
                selected = key;
                Toaster.toast(p.name, info.tablet ? Tr.tr("Install Weylus to use the tablet as a drawing tablet") : Tr.tr("Install scrcpy to show the phone's screen here"), "info");
                return;
            }
        } else {
            return;
        }
        Haptics.snap();
        pendingTimer.restart();
    }

    function disconnect(key: string): void {
        const bt = btFor(key);
        const p = phoneFor(key);
        if (bt) {
            setPending(key, false);
            bt.connected = false;
        } else if (p) {
            if (PhoneLink.extendedTo === p.id)
                PhoneLink.stopExtend();
            if (PhoneLink.mirroring === p.id)
                PhoneLink.stopMirror();
        }
        Haptics.release();
        pendingTimer.restart();
    }

    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2
    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer

    onActiveChanged: active ? PhoneLink.addUser() : PhoneLink.removeUser()
    onKeysChanged: settle()
    Component.onCompleted: {
        if (active)
            PhoneLink.addUser();
    }
    Component.onDestruction: {
        if (active)
            PhoneLink.removeUser();
    }

    NumberAnimation on phase {
        running: root.active && root.visible
        from: 0
        to: Math.PI * 2
        duration: 9000
        loops: Animation.Infinite
    }

    Connections {
        function onExtendedToChanged(): void {
            root.settle();
        }

        function onMirroringChanged(): void {
            root.settle();
        }

        target: PhoneLink
    }

    Timer {
        id: pendingTimer

        interval: 9000
        onTriggered: root.pending = {}
    }

    // Bluetooth state changes don't change the keys; check now and then while something waits.
    Timer {
        running: Object.keys(root.pending).length > 0
        repeat: true
        interval: 500
        onTriggered: root.settle()
    }

    // Soft glow behind everything, centred on the PC (HyperOS style), in the wallpaper's colours.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: ring.x + root.cx
                centerY: ring.y + root.cy
                centerRadius: Math.max(root.width, root.height) * 0.75
                focalX: centerX
                focalY: centerY

                GradientStop {
                    position: 0
                    color: Qt.alpha(Colours.palette.m3primary, root.zoneHot ? 0.3 : 0.2)
                }
                GradientStop {
                    position: 0.45
                    color: Qt.alpha(Colours.palette.m3tertiary, 0.08)
                }
                GradientStop {
                    position: 1
                    color: "transparent"
                }
            }

            startX: 0
            startY: 0

            PathLine {
                x: root.width
                y: 0
            }
            PathLine {
                x: root.width
                y: root.height
            }
            PathLine {
                x: 0
                y: root.height
            }
            PathLine {
                x: 0
                y: 0
            }
        }
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.extraSmall

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: Tr.tr("Super devices")
                font: Tokens.font.title.small
                color: Colours.palette.m3onSurface
            }

            StyledRect {
                visible: root.linkedKeys.length > 0
                implicitWidth: countText.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: countText.implicitHeight + Tokens.padding.extraSmall * 2
                radius: Tokens.rounding.full
                color: Colours.palette.m3primaryContainer

                StyledText {
                    id: countText

                    anchors.centerIn: parent
                    text: Tr.trN("%n connected", "%n connected", root.linkedKeys.length)
                    font: Tokens.font.label.medium
                    color: Colours.palette.m3onPrimaryContainer
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: {
                if (root.keys.length === 0)
                    return PhoneLink.available ? Tr.tr("Pair a Bluetooth device or your phone in KDE Connect to see it here.") : Tr.tr("Pair a Bluetooth device to see it here. Install KDE Connect to add your phone and tablet.");
                return Tr.tr("Drag a device onto your PC to connect, away to disconnect.");
            }
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
        }

        Item {
            id: ring

            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            implicitHeight: 236

            // Lighter discs round the PC; the inner one is the drop zone.
            StyledRect {
                x: root.cx - width / 2
                y: root.cy - height / 2
                width: root.reach * 3.4
                height: width
                radius: width / 2
                color: Qt.alpha(Colours.palette.m3onSurface, 0.025)
            }

            StyledRect {
                x: root.cx - width / 2
                y: root.cy - height / 2
                width: root.reach * 2
                height: width
                radius: width / 2
                color: Qt.alpha(root.zoneHot ? Colours.palette.m3primary : Colours.palette.m3onSurface, root.zoneHot ? 0.16 : 0.045)
                border.width: root.zoneHot ? 2 : 0
                border.color: Qt.alpha(Colours.palette.m3primary, 0.7)
                scale: root.zoneHot ? 1.08 : 1

                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                Behavior on color {
                    CAnim {}
                }
            }

            // Links from this PC to connected devices (under the bubbles).
            Repeater {
                model: ScriptModel {
                    values: root.keys
                }

                Link {}
            }

            // This PC
            Item {
                x: root.cx - width / 2
                y: root.cy - height / 2
                width: 72
                height: 72
                scale: root.zoneHot ? 1.1 : 1

                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                Elevation {
                    anchors.fill: parent
                    radius: width / 2
                    level: 3
                }

                StyledClippingRect {
                    anchors.fill: parent
                    radius: width / 2
                    color: Colours.palette.m3primary

                    // A soft highlight on top, like a lit sphere.
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop {
                                position: 0
                                color: Qt.rgba(1, 1, 1, 0.28)
                            }
                            GradientStop {
                                position: 0.55
                                color: Qt.rgba(1, 1, 1, 0)
                            }
                        }
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "computer"
                        fill: 1
                        color: Colours.palette.m3onPrimary
                        fontStyle: Tokens.font.icon.large
                    }
                }
            }

            Repeater {
                model: ScriptModel {
                    values: root.keys
                }

                Bubble {}
            }
        }

        // Actions for the chosen phone or tablet
        RowLayout {
            id: actions

            readonly property var phone: root.phoneFor(root.selected)

            Layout.fillWidth: true
            Layout.preferredHeight: phone ? implicitHeight : 0
            visible: Layout.preferredHeight > 0.5
            opacity: phone ? 1 : 0
            clip: true
            spacing: Tokens.spacing.small

            Behavior on Layout.preferredHeight {
                Anim {
                    type: Anim.DefaultSpatial
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            IconTextButton {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                type: IconTextButton.Tonal
                icon: "ring_volume"
                text: Tr.tr("Find")
                disabled: !(actions.phone?.reachable ?? false)
                onClicked: PhoneLink.ring(actions.phone.id)
            }

            IconTextButton {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                type: IconTextButton.Tonal
                icon: "content_paste_go"
                text: Tr.tr("Paste")
                disabled: !(actions.phone?.reachable ?? false)
                onClicked: PhoneLink.sendClipboard(actions.phone.id)
            }

            IconTextButton {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                type: IconTextButton.Tonal
                icon: "upload_file"
                text: Tr.tr("File")
                disabled: !(actions.phone?.reachable ?? false)
                onClicked: PhoneLink.requestShare(actions.phone.id)
            }
        }
    }

    component Link: StyledRect {
        id: link

        required property string modelData
        readonly property bool on: root.isLinked(modelData)
        readonly property point to: root.spotFor(modelData)
        readonly property real dx: to.x - root.cx
        readonly property real dy: to.y - root.cy

        x: root.cx
        y: root.cy - height / 2
        width: Math.sqrt(dx * dx + dy * dy)
        height: 2
        radius: 1
        transformOrigin: Item.Left
        rotation: Math.atan2(dy, dx) * 180 / Math.PI
        color: Colours.palette.m3primary
        opacity: on ? 0.5 : 0

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    component Bubble: Item {
        id: bubble

        required property string modelData
        required property int index
        readonly property var info: root.infoFor(modelData)
        readonly property bool linked: root.isLinked(modelData)
        readonly property point rest: root.spotFor(modelData)
        readonly property bool chosen: root.selected === modelData
        readonly property bool dragging: drag.active
        // Centre of the bubble's circle while it is dragged.
        readonly property point held: Qt.point(rest.x + drag.translation.x, rest.y + drag.translation.y)
        readonly property bool inReach: dragging && Math.hypot(held.x - root.cx, held.y - root.cy) < root.reach
        // Drifting: each bubble on its own slow loop round its spot (less when connected).
        readonly property real seed: index * 1.9 + 0.7
        readonly property real drift: dragging ? 0 : linked ? 1.5 : 5
        readonly property real driftX: Math.sin(root.phase + seed) * drift
        readonly property real driftY: Math.cos(root.phase * 2 + seed) * drift * 0.8
        property real reveal

        x: (dragging ? held.x : root.cx + (settleAnchor.at.x - root.cx) * reveal + driftX) - width / 2
        y: (dragging ? held.y : root.cy + (settleAnchor.at.y - root.cy) * reveal + driftY) - dot.height / 2 - dot.y
        z: dragging ? 10 : 1
        width: 92
        height: 88
        opacity: (info?.reachable ?? false) ? reveal : reveal * 0.45
        scale: dragging ? 1.12 : (0.6 + 0.4 * reveal)

        onInReachChanged: {
            root.zoneHot = inReach && !linked;
            if (inReach && !linked)
                Haptics.tick();
        }

        Component.onCompleted: revealAnim.start()

        Behavior on scale {
            Anim {
                type: Anim.FastSpatial
            }
        }

        Connections {
            function onActiveChanged(): void {
                if (root.active) {
                    bubble.reveal = 0;
                    revealAnim.restart();
                }
            }

            target: root
        }

        SequentialAnimation {
            id: revealAnim

            PauseAnimation {
                duration: 60 + bubble.index * 40
            }

            Anim {
                target: bubble
                property: "reveal"
                from: 0
                to: 1
                type: Anim.DefaultSpatial
            }
        }

        // Where the bubble is heading: glides between the outer orbit and the PC, and back from
        // wherever it was let go (the drift on top is not animated).
        Item {
            id: settleAnchor

            property point at: bubble.rest
            property bool instant

            function from(p: point): void {
                instant = true;
                at = p;
                instant = false;
                at = Qt.binding(() => bubble.rest);
            }

            Behavior on at {
                enabled: !settleAnchor.instant

                PropertyAnimation {
                    duration: Tokens.anim.durations.expressiveDefaultSpatial
                    easing: Tokens.anim.expressiveDefaultSpatial
                }
            }
        }

        DragHandler {
            id: drag

            target: null
            enabled: bubble.info?.reachable ?? false
            onActiveChanged: {
                if (active)
                    return;
                const near = Math.hypot(bubble.held.x - root.cx, bubble.held.y - root.cy) < root.reach;
                root.zoneHot = false;
                settleAnchor.from(bubble.held);
                if (near && !bubble.linked)
                    root.connect(bubble.modelData);
                else if (!near && bubble.linked && Math.hypot(drag.translation.x, drag.translation.y) > 30)
                    root.disconnect(bubble.modelData);
            }
        }

        // Battery ring
        CircularProgress {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            width: 58
            height: 58
            visible: (bubble.info?.battery ?? -1) >= 0
            value: Math.max(0, bubble.info?.battery ?? 0)
            hasEndIndicator: false
            strokeWidth: 3
            fgColour: (bubble.info?.battery ?? 1) < 0.2 ? Colours.palette.m3error : Colours.palette.m3primary
            bgColour: Qt.alpha(Colours.palette.m3onSurface, 0.08)
        }

        Elevation {
            anchors.fill: dot
            radius: dot.radius
            level: bubble.dragging ? 3 : 1
        }

        StyledRect {
            id: dot

            anchors.horizontalCenter: parent.horizontalCenter
            y: 5
            width: 48
            height: 48
            radius: Tokens.rounding.full
            color: bubble.inReach ? Colours.palette.m3primary : bubble.chosen ? Colours.palette.m3tertiaryContainer : bubble.linked ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHighest

            StateLayer {
                radius: dot.radius
                onClicked: {
                    if (bubble.modelData.startsWith("bt:")) {
                        bubble.linked ? root.disconnect(bubble.modelData) : root.connect(bubble.modelData);
                    } else {
                        root.selected = root.selected === bubble.modelData ? "" : bubble.modelData;
                    }
                }
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: bubble.info?.icon ?? "devices"
                fill: bubble.linked || bubble.inReach ? 1 : 0
                color: bubble.inReach ? Colours.palette.m3onPrimary : bubble.linked ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.medium

                // Pulses while (dis)connecting.
                SequentialAnimation on opacity {
                    running: (bubble.info?.busy ?? false) || root.pending[bubble.modelData] !== undefined
                    loops: Animation.Infinite
                    alwaysRunToEnd: true

                    Anim {
                        to: 0.35
                        type: Anim.SlowEffects
                    }
                    Anim {
                        to: 1
                        type: Anim.SlowEffects
                    }
                }
            }
        }

        StyledText {
            anchors.top: dot.bottom
            anchors.topMargin: 6
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            lineHeight: 0.9
            visible: !bubble.dragging
            text: bubble.info?.name ?? ""
            font: Tokens.font.label.small
            color: bubble.linked ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
        }
    }
}
