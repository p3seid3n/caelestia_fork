pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus
import qs.modules.sidebar as Sidebar

// Inside the notification centre: Do not disturb and settings on top, then the notifications grouped
// by app (the same list as the sidebar's), sized to fit up to `maxHeight`.
ColumnLayout {
    id: root

    required property ScreenState screenState
    required property Sidebar.Props props
    required property real maxHeight

    spacing: Tokens.spacing.small

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            text: Tr.tr("Notifications")
            font: Tokens.font.title.small
            color: Colours.palette.m3onSurface
        }

        IconTextButton {
            type: IconTextButton.Tonal
            checked: Notifs.dnd
            icon: Notifs.dnd ? "notifications_off" : "notifications_active"
            text: Tr.tr("Do not disturb")
            onClicked: Notifs.dnd = !Notifs.dnd
        }

        IconButton {
            type: IconButton.Text
            isRound: true
            icon: "settings"
            onClicked: {
                root.screenState.notifCentre = false;
                WindowFactory.create();
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.padding.small
        visible: NotifCentre.conflict
        wrapMode: Text.WordWrap
        text: Tr.tr("%1 is taking the notifications, so none arrive here. Fix it in Settings → Services → Notifications.").arg(NotifCentre.owner)
        font: Tokens.font.body.small
        color: Colours.palette.m3error
    }

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: Math.max(Notifs.notClosed.length > 0 ? 180 : 320, Math.min(root.maxHeight, dock.contentHeight))
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainerLow

        Behavior on implicitHeight {
            Anim {}
        }

        Sidebar.NotifDock {
            id: dock

            props: root.props
            screenState: root.screenState
        }
    }
}
