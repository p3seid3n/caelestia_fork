import QtQuick
import Caelestia.Config
import qs.components

// One clock digit.
// - Rolls (old digit slides up and fades, new one rises in) whenever it changes.
// - Thin in the AoD state, bold when awake: `boldness` drives the clock font's variable weight
//   axis, so the glyph really thickens (in steps of 20, which looks continuous).
Item {
    id: root

    required property string digit
    required property color colour
    required property real pointSize
    property real boldness // 0 = thin (AoD), 1 = bold (awake)

    property string shown: digit
    readonly property int weight: Math.round((300 + 400 * boldness) / 20) * 20

    // Same box for every digit so the clock never jitters sideways.
    implicitWidth: zeroMetrics.advanceWidth
    implicitHeight: zeroMetrics.tightBoundingRect.height

    onDigitChanged: {
        if (digit !== shown)
            roll.restart();
    }

    // Measured at the boldest weight so the box stays put while the weight changes.
    TextMetrics {
        id: zeroMetrics

        text: "0"
        font: Tokens.font.clock.size(root.pointSize).vaxis("wght", 700).build()
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
            anchors.horizontalCenter: parent.horizontalCenter
            y: -(zeroMetrics.tightBoundingRect.y - zeroMetrics.boundingRect.y)
            text: root.shown
            color: root.colour
            font: Tokens.font.clock.size(root.pointSize).vaxis("wght", root.weight).build()
        }
    }
}
