pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// The "Dashboard" tab: widgets on a grid. Edit mode works like on the iOS home screen and like the
// Home tab: widgets wiggle and can be dragged, resized (corner arc) and removed (minus badge), "+"
// opens the widget gallery and "Done" leaves edit mode. Holding a widget starts edit mode too.
Item {
    id: root

    property bool editing
    property bool picking // widget gallery open (only while editing)

    // Room for the gallery however few widgets there are.
    implicitWidth: 840
    implicitHeight: Math.max(layout.implicitHeight, picking ? 520 : 0) + Tokens.padding.large * 2

    onEditingChanged: picking = false

    Behavior on implicitHeight {
        Anim {}
    }

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            IconButton {
                visible: root.editing
                type: IconButton.Tonal
                isRound: true
                icon: "add"
                onClicked: root.picking = true
            }

            StyledText {
                Layout.fillWidth: true
                text: Tr.tr("Dashboard")
                font: Tokens.font.body.builders.large.size(28).weight(Font.DemiBold).build()
                color: Colours.palette.m3onSurface
            }

            TextButton {
                visible: root.editing
                type: TextButton.Text
                text: Tr.tr("Reset")
                onClicked: DashboardWidgets.reset()
            }

            IconButton {
                visible: !root.editing
                type: IconButton.Tonal
                isRound: true
                icon: "edit"
                onClicked: root.editing = true
            }

            TextButton {
                visible: root.editing
                type: TextButton.Filled
                horizontalPadding: Tokens.padding.extraLarge
                text: Tr.tr("Done")
                onClicked: root.editing = false
            }
        }

        WidgetGrid {
            Layout.fillWidth: true
            editing: root.editing
            onEditRequested: root.editing = true
        }

        // Nothing on the board
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.padding.large
            visible: DashboardWidgets.widgets.length === 0
            spacing: Tokens.spacing.small

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: "widgets"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.extraLarge
                opacity: 0.6
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Tr.tr("No widgets yet")
                font: Tokens.font.body.medium
                color: Colours.palette.m3onSurfaceVariant
            }

            TextButton {
                Layout.alignment: Qt.AlignHCenter
                type: TextButton.Filled
                horizontalPadding: Tokens.padding.extraLarge
                text: Tr.tr("Add widgets")
                onClicked: {
                    root.editing = true;
                    root.picking = true;
                }
            }
        }

        IconTextButton {
            Layout.alignment: Qt.AlignHCenter
            visible: root.editing && DashboardWidgets.widgets.length > 0
            type: IconTextButton.Tonal
            horizontalPadding: Tokens.padding.extraLarge
            icon: "add"
            text: Tr.tr("Add a widget")
            onClicked: root.picking = true
        }
    }

    Sheet {
        open: root.picking
        title: Tr.tr("Add a widget")
        onClosed: root.picking = false

        WidgetGallery {
            Layout.fillWidth: true
            Layout.fillHeight: true
            onAdded: root.picking = false
        }
    }
}
