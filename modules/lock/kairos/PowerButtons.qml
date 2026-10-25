pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// Sleep, restart and shut down on the lock screen. Restart and shut down ask for a second click
// (the button turns red and says what it will do), so a stray click cannot end the session.
Row {
    id: root

    property string armed

    spacing: Tokens.spacing.small

    Timer {
        id: disarm

        interval: 3500
        onTriggered: root.armed = ""
    }

    Repeater {
        model: [
            {
                key: "sleep",
                icon: "bedtime",
                label: Tr.tr("Sleep"),
                confirm: false,
                command: ["systemctl", "suspend"]
            },
            {
                key: "reboot",
                icon: Config.session.icons.reboot,
                label: Tr.tr("Restart?"),
                confirm: true,
                command: Config.session.commands.reboot
            },
            {
                key: "shutdown",
                icon: Config.session.icons.shutdown,
                label: Tr.tr("Shut down?"),
                confirm: true,
                command: Config.session.commands.shutdown
            }
        ]

        IconTextButton {
            id: button

            required property var modelData
            readonly property bool isArmed: root.armed === modelData.key

            type: isArmed ? IconTextButton.Filled : IconTextButton.Tonal
            icon: modelData.icon
            text: isArmed ? modelData.label : ""
            spacing: isArmed ? Tokens.spacing.small : 0
            activeColour: Colours.palette.m3error
            inactiveColour: isArmed ? Colours.palette.m3error : Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.85)
            inactiveOnColour: isArmed ? Colours.palette.m3onError : Colours.palette.m3onSurface
            onClicked: {
                if (modelData.confirm && !isArmed) {
                    root.armed = modelData.key;
                    disarm.restart();
                    return;
                }
                root.armed = "";
                Quickshell.execDetached(modelData.command);
            }
        }
    }
}
