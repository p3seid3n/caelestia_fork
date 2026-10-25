pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

// Content of the "Add a widget" sheet: every kind of widget with what it shows and its starting size.
ColumnLayout {
    id: root

    signal added

    spacing: Tokens.spacing.small

    StyledListView {
        id: list

        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: Tokens.spacing.extraSmall
        boundsBehavior: Flickable.StopAtBounds
        model: ScriptModel {
            values: DashboardWidgets.typeIds
        }

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: list
        }

        delegate: StyledRect {
            id: row

            required property string modelData
            readonly property var type: DashboardWidgets.types[modelData]
            readonly property int count: DashboardWidgets.widgets.filter(w => w.type === modelData).length

            width: list.width
            implicitHeight: 60
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.large
                anchors.rightMargin: Tokens.padding.medium
                spacing: Tokens.spacing.medium

                StyledRect {
                    implicitWidth: 40
                    implicitHeight: 40
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3primaryContainer

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: row.type.icon
                        fill: 1
                        color: Colours.palette.m3onPrimaryContainer
                        fontStyle: Tokens.font.icon.medium
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: row.type.name
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: row.type.info
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }

                StyledText {
                    visible: row.count > 0
                    text: Tr.tr("On dashboard")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                IconButton {
                    type: IconButton.Tonal
                    isRound: true
                    icon: "add"
                    onClicked: {
                        DashboardWidgets.add(row.modelData);
                        root.added();
                    }
                }
            }
        }
    }
}
