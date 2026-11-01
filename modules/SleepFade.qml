pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components.containers
import qs.services

// The black that screens fade into before they sleep and out of when they wake
// (services/ScreenSleep.qml). Only exists while it is needed and takes no input.
// The lock screen is above every window like this, so it draws the same black itself.
Scope {
    LazyLoader {
        active: ScreenSleep.cover > 0

        Variants {
            model: Quickshell.screens

            StyledWindow {
                required property ShellScreen modelData

                screen: modelData
                name: "sleep-fade"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                mask: Region {}

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                Rectangle {
                    anchors.fill: parent
                    color: "black"
                    opacity: ScreenSleep.cover
                }
            }
        }
    }
}
