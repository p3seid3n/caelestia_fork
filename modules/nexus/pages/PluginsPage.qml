pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// Settings → Plugins: Hyprland plugins through hyprpm, with title bars for floating windows
// (hyprbars) one click away (services/HyprPlugins.qml).
PageBase {
    id: root

    title: Tr.tr("Plugins")

    Component.onCompleted: HyprPlugins.refresh()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        StyledRect {
            Layout.fillWidth: true
            visible: !HyprPlugins.hasHyprpm
            implicitHeight: noPm.implicitHeight + Tokens.padding.extraLarge * 2
            radius: Tokens.rounding.extraLarge
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                id: noPm

                anchors.centerIn: parent
                width: parent.width - Tokens.padding.extraLarge * 2
                spacing: Tokens.spacing.small

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "extension_off"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.extraLarge
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: Tr.tr("hyprpm, Hyprland's plugin manager, was not found. It comes with Hyprland; plugins also need cmake, meson, cpio and git.")
                    font: Tokens.font.body.medium
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }

        // Title bars
        SectionHeader {
            first: true
            visible: HyprPlugins.hasHyprpm
            text: Tr.tr("Recommended")
        }

        StyledRect {
            Layout.fillWidth: true
            visible: HyprPlugins.hasHyprpm
            implicitHeight: bars.implicitHeight + Tokens.padding.large * 2
            radius: Tokens.rounding.extraLarge
            color: HyprPlugins.hyprbarsLoaded ? Colours.tPalette.m3surfaceContainer : Colours.palette.m3primaryContainer

            RowLayout {
                id: bars

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.large

                StyledRect {
                    implicitWidth: 48
                    implicitHeight: 48
                    radius: Tokens.rounding.large
                    color: Colours.palette.m3primary

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "web_asset"
                        color: Colours.palette.m3onPrimary
                        fontStyle: Tokens.font.icon.large
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Title bars (hyprbars)")
                        font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                        color: HyprPlugins.hyprbarsLoaded ? Colours.palette.m3onSurface : Colours.palette.m3onPrimaryContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: HyprPlugins.hyprbarsLoaded ? Tr.tr("Installed and loaded. Floating windows get Material You title bars.") : HyprPlugins.hasHyprbars ? Tr.tr("Installed but not loaded. Switch it on below.") : Tr.tr("Close, maximise and minimise buttons on floating windows. Built from Hyprland's official plugin repository; the terminal may ask for your password.")
                        font: Tokens.font.body.small
                        color: HyprPlugins.hyprbarsLoaded ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onPrimaryContainer
                    }
                }

                TextButton {
                    visible: !HyprPlugins.hasHyprbars
                    type: TextButton.Filled
                    horizontalPadding: Tokens.padding.extraLarge
                    text: Tr.tr("Install")
                    onClicked: HyprPlugins.installTitleBars()
                }
            }
        }

        // Installed
        Repeater {
            model: ScriptModel {
                values: HyprPlugins.repos.map(r => r.repo)
            }

            ColumnLayout {
                id: repo

                required property string modelData
                readonly property var info: HyprPlugins.repos.find(r => r.repo === modelData) ?? null

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                SectionHeader {
                    text: repo.info ? Tr.tr("%1 by %2").arg(repo.info.repo).arg(repo.info.author) : repo.modelData
                }

                Repeater {
                    model: repo.info?.plugins ?? []

                    ToggleRow {
                        required property var modelData
                        required property int index

                        first: index === 0
                        last: index === (repo.info?.plugins.length ?? 1) - 1
                        text: modelData.name
                        subtext: modelData.failed ? Tr.tr("Failed to build; try Update plugins") : HyprPlugins.loaded.some(n => n.toLowerCase().includes(modelData.name.toLowerCase())) ? Tr.tr("Loaded") : Tr.tr("Not loaded")
                        disabled: HyprPlugins.busy || modelData.failed
                        checked: modelData.enabled
                        onToggled: HyprPlugins.setEnabled(modelData.name, checked)
                    }
                }
            }
        }

        // Manage
        SectionHeader {
            visible: HyprPlugins.hasHyprpm
            text: Tr.tr("Manage")
        }

        RowButton {
            visible: HyprPlugins.hasHyprpm
            first: true
            icon: "update"
            text: Tr.tr("Update plugins")
            subtext: Tr.tr("Rebuilds plugins for the running Hyprland; needed after Hyprland updates")
            onClicked: HyprPlugins.updateAll()
        }

        TextFieldRow {
            id: repoField

            visible: HyprPlugins.hasHyprpm
            last: true
            label: Tr.tr("Add a plugin repository")
            subtext: Tr.tr("Only add repositories you trust: plugins run inside Hyprland")
            placeholderText: "https://github.com/..."
            onEditingFinished: value => {
                if (value.trim() !== "")
                    HyprPlugins.addRepository(value);
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            Layout.leftMargin: Tokens.padding.small
            visible: HyprPlugins.error !== ""
            wrapMode: Text.WordWrap
            text: HyprPlugins.error
            font: Tokens.font.body.small
            color: Colours.palette.m3error
        }
    }
}
