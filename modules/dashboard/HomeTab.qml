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
    property bool picking // device list open while editing

    onEditingChanged: {
        picking = false;
        detail.open = false;
    }

    implicitWidth: 840
    implicitHeight: Math.max(layout.implicitHeight, detail.open ? tiles.y + 400 : 0) + Tokens.padding.large * 2

    Behavior on implicitHeight {
        Anim {}
    }

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

        // Tiles (also shown while editing: they wiggle and can be moved/resized)
        TileGrid {
            id: tiles

            Layout.fillWidth: true
            visible: HomeAssistant.connected
            editing: root.editing
            onExpand: (id, from) => detail.show(id, from)
        }

        StyledText {
            Layout.fillWidth: true
            visible: HomeAssistant.connected && !root.editing && HomeAssistant.selected.length === 0
            wrapMode: Text.WordWrap
            text: Tr.tr("No devices yet. Tap the pencil to choose which ones appear here.")
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
        }

        // Edit mode: add / remove devices
        TextButton {
            Layout.alignment: Qt.AlignHCenter
            visible: HomeAssistant.connected && root.editing
            type: root.picking ? TextButton.Filled : TextButton.Tonal
            horizontalPadding: Tokens.padding.extraLarge
            text: root.picking ? Tr.tr("Done adding") : Tr.tr("Add devices")
            onClicked: root.picking = !root.picking
        }

        EntityEditor {
            Layout.fillWidth: true
            visible: HomeAssistant.connected && root.editing && root.picking
        }
    }

    // Full view of a tapped tile, over the grid.
    EntityDetail {
        id: detail

        x: tiles.x + layout.x
        y: tiles.y + layout.y
        width: tiles.width
        height: 400
        z: 10

        // `from` arrives in grid coordinates, which is what this item uses too.
    }
}
