import QtQuick
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Full view of one device. Grows out of the tapped tile (container transform) and
// shrinks back into it when closed. Shows the tile at its largest size, so every
// control the device supports is there.
Item {
    id: root

    property string entityId
    property rect from
    property bool open
    property real prog: open ? 1 : 0

    function show(id: string, r: rect): void {
        entityId = id;
        from = r;
        open = true;
    }

    visible: prog > 0

    Behavior on prog {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    // Scrim: tap outside to close.
    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.large
        color: Colours.palette.m3scrim
        opacity: 0.35 * root.prog

        MouseArea {
            anchors.fill: parent
            enabled: root.open
            onClicked: root.open = false
        }
    }

    Item {
        id: card

        x: root.from.x * (1 - root.prog)
        y: root.from.y * (1 - root.prog)
        width: root.from.width + (root.width - root.from.width) * root.prog
        height: root.from.height + (root.height - root.from.height) * root.prog
        opacity: Math.min(1, root.prog * 3)

        EntityTile {
            anchors.fill: parent
            entityId: root.entityId
            cols: 8
            rows: 3
            onExpand: root.open = false // tapping the body again closes it
        }

        IconButton {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Tokens.padding.medium
            type: IconButton.Text
            isRound: true
            icon: "close"
            opacity: root.prog
            onClicked: root.open = false
        }
    }
}
