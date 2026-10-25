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

// Settings → Updates: what can be updated (Arch repositories, AUR, Flatpak) and the shell itself.
// Updating opens the terminal (services/SystemUpdates.qml).
PageBase {
    id: root

    readonly property int total: SystemUpdates.packages.length

    function ago(ms: double): string {
        if (ms <= 0)
            return "";
        const minutes = Math.round((Date.now() - ms) / 60000);
        if (minutes < 1)
            return Tr.tr("just now");
        if (minutes < 60)
            return Tr.tr("%1 min ago").arg(minutes);
        return Tr.tr("%1 h ago").arg(Math.round(minutes / 60));
    }

    function sourceName(s: string): string {
        return s === "aur" ? "AUR" : s === "flatpak" ? "Flatpak" : Tr.tr("Arch");
    }

    title: Tr.tr("Updates")

    Component.onCompleted: {
        if (Date.now() - SystemUpdates.lastCheck > 10 * 60000)
            SystemUpdates.check();
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Summary
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: summary.implicitHeight + Tokens.padding.extraLarge * 2
            radius: Tokens.rounding.extraLarge
            color: root.total > 0 ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainer

            RowLayout {
                id: summary

                anchors.fill: parent
                anchors.margins: Tokens.padding.extraLarge
                spacing: Tokens.spacing.large

                StyledRect {
                    implicitWidth: 56
                    implicitHeight: 56
                    radius: Tokens.rounding.full
                    color: root.total > 0 ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainerHighest

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: SystemUpdates.checking ? "sync" : root.total > 0 ? "system_update_alt" : "verified"
                        color: root.total > 0 ? Colours.palette.m3onPrimary : Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.large

                        RotationAnimation on rotation {
                            running: SystemUpdates.checking
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 1200
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: SystemUpdates.checking ? Tr.tr("Checking for updates...") : root.total > 0 ? Tr.trN("%n update available", "%n updates available", root.total) : Tr.tr("Everything is up to date")
                        font: Tokens.font.body.builders.large.size(20).weight(Font.DemiBold).build()
                        color: root.total > 0 ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: {
                            const parts = [];
                            if (SystemUpdates.repoCount > 0)
                                parts.push(Tr.tr("%1 from Arch").arg(SystemUpdates.repoCount));
                            if (SystemUpdates.aurCount > 0)
                                parts.push(Tr.tr("%1 from the AUR").arg(SystemUpdates.aurCount));
                            if (SystemUpdates.flatpakCount > 0)
                                parts.push(Tr.tr("%1 Flatpak").arg(SystemUpdates.flatpakCount));
                            const when = SystemUpdates.lastCheck > 0 ? Tr.tr("Checked %1").arg(root.ago(SystemUpdates.lastCheck)) : "";
                            return parts.concat(when ? [when] : []).join(" · ");
                        }
                        font: Tokens.font.body.small
                        color: root.total > 0 ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                    }
                }

                TextButton {
                    type: TextButton.Tonal
                    text: Tr.tr("Check now")
                    disabled: SystemUpdates.checking
                    onClicked: SystemUpdates.check()
                }

                TextButton {
                    visible: root.total > 0
                    type: TextButton.Filled
                    horizontalPadding: Tokens.padding.extraLarge
                    text: Tr.tr("Update all")
                    onClicked: SystemUpdates.updateSystem()
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            Layout.leftMargin: Tokens.padding.small
            visible: !SystemUpdates.hasCheckupdates && SystemUpdates.lastCheck > 0
            wrapMode: Text.WordWrap
            text: Tr.tr("Install pacman-contrib to see updates from the Arch repositories: sudo pacman -S pacman-contrib")
            font: Tokens.font.body.small
            color: Colours.palette.m3error
        }

        // Packages
        SectionHeader {
            visible: root.total > 0
            text: Tr.tr("Packages")
        }

        Repeater {
            model: ScriptModel {
                values: SystemUpdates.packages.slice(0, 200).map(p => p.source + ":" + p.name)
            }

            InfoRow {
                id: pkg

                required property string modelData
                required property int index
                readonly property var info: SystemUpdates.packages.find(p => p.source + ":" + p.name === modelData) ?? null

                first: index === 0
                last: index === Math.min(SystemUpdates.packages.length, 200) - 1
                icon: info?.source === "flatpak" ? "deployed_code" : info?.source === "aur" ? "group" : "package_2"
                label: info?.name ?? ""
                subtext: root.sourceName(info?.source ?? "")
                value: info ? (info.from ? info.from + "  →  " + info.to : info.to) : ""
            }
        }

        // The shell
        SectionHeader {
            text: Tr.tr("Shell")
        }

        InfoRow {
            first: true
            last: !SystemUpdates.shellIsGit || SystemUpdates.shellBehind === 0
            icon: "deployed_code_update"
            label: Tr.tr("Caelestia shell")
            subtext: SystemUpdates.shellIsGit ? Tr.tr("Branch %1 · %2").arg(SystemUpdates.shellBranch).arg(SystemUpdates.shellCommit) : Tr.tr("Not a git checkout; updated with your system packages")
            value: !SystemUpdates.shellIsGit ? "" : SystemUpdates.shellBehind > 0 ? Tr.trN("%n new commit", "%n new commits", SystemUpdates.shellBehind) : Tr.tr("Up to date")
        }

        RowButton {
            visible: SystemUpdates.shellIsGit && SystemUpdates.shellBehind > 0
            last: true
            icon: "download"
            text: Tr.tr("Update the shell")
            subtext: Tr.tr("Pulls the new commits; restart the shell afterwards")
            onClicked: SystemUpdates.updateShell()
        }
    }
}
