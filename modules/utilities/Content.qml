pragma ComponentBehavior: Bound

import "quick"
import QtQuick
import qs.components
import qs.modules.bar.popouts as BarPopouts

// KairosOS: the bottom-right panel is quick settings (see quick/QuickSettings.qml). The old cards
// (keep awake, screen recorder with its recordings list, quick toggle row) are tiles there now.
Item {
    id: root

    required property var props
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property matrix4x4 deformMatrix

    readonly property real nonAnimHeight: quick.implicitHeight

    implicitWidth: quick.implicitWidth
    implicitHeight: quick.implicitHeight

    QuickSettings {
        id: quick

        anchors.fill: parent
        screenState: root.screenState
    }
}
