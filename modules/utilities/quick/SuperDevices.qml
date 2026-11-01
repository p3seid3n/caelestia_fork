pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils

// "Super devices", the way Huawei / HyperOS do it: this PC in the middle, the devices it can work
// with orbiting it. Drag a device onto the PC to connect it, drag it away to disconnect.
//   - Bluetooth devices that are paired (earbuds, speakers, controllers, ...): (dis)connect.
//   - Tablets from KDE Connect: become a drawing tablet / second screen (Weylus); the tablet's
//     browser opens the page by itself.
//   - Phones from KDE Connect: their screen in a window (scrcpy); tapping one shows Find,
//     clipboard and file sending.
// Connected devices sit close round the PC, linked to it. Coming into reach, snapping in and
// letting go each give a short pulse (services/Haptics.qml) - felt through a subwoofer.
// Phones are only looked up while the panel is open (`active`).
StyledRect {
    id: root

    property bool active
    property string selected
    // Optimistic state while a connection is being made: key -> wanted (bool).
    property var pending: ({})

    readonly property real cx: ring.width / 2
    readonly property real cy: ring.height / 2
    readonly property real reach: 62 // drop zone round the PC
    readonly property var btDevices: Bluetooth.devices.values.filter(d => d.paired || d.connected) // qmllint disable unresolved-type
    // Plain string keys keep each bubble (and its animation) when the devices' details change.
    readonly property var keys: PhoneLink.devices.map(d => "kde:" + d.id).concat(btDevices.map(d => "bt:" + d.address)).slice(0, 8)
    readonly property var linkedKeys: keys.filter(k => isLinked(k))
    readonly property var freeKeys: keys.filter(k => !isLinked(k))
    // A device is being dragged within reach of the PC.
    property bool zoneHot

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
            const a = (n === 1 ? -35 : -90 + 360 * inner / n) * Math.PI / 180;
            return Qt.point(cx + Math.cos(a) * 64, cy + Math.sin(a) * 58);
        }
        const i = freeKeys.indexOf(key);
        const n = Math.max(1, freeKeys.length);
        const a = (n === 1 ? 180 : n === 2 ? 180 + 180 * i : 200 + 360 * i / n) * Math.PI / 180;
        const rx = Math.min(ring.width / 2 - 38, 150);
        return Qt.point(cx + Math.cos(a) * rx, cy + Math.sin(a) * (ring.height / 2 - 34));
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
    Component.onCompleted: {
        if (active)
            PhoneLink.addUser();
    }
    Component.onDestruction: {
        if (active)
            PhoneLink.removeUser();
    }

    // Pending states settle once the real state agrees, or give up after a while.
    onKeysChanged: settle()

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

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                text: Tr.tr("Super devices")
                font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                color: Colours.palette.m3onSurface
            }

            StyledText {
                text: root.linkedKeys.length > 0 ? Tr.trN("%n connected", "%n connected", root.linkedKeys.length) : root.keys.length > 0 ? Tr.tr("Drag onto your PC to connect") : ""
                font: Tokens.font.body.small
                color: root.linkedKeys.length > 0 ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            }
        }

        Item {
            id: ring

            Layout.fillWidth: true
            implicitHeight: 200

            // Orbits
            StyledRect {
                x: root.cx - width / 2
                y: root.cy - height / 2
                width: root.reach * 2 + 8
                height: width
                radius: width / 2
                color: Qt.alpha(Colours.palette.m3primary, root.zoneHot ? 0.14 : 0)
                border.width: 1
                border.color: Qt.alpha(root.zoneHot ? Colours.palette.m3primary : Colours.palette.m3outlineVariant, root.zoneHot ? 0.9 : 0.6)
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

            StyledRect {
                x: root.cx - width / 2
                y: root.cy - height / 2
                width: Math.min(ring.width - 24, 300)
                height: ring.height - 52
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.35)
            }

            // Links from this PC to connected devices (under the bubbles).
            Repeater {
                model: ScriptModel {
                    values: root.keys
                }

                Link {}
            }

            // This PC
            StyledRect {
                id: pc

                x: root.cx - width / 2
                y: root.cy - height / 2
                implicitWidth: 60
                implicitHeight: 60
                radius: root.zoneHot ? Tokens.rounding.large : Tokens.rounding.full
                color: root.zoneHot ? Colours.palette.m3primary : Colours.palette.m3primaryContainer
                scale: root.zoneHot ? 1.1 : 1

                Behavior on radius {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "computer"
                    fill: 1
                    color: root.zoneHot ? Colours.palette.m3onPrimary : Colours.palette.m3onPrimaryContainer
                    fontStyle: Tokens.font.icon.large
                }
            }

            Repeater {
                model: ScriptModel {
                    values: root.keys
                }

                Bubble {}
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                width: parent.width - Tokens.padding.large * 2
                visible: root.keys.length === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: PhoneLink.available ? Tr.tr("Pair a Bluetooth device or your phone in KDE Connect to see it here") : Tr.tr("Pair a Bluetooth device to see it here. Install KDE Connect to add your phone.")
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
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
                type: IconTextButton.Tonal
                icon: "ring_volume"
                text: Tr.tr("Find")
                disabled: !(actions.phone?.reachable ?? false)
                onClicked: PhoneLink.ring(actions.phone.id)
            }

            IconTextButton {
                Layout.fillWidth: true
                type: IconTextButton.Tonal
                icon: "content_paste_go"
                text: Tr.tr("Clipboard")
                disabled: !(actions.phone?.reachable ?? false)
                onClicked: PhoneLink.sendClipboard(actions.phone.id)
            }

            IconTextButton {
                Layout.fillWidth: true
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
        opacity: on ? 0.55 : 0

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on width {
            Anim {
                type: Anim.DefaultSpatial
            }
        }

        Behavior on rotation {
            Anim {
                type: Anim.DefaultSpatial
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
        property real reveal

        x: (dragging ? held.x : root.cx + (rest.x - root.cx) * reveal) - width / 2
        y: (dragging ? held.y : root.cy + (rest.y - root.cy) * reveal) - dot.height / 2 - dot.y
        z: dragging ? 10 : 1
        width: 76
        height: 70
        opacity: (info?.reachable ?? false) ? reveal : reveal * 0.45
        scale: dragging ? 1.12 : (0.6 + 0.4 * reveal)

        onInReachChanged: {
            root.zoneHot = inReach && !linked;
            if (inReach && !linked)
                Haptics.tick();
        }

        Component.onCompleted: revealAnim.start()

        Behavior on x {
            enabled: !bubble.dragging && bubble.reveal >= 1

            Anim {
                type: Anim.DefaultSpatial
            }
        }

        Behavior on y {
            enabled: !bubble.dragging && bubble.reveal >= 1

            Anim {
                type: Anim.DefaultSpatial
            }
        }

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

        DragHandler {
            id: drag

            target: null
            enabled: bubble.info?.reachable ?? false
            onActiveChanged: {
                if (active)
                    return;
                const near = Math.hypot(bubble.held.x - root.cx, bubble.held.y - root.cy) < root.reach;
                root.zoneHot = false;
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
            width: 50
            height: 50
            visible: (bubble.info?.battery ?? -1) >= 0
            value: Math.max(0, bubble.info?.battery ?? 0)
            hasEndIndicator: false
            strokeWidth: 3
            fgColour: (bubble.info?.battery ?? 1) < 0.2 ? Colours.palette.m3error : Colours.palette.m3primary
            bgColour: Qt.alpha(Colours.palette.m3onSurface, 0.08)
        }

        StyledRect {
            id: dot

            anchors.horizontalCenter: parent.horizontalCenter
            y: 5
            width: 40
            height: 40
            radius: bubble.linked ? Tokens.rounding.medium : Tokens.rounding.full
            color: bubble.inReach ? Colours.palette.m3primary : bubble.chosen ? Colours.palette.m3tertiaryContainer : bubble.linked ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainerHighest

            Behavior on radius {
                Anim {
                    type: Anim.FastSpatial
                }
            }

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
            anchors.topMargin: 5
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            visible: !bubble.dragging
            text: bubble.info?.name ?? ""
            font: Tokens.font.label.small
            color: bubble.linked ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
        }
    }
}
