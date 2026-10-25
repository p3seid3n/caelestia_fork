pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// Choose which dashboard tabs exist and in which order. Opens over the tab content
// from the tune button in the tab bar.
Item {
    id: root

    signal done

    implicitWidth: 840
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: Tr.tr("Customise dashboard")
                    font: Tokens.font.body.builders.large.size(28).weight(Font.DemiBold).build()
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Tr.tr("Switch tabs on or off and use the arrows to change their order.")
                    font: Tokens.font.body.medium
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            TextButton {
                type: TextButton.Text
                text: Tr.tr("Reset")
                onClicked: DashboardLayout.reset()
            }

            TextButton {
                type: TextButton.Filled
                horizontalPadding: Tokens.padding.extraLarge
                text: Tr.tr("Done")
                onClicked: root.done()
            }
        }

        Repeater {
            model: ScriptModel {
                values: DashboardLayout.order
            }

            StyledRect {
                id: row

                required property string modelData
                required property int index
                readonly property bool on: DashboardLayout.enabledIds.includes(modelData)

                Layout.fillWidth: true
                implicitHeight: 52
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainer

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.large
                    anchors.rightMargin: Tokens.padding.medium
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: 36
                        implicitHeight: 36
                        radius: Tokens.rounding.full
                        color: row.on ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainerHighest

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: DashboardLayout.meta[row.modelData]?.icon ?? "tab"
                            fill: row.on ? 1 : 0
                            color: row.on ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.medium
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: DashboardLayout.meta[row.modelData]?.name ?? row.modelData
                        font: Tokens.font.body.medium
                        color: row.on ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                    }

                    IconButton {
                        type: IconButton.Text
                        isRound: true
                        icon: "keyboard_arrow_up"
                        disabled: row.index === 0
                        onClicked: DashboardLayout.move(row.modelData, -1)
                    }

                    IconButton {
                        type: IconButton.Text
                        isRound: true
                        icon: "keyboard_arrow_down"
                        disabled: row.index === DashboardLayout.order.length - 1
                        onClicked: DashboardLayout.move(row.modelData, 1)
                    }

                    StyledSwitch {
                        id: toggle

                        // The last tab that is on cannot be switched off.
                        disabled: row.on && DashboardLayout.enabledIds.length <= 1
                        onToggled: DashboardLayout.setEnabled(row.modelData, checked)

                        // A plain `checked:` binding is lost after the first click, and Reset has to reach this switch.
                        Binding {
                            target: toggle
                            property: "checked"
                            value: row.on
                        }
                    }
                }
            }
        }
    }
}
