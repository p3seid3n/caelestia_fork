import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// The file dock in the bar: a small stack of the latest files (screenshots arrive here by
// themselves), with how many there are. Hovering opens the whole dock (popouts/FileDockPopout);
// the top file can be dragged straight out of the bar. While a file is dragged over the bar the
// stack opens up as a drop target. Takes no room while it is empty.
Item {
    id: root

    readonly property var top: FileDock.items[0] ?? null
    readonly property var second: FileDock.items[1] ?? null
    readonly property bool showing: FileDock.items.length > 0 || FileDock.dropHover
    // 0 hidden, 1 shown; the bar's spacing around it follows (Bar.qml).
    property real reveal: showing ? 1 : 0

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: Math.round(46 * reveal)
    clip: reveal < 1
    opacity: reveal

    Behavior on reveal {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    StyledRect {
        id: well

        anchors.fill: parent
        radius: Tokens.rounding.full
        color: FileDock.dropHover ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainer
        scale: FileDock.dropHover ? 1.06 : 1

        Behavior on scale {
            Anim {
                type: Anim.FastSpatial
            }
        }
    }

    // The file behind, peeking out.
    DockThumb {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: 3
        anchors.verticalCenterOffset: -2
        width: 24
        height: 24
        rotation: 9
        opacity: root.second && !FileDock.dropHover ? 0.75 : 0
        draggable: false
        path: root.second?.path ?? ""
        visible: root.second !== null
    }

    DockThumb {
        id: front

        anchors.centerIn: parent
        anchors.verticalCenterOffset: 1
        width: 26
        height: 26
        radius: Tokens.rounding.small
        opacity: root.top && !FileDock.dropHover ? 1 : 0
        path: root.top?.path ?? ""
        visible: root.top !== null
        scale: dragging ? 0.85 : 1

        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
            }
        }

        Behavior on scale {
            Anim {
                type: Anim.FastSpatial
            }
        }
    }

    // Count
    StyledRect {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 3
        anchors.bottomMargin: 3
        visible: FileDock.items.length > 1 && !FileDock.dropHover
        implicitWidth: Math.max(implicitHeight, count.implicitWidth + 6)
        implicitHeight: 15
        radius: Tokens.rounding.full
        color: Colours.palette.m3primary

        StyledText {
            id: count

            anchors.centerIn: parent
            text: FileDock.items.length > 9 ? "9+" : FileDock.items.length
            font: Tokens.font.label.builders.small.size(8).weight(Font.Bold).build()
            color: Colours.palette.m3onPrimary
        }
    }

    // Drop target
    MaterialIcon {
        anchors.centerIn: parent
        text: "add"
        color: Colours.palette.m3onPrimaryContainer
        fontStyle: Tokens.font.icon.medium
        opacity: FileDock.dropHover ? 1 : 0
        scale: FileDock.dropHover ? 1 : 0.6

        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
            }
        }

        Behavior on scale {
            Anim {
                type: Anim.FastSpatial
            }
        }
    }
}
