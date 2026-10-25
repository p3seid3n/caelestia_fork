pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.sidebar as Sidebar

// The notification centre drawer in the top right corner. Slides down from the top edge like the
// dashboard and joins the shell's frame like every drawer (its blob is in drawers/ContentWindow).
Item {
    id: root

    required property ScreenState screenState
    readonly property Sidebar.Props props: Sidebar.Props {
        reloadableId: "notifCentre"
    }

    readonly property bool shouldBeActive: screenState.notifCentre && NotifCentre.enabled
    property real offsetScale: shouldBeActive ? 0 : 1
    readonly property real maxHeight: ((QsWindow.window as QsWindow)?.screen?.height ?? 1080) * 0.7

    visible: offsetScale < 1
    anchors.topMargin: (-implicitHeight - 5) * offsetScale
    implicitWidth: Math.max(Tokens.sizes.notifs.width, 400) + Tokens.padding.large * 2
    implicitHeight: content.implicitHeight + Tokens.padding.large + CUtils.clamp(Tokens.padding.large - Config.border.thickness, 0, Tokens.padding.large)
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {}
    }

    Loader {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Tokens.padding.large
        anchors.rightMargin: CUtils.clamp(Tokens.padding.large - Config.border.thickness, 0, Tokens.padding.large)
        anchors.bottomMargin: Tokens.padding.large

        active: root.shouldBeActive || root.visible

        sourceComponent: Content {
            screenState: root.screenState
            props: root.props
            maxHeight: root.maxHeight
        }
    }
}
