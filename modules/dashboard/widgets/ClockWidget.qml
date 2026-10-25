import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Time and date; the date drops out when the widget is a single row high.
Item {
    id: root

    readonly property bool compact: height < 130
    readonly property real clockSize: compact ? 30 : width > 300 ? 60 : 42

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width - Tokens.padding.large * 2
        spacing: 0

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Time.hourStr + ":" + Time.minuteStr + (Time.amPmStr !== "" ? " " + Time.amPmStr : "")
            color: Colours.palette.m3primary
            font: Tokens.font.clock.size(root.clockSize).weight(Font.DemiBold).build()
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            visible: !root.compact
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: Time.format("dddd, d MMMM")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.medium
        }
    }
}
