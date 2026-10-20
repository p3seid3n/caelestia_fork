import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// Pill slider with a colour gradient track: hue (rainbow) or colour temperature (warm -> cool).
// value is 0-1. `moved(v)` fires while dragging, `released(v)` at the end.
Item {
    id: root

    property string kind: "hue" // "hue" | "temperature"
    property real value
    readonly property bool dragging: mouse.pressed

    signal moved(v: real)
    signal released(v: real)

    implicitWidth: 200
    implicitHeight: 28

    Rectangle {
        id: track

        anchors.fill: parent
        radius: height / 2
        gradient: Gradient {
            orientation: Gradient.Horizontal

            GradientStop {
                position: 0
                color: root.kind === "hue" ? Qt.hsva(0, 0.75, 1, 1) : "#ffa95c"
            }
            GradientStop {
                position: 0.17
                color: root.kind === "hue" ? Qt.hsva(0.17, 0.75, 1, 1) : "#ffc185"
            }
            GradientStop {
                position: 0.33
                color: root.kind === "hue" ? Qt.hsva(0.33, 0.75, 1, 1) : "#ffd6aa"
            }
            GradientStop {
                position: 0.5
                color: root.kind === "hue" ? Qt.hsva(0.5, 0.75, 1, 1) : "#ffe9d1"
            }
            GradientStop {
                position: 0.67
                color: root.kind === "hue" ? Qt.hsva(0.67, 0.75, 1, 1) : "#fdf4ec"
            }
            GradientStop {
                position: 0.83
                color: root.kind === "hue" ? Qt.hsva(0.83, 0.75, 1, 1) : "#e6ebff"
            }
            GradientStop {
                position: 1
                color: root.kind === "hue" ? Qt.hsva(1, 0.75, 1, 1) : "#cbd6ff"
            }
        }
    }

    // Knob
    Rectangle {
        id: knob

        readonly property real shown: mouse.pressed ? mouse.pos : root.value

        x: shown * (root.width - width)
        anchors.verticalCenter: parent.verticalCenter
        width: root.height + (mouse.pressed ? 6 : 0)
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 4
        border.color: Colours.palette.m3onSurface

        Behavior on width {
            Anim {
                type: Anim.FastSpatial
            }
        }
    }

    MouseArea {
        id: mouse

        property real pos

        anchors.fill: parent
        anchors.margins: -6
        preventStealing: true
        cursorShape: Qt.PointingHandCursor

        function update(x: real): void {
            pos = Math.max(0, Math.min(1, (x - 6) / root.width));
        }

        onPressed: e => {
            update(e.x);
            root.moved(pos);
        }
        onPositionChanged: e => {
            update(e.x);
            root.moved(pos);
        }
        onReleased: root.released(pos)
    }
}
