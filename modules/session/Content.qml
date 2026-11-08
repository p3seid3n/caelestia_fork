pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services
import qs.utils

// KairosOS power menu: sleep, restart, restart into Windows, shut down. Icons only.
// Mouse and keyboard share one focus (hovering a button focuses it), so the highlighted button
// is always the one Enter or a click runs. The buttons come in one after another and the
// focused one morphs from a rounded square into a pill.
Column {
    id: root

    required property ScreenState screenState
    // Drives the staggered entrance (1 while the menu is open).
    property real shown: 0

    function runWindows(): void {
        windowsProc.running = true;
    }

    padding: Tokens.padding.large
    rightPadding: CUtils.clamp(padding - Config.border.thickness, 0, padding)
    spacing: Tokens.spacing.normal

    Component.onCompleted: {
        shown = 1;
        sleep.forceActiveFocus();
    }

    Behavior on shown {
        Anim {
            type: Anim.SlowSpatial
        }
    }

    Connections {
        function onSessionChanged(): void {
            root.shown = root.screenState.session ? 1 : 0;
            if (root.screenState.session)
                sleep.forceActiveFocus();
        }

        function onLauncherChanged(): void {
            if (!root.screenState.launcher && root.screenState.session)
                sleep.forceActiveFocus();
        }

        target: root.screenState
    }

    // One-time setup: sudo ~/caelestia_fork/scripts/install-reboot-windows.sh
    Process {
        id: windowsProc

        command: ["sh", "-c", "sudo -n /usr/local/bin/kairos-reboot-windows 2>/dev/null || pkexec /usr/local/bin/kairos-reboot-windows"]
        stderr: StdioCollector {
            id: windowsErr
        }
        onExited: code => {
            if (code === 0)
                return;
            const why = windowsErr.text.trim().split("\n").pop();
            Toaster.toast(Tr.tr("Restart into Windows"), why || Tr.tr("Run scripts/install-reboot-windows.sh once to set it up."), "error");
        }
    }

    SessionButton {
        id: sleep

        index: 0
        icon: "bedtime"
        command: ["suspend"]

        KeyNavigation.down: restart
    }

    SessionButton {
        id: restart

        index: 1
        icon: "restart_alt"
        command: Config.session.commands.reboot

        KeyNavigation.up: sleep
        KeyNavigation.down: windows
    }

    SessionButton {
        id: windows

        index: 2
        tone: "tertiary"
        onRun: root.runWindows()

        KeyNavigation.up: restart
        KeyNavigation.down: shutdown

        // Windows logo: four squares with a small gap, coloured like an icon.
        Grid {
            anchors.centerIn: parent
            columns: 2
            spacing: 2.5

            Repeater {
                model: 4

                Rectangle {
                    implicitWidth: 13.5
                    implicitHeight: 13.5
                    radius: 1.5
                    color: windows.onColour
                }
            }
        }
    }

    SessionButton {
        id: shutdown

        index: 3
        tone: "error"
        icon: "power_settings_new"
        command: Config.session.commands.shutdown

        KeyNavigation.up: windows
    }

    component SessionButton: IconButton {
        id: button

        required property int index
        property list<string> command
        // Colour when focused: "secondary" (default), "tertiary" or "error".
        property string tone: "secondary"
        // Where this button is in the staggered entrance (0 hidden .. 1 in place).
        readonly property real enter: CUtils.clamp(root.shown * 1.6 - index * 0.2, 0, 1)

        signal run

        function exec(): void {
            if (command.length === 0) {
                run();
                return;
            }
            if (!SessionManager.exec(command))
                Quickshell.execDetached(command);
        }

        implicitWidth: Tokens.sizes.session.button
        implicitHeight: Tokens.sizes.session.button

        opacity: enter
        scale: 0.7 + 0.3 * enter
        transform: Translate {
            x: (1 - button.enter) * 36
        }

        inactiveColour: {
            if (!activeFocus)
                return Colours.tPalette.m3surfaceContainer;
            if (tone === "error")
                return Colours.palette.m3errorContainer;
            if (tone === "tertiary")
                return Colours.palette.m3tertiaryContainer;
            return Colours.palette.m3secondaryContainer;
        }
        inactiveOnColour: {
            if (!activeFocus)
                return Colours.palette.m3onSurface;
            if (tone === "error")
                return Colours.palette.m3onErrorContainer;
            if (tone === "tertiary")
                return Colours.palette.m3onTertiaryContainer;
            return Colours.palette.m3onSecondaryContainer;
        }
        // Rounded square at rest, a full circle when focused, squashed while pressed.
        radius: pressed ? Tokens.rounding.medium : activeFocus ? implicitHeight / 2 : Tokens.rounding.largeIncreased
        font: Tokens.font.icon.builders.large.scale(1.3).build()
        onClicked: exec()
        onHoveredChanged: {
            if (hovered)
                forceActiveFocus();
        }

        Keys.onEnterPressed: exec()
        Keys.onReturnPressed: exec()
        Keys.onEscapePressed: root.screenState.session = false
        Keys.onPressed: event => {
            if (!Config.session.vimKeybinds)
                return;

            if (event.modifiers & Qt.ControlModifier) {
                if ((event.key === Qt.Key_J || event.key === Qt.Key_N) && KeyNavigation.down) {
                    KeyNavigation.down.focus = true;
                    event.accepted = true;
                } else if ((event.key === Qt.Key_K || event.key === Qt.Key_P) && KeyNavigation.up) {
                    KeyNavigation.up.focus = true;
                    event.accepted = true;
                }
            } else if (event.key === Qt.Key_Tab && KeyNavigation.down) {
                KeyNavigation.down.focus = true;
                event.accepted = true;
            } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                if (KeyNavigation.up) {
                    KeyNavigation.up.focus = true;
                    event.accepted = true;
                }
            }
        }
    }
}
