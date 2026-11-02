pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    required property real nonAnimWidth
    required property ScreenState screenState
    required property var tabs

    readonly property int count: repeater.count

    signal customizeRequested

    implicitHeight: bar.implicitHeight + bar.anchors.topMargin + indicator.implicitHeight + indicator.anchors.topMargin + separator.implicitHeight

    // The tab buttons. A plain row (not a TabBar): each button knows its own index in the list, so
    // switching tabs on, off or moving them never leaves a button pointing at the wrong tab.
    RowLayout {
        id: bar

        readonly property Item currentItem: {
            repeater.count;
            root.tabs;
            return repeater.itemAt(root.screenState.dashboardTab);
        }

        anchors.left: parent.left
        anchors.right: customize.left
        anchors.rightMargin: Tokens.spacing.small
        anchors.top: parent.top
        anchors.topMargin: Tokens.sizes.dashboard.tabIndicatorSpacing
        spacing: 0

        Repeater {
            id: repeater

            model: root.tabs

            Tab {}
        }
    }

    IconButton {
        id: customize

        anchors.right: parent.right
        anchors.verticalCenter: bar.verticalCenter

        type: IconButton.Text
        isRound: true
        icon: "tune"
        inactiveOnColour: Colours.palette.m3onSurfaceVariant
        onClicked: root.customizeRequested()
    }

    Item {
        id: indicator

        anchors.top: bar.bottom
        anchors.topMargin: 5

        implicitWidth: bar.currentItem?.contentWidth ?? 0
        implicitHeight: 3

        x: {
            const tab = bar.currentItem;
            return tab ? bar.x + tab.x + (tab.width - tab.contentWidth) / 2 : 0;
        }

        clip: true

        StyledRect {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            implicitHeight: parent.implicitHeight * 2

            color: Colours.palette.m3primary
            radius: Tokens.rounding.full
        }

        Behavior on x {
            Anim {}
        }

        Behavior on implicitWidth {
            Anim {}
        }
    }

    StyledRect {
        id: separator

        anchors.top: indicator.bottom
        anchors.left: parent.left
        anchors.right: parent.right

        implicitHeight: 1
        color: Colours.palette.m3outlineVariant
    }

    component Tab: Item {
        id: tab

        required property var modelData
        required property int index
        readonly property bool current: root.screenState.dashboardTab === index
        readonly property real contentWidth: mouse.implicitWidth

        Layout.fillWidth: true
        Layout.preferredWidth: 1 // Uniform width across all tabs
        implicitWidth: mouse.implicitWidth
        implicitHeight: mouse.implicitHeight

        CustomMouseArea {
            id: mouse

            function onWheel(event: WheelEvent): void {
                if (event.angleDelta.y < 0)
                    root.screenState.dashboardTab = Math.min(root.screenState.dashboardTab + 1, root.count - 1);
                else if (event.angleDelta.y > 0)
                    root.screenState.dashboardTab = Math.max(root.screenState.dashboardTab - 1, 0);
            }

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            implicitWidth: Math.max(icon.width, label.width)
            implicitHeight: icon.height + label.height
            width: implicitWidth
            height: implicitHeight

            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onPressed: root.screenState.dashboardTab = tab.index

            StateLayer {
                id: stateLayer

                anchors.fill: undefined
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: tab.width
                implicitHeight: parent.height + Tokens.sizes.dashboard.tabIndicatorSpacing * 2

                radius: Tokens.rounding.medium
                color: tab.current ? Colours.palette.m3primary : Colours.palette.m3onSurface
                onClicked: root.screenState.dashboardTab = tab.index
            }

            MaterialIcon {
                id: icon

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: label.top

                text: tab.modelData.iconName
                color: tab.current ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                fill: tab.current ? 1 : 0
                fontStyle: Tokens.font.icon.medium

                Behavior on fill {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }

            StyledText {
                id: label

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom

                text: tab.modelData.text
                color: tab.current ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            }
        }
    }
}
