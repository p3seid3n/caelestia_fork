pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services
import qs.modules.nexus.common

// Settings → Windows: tiling or floating windows, title bars, snapping, gaps, borders and the
// shell's frame. Window settings are applied live through services/WindowLayout.qml.
PageBase {
    id: root

    function px(v: int): string {
        return Tr.tr("%1 px").arg(v);
    }

    title: Tr.tr("Windows")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: Tr.tr("Window mode")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            ModeCard {
                mode: "tiling"
                title: Tr.tr("Tiling")
                subtitle: Tr.tr("Hyprland arranges windows side by side")
            }

            ModeCard {
                mode: "floating"
                title: Tr.tr("Floating")
                subtitle: Tr.tr("Windows float freely, like on Windows or macOS")
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            Layout.leftMargin: Tokens.padding.small
            visible: !WindowLayout.available
            wrapMode: Text.WordWrap
            text: Tr.tr("Hyprland is not running, so window settings have no effect.")
            font: Tokens.font.body.small
            color: Colours.palette.m3error
        }

        SectionHeader {
            text: Tr.tr("Floating windows")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Title bars")
            subtext: WindowLayout.hasTitleBarPlugin ? Tr.tr("Close, maximise and minimise in the wallpaper's colours; double-click to maximise") : Tr.tr("Needs the hyprbars plugin: Settings → Plugins → Title bars")
            disabled: !WindowLayout.floating || !WindowLayout.lua
            checked: WindowLayout.titleBars
            onToggled: WindowLayout.setOption("titleBars", checked)
        }

        ToggleRow {
            text: Tr.tr("Buttons on the left")
            subtext: Tr.tr("macOS style, with the title centred; off puts them on the right like Windows")
            disabled: !WindowLayout.floating || !WindowLayout.titleBars || !WindowLayout.lua
            checked: WindowLayout.buttonsLeft
            onToggled: WindowLayout.setOption("buttonsLeft", checked)
        }

        ToggleRow {
            text: Tr.tr("Snap to edges")
            subtext: Tr.tr("Windows stick to the screen edges and to each other when moved close")
            disabled: !WindowLayout.floating
            checked: WindowLayout.snap
            onToggled: WindowLayout.setOption("snap", checked)
        }

        ToggleRow {
            last: true
            text: Tr.tr("Resize from window edges")
            subtext: Tr.tr("Drag a window's border to resize it, without holding Super")
            disabled: !WindowLayout.floating
            checked: WindowLayout.resizeOnEdges
            onToggled: WindowLayout.setOption("resizeOnEdges", checked)
        }

        SectionHeader {
            text: Tr.tr("Special workspaces")
        }

        ToggleRow {
            first: true
            last: true
            text: Tr.tr("Click behind to hide")
            subtext: WindowLayout.lua ? Tr.tr("Music (Super+M), messages (Super+D) and to-do (Super+R) open on top of your windows; clicking a window behind them hides them and brings it forward") : Tr.tr("Needs a Lua Hyprland config")
            disabled: !WindowLayout.lua
            checked: WindowLayout.dismissSpecial
            onToggled: WindowLayout.setOption("dismissSpecial", checked)
        }

        SectionHeader {
            text: Tr.tr("Gaps and borders")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Custom gaps and borders")
            subtext: Tr.tr("Overrides your Hyprland config while the shell runs; off restores it")
            checked: WindowLayout.customGaps
            onToggled: WindowLayout.setCustomGaps(checked)
        }

        SliderRow {
            icon: "space_bar"
            label: Tr.tr("Gap between windows")
            valueLabel: root.px(WindowLayout.gapsIn)
            enabled: WindowLayout.customGaps
            value: WindowLayout.gapsIn / 40
            onMoved: v => WindowLayout.setOption("gapsIn", Math.round(v * 40))
        }

        SliderRow {
            icon: "fit_screen"
            label: Tr.tr("Gap to the screen edge")
            valueLabel: root.px(WindowLayout.gapsOut)
            enabled: WindowLayout.customGaps
            value: WindowLayout.gapsOut / 60
            onMoved: v => WindowLayout.setOption("gapsOut", Math.round(v * 60))
        }

        SliderRow {
            icon: "border_style"
            label: Tr.tr("Window border")
            valueLabel: root.px(WindowLayout.borderSize)
            enabled: WindowLayout.customGaps
            value: WindowLayout.borderSize / 8
            onMoved: v => WindowLayout.setOption("borderSize", Math.round(v * 8))
        }

        SliderRow {
            last: true
            icon: "rounded_corner"
            label: Tr.tr("Window corners")
            valueLabel: root.px(WindowLayout.rounding)
            enabled: WindowLayout.customGaps
            value: WindowLayout.rounding / 30
            onMoved: v => WindowLayout.setOption("rounding", Math.round(v * 30))
        }

        SectionHeader {
            text: Tr.tr("Shell frame")
        }

        SliderRow {
            first: true
            icon: "crop_square"
            label: Tr.tr("Frame thickness")
            valueLabel: root.px(Config.border.thickness)
            value: Config.border.thickness / 30
            onMoved: v => GlobalConfig.border.thickness = Math.max(Config.border.minThickness, Math.round(v * 30))
        }

        SliderRow {
            last: true
            icon: "rounded_corner"
            label: Tr.tr("Frame corners")
            valueLabel: root.px(Config.border.rounding)
            value: Config.border.rounding / 50
            onMoved: v => GlobalConfig.border.rounding = Math.round(v * 50)
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.large
            Layout.leftMargin: Tokens.padding.small
            wrapMode: Text.WordWrap
            text: Tr.tr("Tip: bind a key to %1 to switch between tiling and floating.").arg("caelestia shell windowMode toggle")
            font: Tokens.font.body.small
            color: Colours.palette.m3outline
        }
    }

    // A big card with a small picture of the mode.
    component ModeCard: StyledRect {
        id: card

        required property string mode
        required property string title
        required property string subtitle
        readonly property bool on: WindowLayout.mode === mode

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: content.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.extraLarge
        color: on ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainer
        border.width: on ? 2 : 0
        border.color: Colours.palette.m3primary

        Behavior on color {
            CAnim {}
        }

        StateLayer {
            radius: parent.radius
            disabled: !WindowLayout.available
            onClicked: WindowLayout.setMode(card.mode)
        }

        ColumnLayout {
            id: content

            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.small

            // Picture: a screen with windows
            StyledRect {
                Layout.fillWidth: true
                implicitHeight: 96
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainerHighest

                Item {
                    anchors.fill: parent
                    anchors.margins: 8
                    visible: card.mode === "tiling"

                    Win {
                        x: 0
                        y: 0
                        width: parent.width * 0.5 - 3
                        height: parent.height
                    }

                    Win {
                        x: parent.width * 0.5 + 3
                        y: 0
                        width: parent.width * 0.5 - 3
                        height: parent.height * 0.5 - 3
                    }

                    Win {
                        x: parent.width * 0.5 + 3
                        y: parent.height * 0.5 + 3
                        width: parent.width * 0.5 - 3
                        height: parent.height * 0.5 - 3
                    }
                }

                Item {
                    anchors.fill: parent
                    anchors.margins: 8
                    visible: card.mode === "floating"

                    Win {
                        x: parent.width * 0.08
                        y: parent.height * 0.08
                        width: parent.width * 0.55
                        height: parent.height * 0.62
                        bar: true
                    }

                    Win {
                        x: parent.width * 0.38
                        y: parent.height * 0.3
                        width: parent.width * 0.55
                        height: parent.height * 0.66
                        bar: true
                        front: true
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: card.title
                font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                color: card.on ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: card.subtitle
                font: Tokens.font.body.small
                color: card.on ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
            }
        }
    }

    component Win: StyledRect {
        property bool bar
        property bool front

        radius: Tokens.rounding.small
        color: front ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer
        opacity: front ? 0.9 : 1

        StyledRect {
            visible: parent.bar
            width: parent.width
            height: 8
            topLeftRadius: parent.radius
            topRightRadius: parent.radius
            color: parent.front ? Colours.palette.m3onPrimary : Colours.palette.m3secondary
            opacity: 0.5
        }
    }
}
