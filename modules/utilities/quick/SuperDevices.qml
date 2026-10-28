pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils

// "Super devices": this PC in the middle, the devices it works with around it, as on HyperOS.
//   - Bluetooth devices that are paired (earbuds, speakers, controllers, ...): tap to connect or
//     disconnect; the ring around them is their battery.
//   - Phones and tablets from KDE Connect: tap for Find (rings it), sending the clipboard or a
//     file; the ring is the phone's battery.
// Connected devices are linked to the centre. The devices fly out of the centre when the panel
// opens (one short animation, nothing keeps running). The phone list is only fetched while this
// is on screen.
StyledRect {
    id: root

    readonly property real cx: ring.width / 2
    readonly property real cy: ring.height / 2
    readonly property var btDevices: Bluetooth.devices.values.filter(d => d.paired || d.connected) // qmllint disable unresolved-type
    // Plain string keys keep each bubble (and its animation) when the devices' details change.
    readonly property var keys: {
        const phones = PhoneLink.devices.map(d => "kde:" + d.id);
        const bt = btDevices.slice().sort((a, b) => (b.connected ? 1 : 0) - (a.connected ? 1 : 0)).map(d => "bt:" + d.address);
        return phones.concat(bt).slice(0, 8);
    }
    property string selected

    // Where device `index` of `count` sits: spread over an ellipse around the centre.
    function spot(index: int, count: int): point {
        // One device sits to the right, two left and right, more go round from the top.
        const start = count === 2 ? 180 : -90;
        const angle = (count <= 1 ? 0 : start + 360 * index / count) * Math.PI / 180;
        const rx = Math.min(ring.width / 2 - 40, 150);
        const ry = ring.height / 2 - 42;
        return Qt.point(cx + Math.cos(angle) * rx, cy - 6 + Math.sin(angle) * ry);
    }

    function infoFor(key: string): var {
        if (key.startsWith("kde:")) {
            const d = PhoneLink.devices.find(p => "kde:" + p.id === key);
            if (!d)
                return null;
            return {
                name: d.name,
                icon: PhoneLink.iconFor(d.type),
                linked: d.reachable,
                busy: false,
                battery: d.charge >= 0 ? d.charge / 100 : -1,
                charging: d.charging,
                bt: null
            };
        }
        const addr = key.slice(3);
        const d = root.btDevices.find(b => b.address === addr);
        if (!d)
            return null;
        return {
            name: d.name,
            icon: Icons.getBluetoothIcon(d.icon),
            linked: d.connected,
            busy: d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting, // qmllint disable unresolved-type
            battery: d.batteryAvailable ? d.battery : -1,
            charging: false,
            bt: d
        };
    }

    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2
    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer

    Component.onCompleted: PhoneLink.addUser()
    Component.onDestruction: PhoneLink.removeUser()

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
                readonly property int linked: root.btDevices.filter(d => d.connected).length + PhoneLink.devices.filter(d => d.reachable).length

                text: linked > 0 ? Tr.trN("%n connected", "%n connected", linked) : ""
                font: Tokens.font.body.small
                color: Colours.palette.m3primary
            }
        }

        Item {
            id: ring

            Layout.fillWidth: true
            implicitHeight: 176

            // Links from this PC to connected devices (under the bubbles).
            Repeater {
                model: ScriptModel {
                    values: root.keys
                }

                Link {}
            }

            // This PC
            StyledRect {
                x: root.cx - width / 2
                y: root.cy - height / 2 - 6
                implicitWidth: 56
                implicitHeight: 56
                radius: Tokens.rounding.full
                color: Colours.palette.m3primaryContainer

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "computer"
                    fill: 1
                    color: Colours.palette.m3onPrimaryContainer
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

        // Actions for the chosen phone
        RowLayout {
            id: actions

            readonly property var phone: root.selected.startsWith("kde:") ? (PhoneLink.devices.find(d => "kde:" + d.id === root.selected) ?? null) : null

            Layout.fillWidth: true
            Layout.preferredHeight: phone ? implicitHeight : 0
            visible: Layout.preferredHeight > 0
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
                text: Tr.tr("Send file")
                disabled: !(actions.phone?.reachable ?? false)
                onClicked: PhoneLink.requestShare(actions.phone.id)
            }
        }
    }

    component Link: StyledRect {
        id: link

        required property string modelData
        required property int index
        readonly property var info: root.infoFor(modelData)
        readonly property point to: root.spot(index, root.keys.length)
        readonly property real dx: to.x - root.cx
        readonly property real dy: to.y - (root.cy - 6)

        x: root.cx
        y: root.cy - 6 - height / 2
        width: Math.sqrt(dx * dx + dy * dy)
        height: 2
        transformOrigin: Item.Left
        rotation: Math.atan2(dy, dx) * 180 / Math.PI
        color: Colours.palette.m3primary
        opacity: info?.linked ? 0.45 : 0

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
        readonly property point spotAt: root.spot(index, root.keys.length)
        readonly property bool chosen: root.selected === modelData
        property real reveal

        x: root.cx + (spotAt.x - root.cx) * reveal - width / 2
        y: root.cy - 6 + (spotAt.y - root.cy + 6) * reveal - 26
        width: 76
        height: 74
        opacity: reveal
        scale: 0.6 + 0.4 * reveal

        Component.onCompleted: revealAnim.start()

        SequentialAnimation {
            id: revealAnim

            PauseAnimation {
                duration: bubble.index * 35
            }

            Anim {
                target: bubble
                property: "reveal"
                from: 0
                to: 1
                type: Anim.DefaultSpatial
            }
        }

        // Battery ring
        CircularProgress {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            width: 52
            height: 52
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
            width: 42
            height: 42
            radius: Tokens.rounding.full
            color: bubble.chosen ? Colours.palette.m3tertiaryContainer : bubble.info?.linked ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainerHighest
            opacity: bubble.info?.linked || bubble.chosen ? 1 : 0.7

            StateLayer {
                radius: Tokens.rounding.full
                onClicked: {
                    const info = bubble.info;
                    if (!info)
                        return;
                    if (info.bt)
                        info.bt.connected = !info.bt.connected;
                    else
                        root.selected = root.selected === bubble.modelData ? "" : bubble.modelData;
                }
            }

            MaterialIcon {
                id: devIcon

                anchors.centerIn: parent
                text: bubble.info?.icon ?? "devices"
                fill: bubble.info?.linked ? 1 : 0
                color: bubble.info?.linked ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.medium

                // Pulses while (dis)connecting.
                SequentialAnimation on opacity {
                    running: bubble.info?.busy ?? false
                    loops: Animation.Infinite
                    alwaysRunToEnd: true

                    Anim {
                        to: 0.3
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
            elide: Text.ElideRight
            text: bubble.info?.name ?? ""
            font: Tokens.font.label.small
            color: bubble.info?.linked ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
        }
    }
}
