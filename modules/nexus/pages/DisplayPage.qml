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

// Settings → Display: resolution, refresh rate, scale, rotation, variable refresh rate and turning
// screens on or off, per monitor. Every change is tried live and undone after 15 seconds unless
// kept (services/Displays.qml).
PageBase {
    id: root

    readonly property var scales: [1, 1.25, 1.333333, 1.5, 1.6, 1.75, 2, 2.5, 3]

    function scaleLabel(s: real): string {
        return Math.round(s * 100) + " %";
    }

    title: Tr.tr("Display")

    Component.onCompleted: Displays.refresh()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Keep or revert
        StyledRect {
            Layout.fillWidth: true
            Layout.bottomMargin: Tokens.spacing.medium
            visible: Displays.pending !== null
            implicitHeight: keepRow.implicitHeight + Tokens.padding.large * 2
            radius: Tokens.rounding.extraLarge
            color: Colours.palette.m3primaryContainer

            RowLayout {
                id: keepRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: "desktop_windows"
                    color: Colours.palette.m3onPrimaryContainer
                    fontStyle: Tokens.font.icon.large
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Keep these display settings?")
                        font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                        color: Colours.palette.m3onPrimaryContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Going back to the previous settings in %1 s").arg(Displays.countdown)
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onPrimaryContainer
                    }
                }

                TextButton {
                    type: TextButton.Text
                    text: Tr.tr("Revert")
                    onClicked: Displays.revert()
                }

                TextButton {
                    type: TextButton.Filled
                    horizontalPadding: Tokens.padding.extraLarge
                    text: Tr.tr("Keep")
                    onClicked: Displays.keep()
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: Displays.monitors.length === 0
            horizontalAlignment: Text.AlignHCenter
            text: Tr.tr("No monitors found (is Hyprland running?)")
            font: Tokens.font.body.medium
            color: Colours.palette.m3onSurfaceVariant
        }

        Repeater {
            model: ScriptModel {
                values: Displays.monitors.map(m => m.name)
            }

            ColumnLayout {
                id: monitor

                required property string modelData
                required property int index
                readonly property var info: Displays.byName(modelData)
                readonly property var modes: Displays.modesOf(info)
                readonly property var resolutions: [...new Set(modes.map(m => `${m.w}x${m.h}`))]
                readonly property var rates: modes.filter(m => m.w === info?.width && m.h === info?.height)
                readonly property bool remembered: info ? Displays.saved[info.description] !== undefined : false

                function setMode(key: string): void {
                    Displays.tryChange(modelData, {
                        mode: key
                    });
                }

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2

                SectionHeader {
                    first: monitor.index === 0 && Displays.pending === null
                    text: monitor.info ? `${monitor.info.make ?? ""} ${monitor.info.model ?? ""}`.trim() + "  ·  " + monitor.modelData : monitor.modelData
                }

                Variants {
                    id: resolutionItems

                    model: monitor.resolutions

                    MenuItem {
                        required property string modelData

                        text: modelData.replace("x", " × ")
                        value: modelData
                    }
                }

                Variants {
                    id: rateItems

                    model: monitor.rates

                    MenuItem {
                        required property var modelData

                        text: Tr.tr("%1 Hz").arg(Math.round(modelData.hz * 100) / 100)
                        value: modelData.key
                    }
                }

                Variants {
                    id: scaleItems

                    model: root.scales

                    MenuItem {
                        required property real modelData

                        text: root.scaleLabel(modelData)
                        value: modelData
                    }
                }

                Variants {
                    id: rotationItems

                    model: [0, 1, 2, 3]

                    MenuItem {
                        required property int modelData

                        text: [Tr.tr("Normal"), Tr.tr("90°"), Tr.tr("180°"), Tr.tr("270°")][modelData]
                        value: modelData
                    }
                }

                ToggleRow {
                    first: true
                    last: monitor.info?.disabled ?? false
                    text: Tr.trCtx("Enabled", "toggle label")
                    subtext: monitor.info?.description ?? ""
                    checked: !(monitor.info?.disabled ?? false)
                    onToggled: Displays.tryChange(monitor.modelData, {
                        disabled: !checked
                    })
                }

                SelectRow {
                    visible: !(monitor.info?.disabled ?? false)
                    label: Tr.tr("Resolution")
                    menuItems: resolutionItems.instances
                    active: menuItems.find(i => i.value === `${monitor.info?.width}x${monitor.info?.height}`) ?? null
                    fallbackText: monitor.info ? `${monitor.info.width} × ${monitor.info.height}` : ""
                    onSelected: item => {
                        // The highest refresh rate of the new resolution.
                        const best = monitor.modes.find(m => `${m.w}x${m.h}` === item.value);
                        if (best)
                            monitor.setMode(best.key);
                    }
                }

                SelectRow {
                    visible: !(monitor.info?.disabled ?? false)
                    label: Tr.tr("Refresh rate")
                    menuItems: rateItems.instances
                    active: menuItems.find(i => Math.abs(parseFloat(i.value.split("@")[1]) - (monitor.info?.refreshRate ?? 0)) < 0.05) ?? null
                    fallbackText: monitor.info ? Tr.tr("%1 Hz").arg(Math.round(monitor.info.refreshRate * 100) / 100) : ""
                    onSelected: item => monitor.setMode(item.value)
                }

                SelectRow {
                    visible: !(monitor.info?.disabled ?? false)
                    label: Tr.tr("Scale")
                    subtext: Tr.tr("Makes text and everything else bigger")
                    menuItems: scaleItems.instances
                    active: menuItems.find(i => Math.abs(i.value - (monitor.info?.scale ?? 1)) < 0.01) ?? null
                    fallbackText: root.scaleLabel(monitor.info?.scale ?? 1)
                    onSelected: item => Displays.tryChange(monitor.modelData, {
                        scale: item.value
                    })
                }

                SelectRow {
                    visible: !(monitor.info?.disabled ?? false)
                    label: Tr.tr("Rotation")
                    menuItems: rotationItems.instances
                    active: menuItems[(monitor.info?.transform ?? 0) % 4] ?? null
                    onSelected: item => Displays.tryChange(monitor.modelData, {
                        transform: item.value
                    })
                }

                ToggleRow {
                    visible: !(monitor.info?.disabled ?? false)
                    last: !monitor.remembered
                    text: Tr.tr("Variable refresh rate")
                    subtext: Tr.tr("Adaptive sync (FreeSync / G-Sync) where the screen supports it")
                    checked: monitor.info?.vrr ?? false
                    onToggled: Displays.tryChange(monitor.modelData, {
                        vrr: checked ? 1 : 0
                    })
                }

                RowButton {
                    visible: monitor.remembered
                    last: true
                    icon: "restart_alt"
                    text: Tr.tr("Use the Hyprland config again")
                    subtext: Tr.tr("Forget the settings made here for this monitor")
                    onClicked: Displays.forget(monitor.info.description)
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.large
            Layout.leftMargin: Tokens.padding.small
            wrapMode: Text.WordWrap
            text: Tr.tr("Settings you keep here are applied by the shell on top of your Hyprland config, also after restarts.")
            font: Tokens.font.body.small
            color: Colours.palette.m3outline
        }
    }
}
