import QtQuick

// Greeter copy of modules/lock/kairos/RollingDigit.qml without Caelestia dependencies.
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
            M3Anim {
                target: face
                property: "y"
                to: -root.implicitHeight * 0.35
                duration: 250
            }
            M3Anim {
                target: face
                property: "opacity"
                to: 0
                duration: 150
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
            M3Anim {
                target: face
                property: "y"
                to: 0
            }
            M3Anim {
                target: face
                property: "opacity"
                to: 1
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
