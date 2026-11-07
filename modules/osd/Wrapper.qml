pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property bool sidebarOrSessionVisible

    property bool hovered
    readonly property Brightness.Monitor monitor: Brightness.getMonitorForScreen(root.screen)
    readonly property bool shouldBeActive: screenState.osd && Config.osd.enabled && !(screenState.utilities && Config.utilities.enabled)
    property real offsetScale: shouldBeActive ? 0 : 1
    property real sidebarOffset: sidebarOrSessionVisible ? 12 : 0

    property real volume
    property bool muted
    property real sourceVolume
    property bool sourceMuted
    property real brightness
    property double sinkSwitchedAt

    function show(): void {
        screenState.osd = true;
        timer.restart();
    }

    Component.onCompleted: {
        volume = Audio.volume;
        muted = Audio.muted;
        sourceVolume = Audio.sourceVolume;
        sourceMuted = Audio.sourceMuted;
        brightness = root.monitor?.brightness ?? 0;
    }

    visible: offsetScale < 1
    anchors.rightMargin: (-implicitWidth - 5 - sidebarOffset) * offsetScale
    implicitWidth: content.implicitWidth
    implicitHeight: content.implicitHeight
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {}
    }

    // Only real changes open the OSD. PipeWire re-announces a device's volume when its stream
    // setup changes (an app or the visualiser starting to capture, the GPU's HDMI audio waking up),
    // which used to pop the volume slider open without anything having changed.
    Connections {
        function onMutedChanged(): void {
            if (Audio.muted !== root.muted && Date.now() - root.sinkSwitchedAt > 1500)
                root.show();
            root.muted = Audio.muted;
        }

        function onVolumeChanged(): void {
            if (Math.abs(Audio.volume - root.volume) > 0.005 && Date.now() - root.sinkSwitchedAt > 1500)
                root.show();
            root.volume = Audio.volume;
        }

        function onSourceMutedChanged(): void {
            if (Audio.sourceMuted !== root.sourceMuted)
                root.show();
            root.sourceMuted = Audio.sourceMuted;
        }

        function onSourceVolumeChanged(): void {
            if (Math.abs(Audio.sourceVolume - root.sourceVolume) > 0.005)
                root.show();
            root.sourceVolume = Audio.sourceVolume;
        }

        function onSinkChanged(): void {
            // Another output (or the same one coming back after a hiccup): take its values
            // without showing them.
            root.sinkSwitchedAt = Date.now();
            root.volume = Audio.volume;
            root.muted = Audio.muted;
        }

        target: Audio
    }

    Connections {
        function onBrightnessChanged(): void {
            root.show();
            root.brightness = root.monitor?.brightness ?? 0;
        }

        target: root.monitor
    }

    Timer {
        id: timer

        interval: root.Config.osd.hideDelay
        onTriggered: {
            if (!root.hovered)
                root.screenState.osd = false;
        }
    }

    Loader {
        id: content

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left

        asynchronous: true
        active: root.shouldBeActive || root.visible

        sourceComponent: Content {
            monitor: root.monitor
            screenState: root.screenState
            volume: root.volume
            muted: root.muted
            sourceVolume: root.sourceVolume
            sourceMuted: root.sourceMuted
            brightness: root.brightness
        }
    }
}
