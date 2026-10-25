pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components.controls
import qs.modules.nexus.common

// Settings → Panels → Desktop: the clock and the audio visualiser on the wallpaper.
PageBase {
    id: root

    readonly property list<MenuItem> positionItems: [
        MenuItem {
            text: Tr.tr("Top left")
            value: "top-left"
        },
        MenuItem {
            text: Tr.tr("Top centre")
            value: "top-center"
        },
        MenuItem {
            text: Tr.tr("Top right")
            value: "top-right"
        },
        MenuItem {
            text: Tr.tr("Middle left")
            value: "middle-left"
        },
        MenuItem {
            text: Tr.tr("Centre")
            value: "middle-center"
        },
        MenuItem {
            text: Tr.tr("Middle right")
            value: "middle-right"
        },
        MenuItem {
            text: Tr.tr("Bottom left")
            value: "bottom-left"
        },
        MenuItem {
            text: Tr.tr("Bottom centre")
            value: "bottom-center"
        },
        MenuItem {
            text: Tr.tr("Bottom right")
            value: "bottom-right"
        }
    ]

    title: Tr.tr("Desktop")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: Tr.tr("Clock")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Desktop clock")
            subtext: Tr.tr("A big clock on the wallpaper")
            checked: Config.background.desktopClock.enabled
            onToggled: GlobalConfig.background.desktopClock.enabled = checked
        }

        SelectRow {
            label: Tr.tr("Position")
            menuItems: root.positionItems
            active: root.positionItems.find(i => i.value === Config.background.desktopClock.position) ?? null
            onSelected: item => GlobalConfig.background.desktopClock.position = item.value
        }

        SliderRow {
            icon: "format_size"
            label: Tr.tr("Size")
            valueLabel: Math.round(Config.background.desktopClock.scale * 100) + " %"
            enabled: Config.background.desktopClock.enabled
            // 50 % ... 250 %
            value: (Config.background.desktopClock.scale - 0.5) / 2
            onMoved: v => GlobalConfig.background.desktopClock.scale = Math.round((0.5 + v * 2) * 20) / 20
        }

        ToggleRow {
            text: Tr.tr("Invert colours")
            subtext: Tr.tr("For light wallpapers")
            disabled: !Config.background.desktopClock.enabled
            checked: Config.background.desktopClock.invertColors
            onToggled: GlobalConfig.background.desktopClock.invertColors = checked
        }

        ToggleRow {
            text: Tr.tr("Background")
            subtext: Tr.tr("A blurred card behind the clock")
            disabled: !Config.background.desktopClock.enabled
            checked: Config.background.desktopClock.background.enabled
            onToggled: GlobalConfig.background.desktopClock.background.enabled = checked
        }

        ToggleRow {
            last: true
            text: Tr.tr("Shadow")
            subtext: Tr.tr("A soft shadow under the clock")
            disabled: !Config.background.desktopClock.enabled
            checked: Config.background.desktopClock.shadow.enabled
            onToggled: GlobalConfig.background.desktopClock.shadow.enabled = checked
        }

        SectionHeader {
            text: Tr.tr("Audio visualiser")
        }

        ToggleRow {
            first: true
            text: Tr.trCtx("Enabled", "toggle label")
            subtext: Tr.tr("Bars on the wallpaper that move with the music")
            checked: Config.background.visualiser.enabled
            onToggled: GlobalConfig.background.visualiser.enabled = checked
        }

        ToggleRow {
            text: Tr.tr("Hide when windows are open")
            disabled: !Config.background.visualiser.enabled
            checked: Config.background.visualiser.autoHide
            onToggled: GlobalConfig.background.visualiser.autoHide = checked
        }

        ToggleRow {
            last: true
            text: Tr.tr("Blur")
            disabled: !Config.background.visualiser.enabled
            checked: Config.background.visualiser.blur
            onToggled: GlobalConfig.background.visualiser.blur = checked
        }
    }
}
