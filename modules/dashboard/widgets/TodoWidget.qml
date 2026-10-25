import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services

// Open tasks with a round check to tick them off, as many as fit.
Item {
    id: root

    readonly property real rowHeight: 34
    readonly property var open: Todos.items.filter(i => !i.done)
    readonly property int fit: Math.max(1, Math.floor((height - Tokens.padding.large * 2 - header.height - layout.spacing) / (rowHeight + layout.spacing)))
    // One row is kept for "+N more" when not everything fits.
    readonly property int limit: open.length > fit ? Math.max(1, fit - 1) : fit
    readonly property var shown: open.slice(0, limit)

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.extraSmall

        RowLayout {
            id: header

            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "checklist"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                Layout.fillWidth: true
                text: Tr.tr("To-do")
                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                color: Colours.palette.m3primary
            }

            StyledText {
                visible: root.open.length > 0
                text: String(root.open.length)
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }

        Repeater {
            model: root.shown

            Item {
                id: row

                required property var modelData

                Layout.fillWidth: true
                Layout.preferredHeight: root.rowHeight

                StyledRect {
                    id: check

                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 22
                    implicitHeight: 22
                    radius: Tokens.rounding.full
                    color: "transparent"
                    border.width: 2
                    border.color: Colours.palette.m3outline

                    StateLayer {
                        radius: parent.radius
                        onClicked: Todos.toggle(row.modelData.id)
                    }
                }

                StyledText {
                    anchors.left: check.right
                    anchors.leftMargin: Tokens.spacing.medium
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: row.modelData.text
                    font: Tokens.font.body.medium
                    color: Colours.palette.m3onSurface
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.open.length > root.shown.length
            text: Tr.tr("+%1 more").arg(root.open.length - root.shown.length)
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.open.length === 0
            text: Todos.items.length === 0 ? Tr.tr("No tasks yet") : Tr.tr("All done")
            font: Tokens.font.body.medium
            color: Colours.palette.m3onSurfaceVariant
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
