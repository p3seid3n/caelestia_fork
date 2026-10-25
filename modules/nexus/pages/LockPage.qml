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

// Settings → Lock screen: the KairosOS always-on lock (or Caelestia's original), what it shows
// when awake, and how it unlocks. Written to ~/.config/caelestia/kairos-lock.json
// (services/LockStyle.qml) and the shell config (lock section).
PageBase {
    id: root

    readonly property list<MenuItem> styleItems: [
        MenuItem {
            text: Tr.tr("KairosOS (always-on clock)")
            value: "kairos"
        },
        MenuItem {
            text: Tr.tr("Caelestia")
            value: "caelestia"
        }
    ]

    function validColour(text: string): bool {
        return text === "" || /^#([0-9a-f]{6}|[0-9a-f]{8})$/i.test(text);
    }

    title: Tr.tr("Lock screen")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: Tr.tr("Style")
        }

        SelectRow {
            first: true
            label: Tr.tr("Lock screen")
            subtext: Tr.tr("The black always-on clock that wakes into a password bar, or Caelestia's own")
            menuItems: root.styleItems
            active: root.styleItems.find(i => i.value === LockStyle.style) ?? root.styleItems[0]
            onSelected: item => LockStyle.setOption("style", item.value)
        }

        ToggleRow {
            text: Tr.trCtx("Enabled", "toggle label")
            subtext: Tr.tr("Lock the screen when asked to (shortcut, idle, before sleep)")
            checked: Config.lock.enabled
            onToggled: GlobalConfig.lock.enabled = checked
        }

        RowButton {
            last: true
            icon: "lock"
            text: Tr.tr("Lock now")
            subtext: Tr.tr("See how it looks")
            onClicked: Quickshell.execDetached(["qs", "-p", Quickshell.shellDir, "ipc", "call", "lock", "lock"])
        }

        // AoD
        SectionHeader {
            visible: LockStyle.kairos
            text: Tr.tr("Always-on clock")
        }

        StepperRow {
            visible: LockStyle.kairos
            first: true
            label: Tr.tr("Back to the clock after (seconds)")
            subtext: Tr.tr("Without typing or moving the pointer")
            from: 5
            to: 300
            stepSize: 5
            value: LockStyle.aodTimeout
            onMoved: v => LockStyle.setOption("aodTimeout", Math.round(v))
        }

        ToggleRow {
            visible: LockStyle.kairos
            last: true
            text: Tr.tr("Move the clock now and then")
            subtext: Tr.tr("A few pixels every minute, against burn-in on OLED screens")
            checked: LockStyle.drift
            onToggled: LockStyle.setOption("drift", checked)
        }

        // Awake
        SectionHeader {
            visible: LockStyle.kairos
            text: Tr.tr("When awake")
        }

        ToggleRow {
            visible: LockStyle.kairos
            first: true
            text: Tr.tr("Blurred wallpaper")
            subtext: Tr.tr("Behind the clock once the screen wakes; the always-on clock stays on black")
            checked: LockStyle.wallpaperWhenAwake
            onToggled: LockStyle.setOption("wallpaperWhenAwake", checked)
        }

        ToggleRow {
            visible: LockStyle.kairos
            text: Tr.tr("Music")
            subtext: Tr.tr("What is playing, with previous, play and next")
            checked: LockStyle.showMedia
            onToggled: LockStyle.setOption("showMedia", checked)
        }

        ToggleRow {
            visible: LockStyle.kairos
            text: Tr.tr("Notifications")
            subtext: Tr.tr("The three latest notifications")
            checked: LockStyle.showNotifications
            onToggled: LockStyle.setOption("showNotifications", checked)
        }

        ToggleRow {
            text: Tr.tr("Hide what notifications say")
            subtext: Tr.tr("Only show how many there are until unlocked")
            checked: Config.lock.hideNotifs
            onToggled: GlobalConfig.lock.hideNotifs = checked
        }

        ToggleRow {
            visible: LockStyle.kairos
            last: true
            text: Tr.tr("Sleep, restart and shut down")
            subtext: Tr.tr("Buttons in the bottom right corner; restart and shut down ask twice")
            checked: LockStyle.powerButtons
            onToggled: LockStyle.setOption("powerButtons", checked)
        }

        // Unlocking
        SectionHeader {
            text: Tr.tr("Unlocking")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Face unlock (Howdy)")
            subtext: Tr.tr("Needs Howdy set up for your user")
            checked: Config.lock.enableHowdy
            onToggled: GlobalConfig.lock.enableHowdy = checked
        }

        ToggleRow {
            text: Tr.tr("Look for a face as soon as the screen wakes")
            subtext: Tr.tr("When woken with the mouse; typing goes to the password")
            disabled: !Config.lock.enableHowdy || !LockStyle.kairos
            checked: LockStyle.faceOnWake
            onToggled: LockStyle.setOption("faceOnWake", checked)
        }

        ToggleRow {
            last: true
            text: Tr.tr("Fingerprint")
            subtext: Tr.tr("Needs fprintd with an enrolled finger")
            checked: Config.lock.enableFprint
            onToggled: GlobalConfig.lock.enableFprint = checked
        }

        // Colours
        SectionHeader {
            visible: LockStyle.kairos
            text: Tr.tr("Colours")
        }

        TextFieldRow {
            visible: LockStyle.kairos
            first: true
            label: Tr.tr("Hours")
            subtext: Tr.tr("A colour like #F7D51D; empty uses the wallpaper's colours")
            value: LockStyle.hourColour
            placeholderText: Tr.tr("Theme colour")
            validate: /^$|^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/
            errorText: Tr.tr("Use #RRGGBB")
            onEditingFinished: value => {
                if (root.validColour(value.trim()))
                    LockStyle.setOption("hourColour", value.trim());
            }
        }

        TextFieldRow {
            visible: LockStyle.kairos
            label: Tr.tr("Minutes")
            value: LockStyle.minuteColour
            placeholderText: Tr.tr("Theme colour")
            validate: /^$|^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/
            errorText: Tr.tr("Use #RRGGBB")
            onEditingFinished: value => {
                if (root.validColour(value.trim()))
                    LockStyle.setOption("minuteColour", value.trim());
            }
        }

        TextFieldRow {
            visible: LockStyle.kairos
            last: true
            label: Tr.tr("Date and password bar")
            value: LockStyle.accentColour
            placeholderText: Tr.tr("Theme colour")
            validate: /^$|^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/
            errorText: Tr.tr("Use #RRGGBB")
            onEditingFinished: value => {
                if (root.validColour(value.trim()))
                    LockStyle.setOption("accentColour", value.trim());
            }
        }
    }
}
