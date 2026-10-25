import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Current weather: icon and temperature, with the description (and the place) when there is room.
Item {
    id: root

    readonly property bool compact: height < 130

    Component.onCompleted: Weather.reload()

    RowLayout {
        anchors.centerIn: parent
        width: parent.width - Tokens.padding.large * 2
        spacing: Tokens.spacing.large

        MaterialIcon {
            Layout.alignment: Qt.AlignVCenter
            animate: true
            text: Weather.icon
            color: Colours.palette.m3secondary
            fontStyle: Tokens.font.icon.builders.extraLarge.scale(root.compact ? 1 : 1.6).build()
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                animate: true
                elide: Text.ElideRight
                text: Weather.temp
                color: Colours.palette.m3primary
                font: Tokens.font.headline.builders.medium.weight(Font.DemiBold).build()
            }

            StyledText {
                Layout.fillWidth: true
                visible: !root.compact
                animate: true
                elide: Text.ElideRight
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                text: Weather.description
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.small
            }

            StyledText {
                Layout.fillWidth: true
                visible: !root.compact && Weather.city !== ""
                elide: Text.ElideRight
                text: Weather.city
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }
        }
    }
}
