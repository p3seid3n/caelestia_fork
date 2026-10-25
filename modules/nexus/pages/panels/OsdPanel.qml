import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.modules.nexus.common

// Settings → Panels → On-screen display: the volume / brightness popup.
PageBase {
    id: root

    title: Tr.tr("On-screen display")
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
            subtext: Tr.tr("Show a popup when the volume or brightness changes")
            checked: Config.osd.enabled
            onToggled: GlobalConfig.osd.enabled = checked
        }

        StepperRow {
            last: true
            label: Tr.tr("Hide after (seconds)")
            subtext: Tr.tr("How long the popup stays after the last change")
            from: 0.5
            to: 10
            stepSize: 0.5
            value: Config.osd.hideDelay / 1000
            onMoved: v => GlobalConfig.osd.hideDelay = Math.round(v * 1000)
        }

        SectionHeader {
            text: Tr.tr("Shown for")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Brightness")
            subtext: Tr.tr("Screen brightness keys")
            disabled: !Config.osd.enabled
            checked: Config.osd.enableBrightness
            onToggled: GlobalConfig.osd.enableBrightness = checked
        }

        ToggleRow {
            last: true
            text: Tr.tr("Microphone")
            subtext: Tr.tr("Microphone volume and mute")
            disabled: !Config.osd.enabled
            checked: Config.osd.enableMicrophone
            onToggled: GlobalConfig.osd.enableMicrophone = checked
        }
    }
}
