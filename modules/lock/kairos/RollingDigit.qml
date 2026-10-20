import QtQuick
import Caelestia.Config
import qs.components

// One clock digit.
// - Rolls (old digit slides up and fades, new one rises in) whenever it changes.
// - Two weights stacked on top of each other: thin for the AoD state, bold when awake.
//   `boldness` crossfades between them, which reads as the glyph thickening.
Item {
    id: root

    required property string digit
    required property color colour
    required property real pointSize
    property real boldness // 0 = thin (AoD), 1 = bold (awake)

    property string shown: digit

    // Same box for every digit so the clock never jitters sideways.
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
            Anim {
                target: face
                property: "y"
                to: -root.implicitHeight * 0.35
                type: Anim.FastSpatial
            }
            Anim {
                target: face
                property: "opacity"
                to: 0
                type: Anim.FastEffects
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
            Anim {
                target: face
                property: "y"
                to: 0
                type: Anim.DefaultSpatial
            }
            Anim {
                target: face
                property: "opacity"
                to: 1
                type: Anim.DefaultEffects
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
            font: Tokens.font.clock.size(root.pointSize).vaxis("wght", 300).build()
            opacity: 1 - root.boldness
        }

        Text {
            id: bold

            anchors.horizontalCenter: parent.horizontalCenter
            y: thin.y
            text: root.shown
            color: root.colour
            font: Tokens.font.clock.size(root.pointSize).vaxis("wght", 700).build()
            opacity: root.boldness
        }
    }
}
