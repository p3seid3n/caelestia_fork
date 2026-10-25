import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.modules.nexus.common

// Settings → Panels → Session menu: the logout / shutdown / reboot menu.
PageBase {
    id: root

    title: Tr.tr("Session menu")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: Tr.tr("General")
        }

        ToggleRow {
            first: true
            text: Tr.trCtx("Enabled", "toggle label")
            subtext: Tr.tr("Show the session menu at the right edge of the screen")
            checked: Config.session.enabled
            onToggled: GlobalConfig.session.enabled = checked
        }

        StepperRow {
            label: Tr.tr("Drag distance (px)")
            subtext: Tr.tr("How far to drag from the edge to open it")
            from: 0
            to: 200
            stepSize: 5
            value: Config.session.dragThreshold
            onMoved: v => GlobalConfig.session.dragThreshold = Math.round(v)
        }

        ToggleRow {
            last: true
            text: Tr.tr("Vim keys")
            subtext: Tr.tr("Move between the buttons with h, j, k and l")
            checked: Config.session.vimKeybinds
            onToggled: GlobalConfig.session.vimKeybinds = checked
        }
    }
}
