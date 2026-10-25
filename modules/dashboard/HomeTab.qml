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
// Setup form -> tiles of the chosen devices. Edit mode works like the iOS Control Center:
// the tiles wiggle and can be dragged, resized (corner arc) and removed (minus badge),
// "+" and "Add a device" slide up the device gallery, "Done" leaves edit mode.
// Holding a tile starts edit mode too.
Item {
    id: root

    required property ScreenState screenState
    property bool editing
    property bool picking // device gallery open (only while editing)

    // The gallery needs room, however few tiles there are.
    implicitWidth: 840
    implicitHeight: Math.max(layout.implicitHeight, detail.open ? tiles.y + 400 : 0, picking ? 520 : 0) + Tokens.padding.large * 2

    onEditingChanged: {
        picking = false;
        detail.open = false;
    }
    Component.onCompleted: HomeAssistant.refresh()

    Behavior on implicitHeight {
        Anim {}
    }

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

            IconButton {
                visible: HomeAssistant.connected && root.editing
                type: IconButton.Tonal
                isRound: true
                icon: "add"
                onClicked: root.picking = true
            }

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
                visible: HomeAssistant.connected && !root.editing
                type: IconButton.Tonal
                isRound: true
                icon: "edit"
                onClicked: root.editing = true
            }

            TextButton {
                visible: HomeAssistant.connected && root.editing
                type: TextButton.Filled
                horizontalPadding: Tokens.padding.extraLarge
                text: Tr.tr("Done")
                onClicked: root.editing = false
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
            onEditRequested: root.editing = true
        }

        // Nothing chosen yet
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.padding.large
            visible: HomeAssistant.connected && !root.editing && HomeAssistant.selected.length === 0
            spacing: Tokens.spacing.small

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: "home"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.extraLarge
                opacity: 0.6
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Tr.tr("No devices yet")
                font: Tokens.font.body.medium
                color: Colours.palette.m3onSurfaceVariant
            }

            TextButton {
                Layout.alignment: Qt.AlignHCenter
                type: TextButton.Filled
                horizontalPadding: Tokens.padding.extraLarge
                text: Tr.tr("Add devices")
                onClicked: {
                    root.editing = true;
                    root.picking = true;
                }
            }
        }

        // Edit mode: opens the gallery
        IconTextButton {
            Layout.alignment: Qt.AlignHCenter
            visible: HomeAssistant.connected && root.editing
            type: IconTextButton.Tonal
            horizontalPadding: Tokens.padding.extraLarge
            icon: "add"
            text: Tr.tr("Add a device")
            onClicked: root.picking = true
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

    // Device gallery: slides up over the tab, like the iOS "Add a Control" sheet.
    Item {
        id: sheet

        property real prog: root.picking ? 1 : 0

        anchors.fill: parent
        z: 20
        visible: prog > 0

        Behavior on prog {
            Anim {
                type: Anim.DefaultSpatial
            }
        }

        // Scrim: tap outside to close.
        StyledRect {
            anchors.fill: parent
            radius: Tokens.rounding.large
            color: Colours.palette.m3scrim
            opacity: 0.35 * sheet.prog

            MouseArea {
                anchors.fill: parent
                enabled: root.picking
                onClicked: root.picking = false
            }
        }

        StyledRect {
            x: 0
            y: sheet.height - height * sheet.prog
            width: sheet.width
            height: sheet.height - Tokens.padding.extraLarge
            topLeftRadius: Tokens.rounding.extraLarge
            topRightRadius: Tokens.rounding.extraLarge
            color: Colours.palette.m3surfaceContainerHigh

            // Keeps taps on the sheet itself from reaching the scrim.
            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.small

                StyledRect {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 36
                    implicitHeight: 4
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3outlineVariant
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        text: Tr.tr("Add a device")
                        font: Tokens.font.body.builders.large.size(22).weight(Font.DemiBold).build()
                        color: Colours.palette.m3onSurface
                    }

                    IconButton {
                        type: IconButton.Tonal
                        isRound: true
                        icon: "close"
                        onClicked: root.picking = false
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    active: root.picking || sheet.prog > 0

                    sourceComponent: DeviceGallery {}
                }
            }
        }
    }
}
