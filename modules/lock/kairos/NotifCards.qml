pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services

// The latest notifications on the awake lock screen, newest on top. With "lock.hideNotifs" only
// their number is shown.
ColumnLayout {
    id: root

    readonly property var latest: Notifs.notClosed.slice(-3).reverse()

    spacing: Tokens.spacing.small

    Repeater {
        model: Config.lock.hideNotifs ? [] : root.latest

        StyledRect {
            id: card

            required property var modelData

            Layout.preferredWidth: 360
            implicitHeight: content.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.large
            color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.85)

            ColumnLayout {
                id: content

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.large
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: card.modelData.urgency === "critical" ? "priority_high" : "notifications"
                        color: card.modelData.urgency === "critical" ? Colours.palette.m3error : Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.small
                    }

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: card.modelData.appName || Tr.tr("Notification")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    StyledText {
                        text: card.modelData.timeStr ?? ""
                        font: Tokens.font.body.small
                        color: Colours.palette.m3outline
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: card.modelData.summary
                    font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    textFormat: Text.PlainText
                    text: String(card.modelData.body ?? "").replace(/<[^>]*>/g, "").split("\n")[0]
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }

    StyledRect {
        visible: Config.lock.hideNotifs && Notifs.notClosed.length > 0
        Layout.preferredWidth: 360
        implicitHeight: 48
        radius: Tokens.rounding.large
        color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.85)

        StyledText {
            anchors.centerIn: parent
            text: Tr.trN("%n notification · unlock to see it", "%n notifications · unlock to see them", Notifs.notClosed.length)
            font: Tokens.font.body.medium
            color: Colours.palette.m3onSurfaceVariant
        }
    }
}
