import QtQuick

// Greeter copy of modules/lock/kairos/RollingDigit.qml without Caelestia dependencies.
// Same motion (Motion.qml mirrors Caelestia's Anim types).
Item {
    id: root

    required property string digit
    required property color colour
    required property real pointSize
    property real boldness

    property string shown: digit

    implicitWidth: zeroMetrics.advanceWidth
    implicitHeight: zeroMetrics.tightBoundingRect.height

    onDigitChanged: {
        if (digit !== shown)
            roll.restart();
    }

    TextMetrics {
        id: zeroMetrics

        text: "0"
        font: bold.font
    }

    SequentialAnimation {
        id: roll

        ParallelAnimation {
            Motion {
                target: face
                property: "y"
                to: -root.implicitHeight * 0.35
                type: "fastSpatial"
            }
            Motion {
                target: face
                property: "opacity"
                to: 0
                type: "fastEffects"
            }
        }
        PropertyAction {
            target: root
            property: "shown"
            value: root.digit
        }
        PropertyAction {
            target: face
            property: "y"
            value: root.implicitHeight * 0.35
        }
        ParallelAnimation {
            Motion {
                target: face
                property: "y"
                to: 0
                type: "defaultSpatial"
            }
            Motion {
                target: face
                property: "opacity"
                to: 1
                type: "defaultEffects"
            }
        }
    }

    Item {
        id: face

        width: root.width
        height: root.height

        Text {
            id: thin

            anchors.horizontalCenter: parent.horizontalCenter
            y: -(zeroMetrics.tightBoundingRect.y - zeroMetrics.boundingRect.y)
            text: root.shown
            color: root.colour
            font.family: "Rubik"
            font.pointSize: root.pointSize
            font.weight: Font.Light
            opacity: 1 - root.boldness
        }

        Text {
            id: bold

            anchors.horizontalCenter: parent.horizontalCenter
            y: thin.y
            text: root.shown
            color: root.colour
            font.family: "Rubik"
            font.pointSize: root.pointSize
            font.weight: Font.Bold
            opacity: root.boldness
        }
    }
}
