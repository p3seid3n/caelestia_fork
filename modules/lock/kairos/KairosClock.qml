import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// HyperOS-style stacked clock: hours on top, minutes below, date underneath.
Column {
    id: root

    required property real pointSize
    property real boldness

    readonly property color hourColour: LockStyle.hourColour || Colours.palette.m3primary
    readonly property color minuteColour: LockStyle.minuteColour || Colours.palette.m3secondary
    readonly property color dateColour: LockStyle.accentColour || Colours.palette.m3onSurfaceVariant

    spacing: pointSize * 0.12

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.pointSize * 0.04

        Repeater {
            model: 2

            RollingDigit {
                required property int index

                digit: Time.hourStr.charAt(index)
                colour: root.hourColour
                pointSize: Math.round(root.pointSize)
                boldness: root.boldness
            }
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.pointSize * 0.04

        Repeater {
            model: 2

            RollingDigit {
                required property int index

                digit: Time.minuteStr.charAt(index)
                colour: root.minuteColour
                pointSize: Math.round(root.pointSize)
                boldness: root.boldness
            }
        }
    }

    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        topPadding: root.pointSize * 0.1
        text: Time.format("dddd, d MMMM")
        color: root.dateColour
        font: Tokens.font.title.builders.medium.size(Math.round(root.pointSize * 0.13)).weight(Font.Medium).build()
        opacity: 0.6 + 0.4 * root.boldness
    }
}
