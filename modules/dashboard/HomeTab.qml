pragma ComponentBehavior: Bound

import "home"
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// Dashboard "Home" tab: Home Assistant.
// Setup form -> tiles of the chosen devices -> editor (pencil button) to choose them.
Item {
    id: root

    required property ScreenState screenState
    property bool editing

    implicitWidth: 840
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2

    Component.onCompleted: HomeAssistant.refresh()

    // Ask the drawer window for keyboard focus while there is something to type into.
    // Released automatically when this tab is unloaded.
    Binding {
        target: root.screenState
        property: "dashboardInput"
        value: !HomeAssistant.connected || root.editing
        restoreMode: Binding.RestoreValue
    }

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                text: Tr.tr("Home")
                font: Tokens.font.body.builders.large.size(28).weight(Font.DemiBold).build()
                color: Colours.palette.m3onSurface
            }

            IconButton {
                visible: HomeAssistant.connected && root.editing
                type: IconButton.Text
                isRound: true
                icon: "logout"
                inactiveOnColour: Colours.palette.m3error
                onClicked: {
                    root.editing = false;
                    HomeAssistant.forget();
                }
            }

            IconButton {
                visible: HomeAssistant.connected
                type: root.editing ? IconButton.Filled : IconButton.Tonal
                isRound: true
                icon: root.editing ? "check" : "edit"
                onClicked: root.editing = !root.editing
            }
        }

        // Setup form (until a working connection exists)
        ColumnLayout {
            Layout.fillWidth: true
            visible: !HomeAssistant.connected
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: HomeAssistant.status === "loading" ? Tr.tr("Loading...") : Tr.tr("Enter your Home Assistant address and a long-lived access token (Profile → Security in Home Assistant). They are stored in your system keyring, never in a config file.")
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledTextField {
                id: urlField

                Layout.fillWidth: true
                placeholderText: Tr.tr("Address, e.g. http://homeassistant.local:8123")
                leadingIcon: "link"
                text: HomeAssistant.url
                enabled: HomeAssistant.status !== "connecting"
            }

            StyledTextField {
                id: tokenField

                Layout.fillWidth: true
                placeholderText: Tr.tr("Long-lived access token")
                leadingIcon: "key"
                echoMode: TextInput.Password
                enabled: HomeAssistant.status !== "connecting"

                onAccepted: HomeAssistant.connect(urlField.text, tokenField.text)
            }

            StyledText {
                Layout.fillWidth: true
                visible: HomeAssistant.status === "error"
                wrapMode: Text.WordWrap
                text: HomeAssistant.errorText
                font: Tokens.font.body.small
                color: Colours.palette.m3error
            }

            TextButton {
                Layout.alignment: Qt.AlignRight
                horizontalPadding: Tokens.padding.extraLarge
                type: TextButton.Filled
                text: HomeAssistant.status === "connecting" ? Tr.tr("Connecting...") : Tr.tr("Connect")
                disabled: HomeAssistant.status === "connecting"
                onClicked: HomeAssistant.connect(urlField.text, tokenField.text)
            }
        }

        // Tiles
        Flow {
            id: tiles

            Layout.fillWidth: true
            visible: HomeAssistant.connected && !root.editing
            spacing: Tokens.spacing.small

            Repeater {
                model: HomeAssistant.selected

                EntityTile {
                    required property string modelData

                    entityId: modelData
                }
            }

            add: Transition {
                Anim {
                    property: "opacity"
                    from: 0
                    to: 1
                }
                Anim {
                    property: "scale"
                    from: 0.85
                    to: 1
                    type: Anim.FastSpatial
                }
            }

            move: Transition {
                Anim {
                    properties: "x,y"
                    type: Anim.DefaultSpatial
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: HomeAssistant.connected && !root.editing && HomeAssistant.selected.length === 0
            wrapMode: Text.WordWrap
            text: Tr.tr("No devices yet. Tap the pencil to choose which ones appear here.")
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
        }

        // Editor
        EntityEditor {
            Layout.fillWidth: true
            visible: HomeAssistant.connected && root.editing
        }
    }
}
