pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Widgets
import Quickshell.Services.UPower
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus

// Quick settings (bottom-right panel), laid out like a phone's control centre:
//   header     battery, date, settings and power
//   row 1      Wi-Fi and Bluetooth as large tiles | what is playing (or the time)
//   row 2      round toggles (focus, night light, keep awake, game mode, floating windows, dark
//              mode, microphone, screen recording, VPN) | brightness and volume as tall sliders
//   row 3      Super devices: this PC with its phones, earbuds and other devices around it
// Only built while the panel is open (utilities/Wrapper.qml); nothing here polls on its own.
ColumnLayout {
    id: root

    required property ScreenState screenState

    readonly property var monitor: Brightness.getMonitorForScreen(screenState.modelData)
    readonly property var btAdapter: Bluetooth.defaultAdapter // qmllint disable unresolved-type
    readonly property var btConnected: Bluetooth.devices.values.filter(d => d.connected) // qmllint disable unresolved-type
    readonly property real sliderWidth: 64

    function closeAnd(action: var): void {
        root.screenState.utilities = false;
        action();
    }

    spacing: Tokens.spacing.medium

    // --- Header ---------------------------------------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.padding.small
        spacing: Tokens.spacing.small

        StyledRect {
            visible: UPower.displayDevice.isLaptopBattery
            implicitWidth: batteryRow.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: batteryRow.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.full
            color: UPower.displayDevice.percentage < 0.15 ? Colours.palette.m3errorContainer : Colours.tPalette.m3surfaceContainerHigh

            Row {
                id: batteryRow

                anchors.centerIn: parent
                spacing: Tokens.spacing.extraSmall

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Icons.getBatteryIcon(UPower.displayDevice.percentage, [UPowerDeviceState.Charging, UPowerDeviceState.FullyCharged, UPowerDeviceState.PendingCharge].includes(UPower.displayDevice.state))
                    color: Colours.palette.m3onSurface
                    fontStyle: Tokens.font.icon.small
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: `${Math.round(UPower.displayDevice.percentage * 100)}%`
                    font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                    color: Colours.palette.m3onSurface
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: {
                Time.hours;
                return new Date().toLocaleDateString(Qt.locale(), "dddd, d MMMM");
            }
            font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
            color: Colours.palette.m3onSurfaceVariant
        }

        IconButton {
            type: IconButton.Text
            isRound: true
            icon: "settings"
            onClicked: root.closeAnd(() => WindowFactory.create())
        }

        IconButton {
            type: IconButton.Tonal
            isRound: true
            icon: "power_settings_new"
            onClicked: root.closeAnd(() => root.screenState.session = true)
        }
    }

    // --- Row 1: connectivity and media ----------------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 3
            spacing: Tokens.spacing.small

            BigTile {
                icon: Nmcli.wifiEnabled ? "wifi" : "wifi_off"
                label: Tr.tr("Wi-Fi")
                sub: {
                    if (!Nmcli.wifiEnabled)
                        return Nmcli.activeEthernet ? Tr.tr("Ethernet") : Tr.tr("Off");
                    return Nmcli.active?.ssid ?? (Nmcli.activeEthernet ? Tr.tr("Ethernet") : Tr.tr("Not connected"));
                }
                checked: Nmcli.wifiEnabled
                onClicked: Nmcli.toggleWifi()
            }

            BigTile {
                icon: root.btAdapter?.enabled ? "bluetooth" : "bluetooth_disabled"
                label: Tr.tr("Bluetooth")
                sub: {
                    if (!root.btAdapter?.enabled)
                        return Tr.tr("Off");
                    if (root.btConnected.length === 1)
                        return root.btConnected[0].name;
                    if (root.btConnected.length > 1)
                        return Tr.trN("%n device", "%n devices", root.btConnected.length);
                    return Tr.tr("On");
                }
                checked: root.btAdapter?.enabled ?? false
                onClicked: {
                    if (root.btAdapter)
                        root.btAdapter.enabled = !root.btAdapter.enabled;
                }
            }
        }

        MediaCard {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 2
        }
    }

    // --- Row 2: toggles and sliders ---------------------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        GridLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            columns: 4
            columnSpacing: Tokens.spacing.small
            rowSpacing: Tokens.spacing.small

            RoundToggle {
                icon: "do_not_disturb_on"
                label: Tr.tr("Focus")
                checked: Notifs.dnd
                onClicked: Notifs.dnd = !Notifs.dnd
            }

            RoundToggle {
                visible: NightLight.available
                icon: "nightlight"
                label: Tr.tr("Night light")
                checked: NightLight.on
                onClicked: NightLight.toggle()
            }

            RoundToggle {
                icon: "coffee"
                label: Tr.tr("Keep awake")
                checked: IdleInhibitor.enabled
                onClicked: IdleInhibitor.enabled = !IdleInhibitor.enabled
            }

            RoundToggle {
                icon: "sports_esports"
                label: Tr.tr("Game mode")
                checked: GameMode.enabled
                onClicked: GameMode.enabled = !GameMode.enabled
            }

            RoundToggle {
                icon: WindowLayout.floating ? "select_window" : "grid_view"
                label: WindowLayout.floating ? Tr.tr("Floating") : Tr.tr("Tiling")
                checked: WindowLayout.floating
                onClicked: WindowLayout.toggle()
            }

            RoundToggle {
                icon: "dark_mode"
                label: Tr.tr("Dark mode")
                checked: !Colours.light
                onClicked: Colours.setMode(Colours.light ? "dark" : "light")
            }

            RoundToggle {
                icon: Audio.sourceMuted ? "mic_off" : "mic"
                label: Tr.tr("Microphone")
                checked: !Audio.sourceMuted
                onClicked: {
                    const audio = Audio.source?.audio;
                    if (audio)
                        audio.muted = !audio.muted;
                }
            }

            RoundToggle {
                icon: Recorder.running ? "stop_circle" : "screen_record"
                label: Recorder.running ? `${String(Math.floor(Recorder.elapsed / 60)).padStart(2, "0")}:${String(Math.floor(Recorder.elapsed % 60)).padStart(2, "0")}` : Tr.tr("Record")
                checked: Recorder.running
                onClicked: Recorder.running ? Recorder.stop() : root.closeAnd(() => Recorder.start())
            }

            RoundToggle {
                visible: GlobalConfig.utilities.vpn.selectedProvider.length > 0
                icon: "vpn_key"
                label: Tr.tr("VPN")
                checked: VPN.connected
                onClicked: VPN.toggle()
            }
        }

        // Brightness and volume as tall sliders, like on a phone.
        Item {
            Layout.alignment: Qt.AlignTop
            implicitWidth: root.monitor ? root.sliderWidth * 2 + Tokens.spacing.small : root.sliderWidth
            implicitHeight: 152

            FilledSlider {
                visible: root.monitor !== undefined && root.monitor !== null
                x: 0
                width: root.sliderWidth
                height: parent.height
                icon: `brightness_${(Math.round(value * 6) + 1)}`
                value: root.monitor?.brightness ?? 0
                onMoved: root.monitor?.setBrightness(value)
            }

            FilledSlider {
                anchors.right: parent.right
                width: root.sliderWidth
                height: parent.height
                icon: Icons.getVolumeIcon(value, Audio.muted)
                value: Audio.volume
                to: GlobalConfig.services.maxVolume
                onMoved: Audio.setVolume(value)
            }
        }
    }

    // Output device: click to switch to the next one.
    StyledRect {
        Layout.fillWidth: true
        implicitHeight: outputRow.implicitHeight + Tokens.padding.small * 2
        radius: Tokens.rounding.full
        color: Colours.tPalette.m3surfaceContainer
        visible: Audio.sink !== null

        StateLayer {
            radius: parent.radius
            onClicked: Audio.cycleNextAudioOutput()
        }

        RowLayout {
            id: outputRow

            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.large
            anchors.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "speaker"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: Audio.sink?.description || Audio.sink?.nickName || Audio.sink?.name || ""
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurface
            }

            MaterialIcon {
                text: "swap_horiz"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }
        }
    }

    // --- Row 3: Super devices ----------------------------------------------------------------
    SuperDevices {
        Layout.fillWidth: true
    }

    // A wide tile: icon in a circle, name and state. The shape squares off a little when on.
    component BigTile: StyledRect {
        id: tile

        property string icon
        property string label
        property string sub
        property bool checked

        signal clicked

        Layout.fillWidth: true
        implicitHeight: 64
        radius: checked ? Tokens.rounding.large : Tokens.rounding.full
        color: checked ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainerHigh

        Behavior on radius {
            Anim {
                type: Anim.FastSpatial
            }
        }

        StateLayer {
            radius: tile.radius
            color: tile.checked ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
            onClicked: tile.clicked()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.small + 2
            anchors.rightMargin: Tokens.padding.large
            spacing: Tokens.spacing.medium

            StyledRect {
                implicitWidth: 44
                implicitHeight: 44
                radius: Tokens.rounding.full
                color: tile.checked ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainerHighest

                MaterialIcon {
                    anchors.centerIn: parent
                    text: tile.icon
                    fill: tile.checked ? 1 : 0
                    color: tile.checked ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium

                    Behavior on fill {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: tile.label
                    font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                    color: tile.checked ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: tile.sub
                    font: Tokens.font.body.small
                    color: tile.checked ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                    opacity: 0.85
                }
            }
        }
    }

    // A round toggle with its name underneath.
    component RoundToggle: Item {
        id: toggle

        property string icon
        property string label
        property bool checked

        signal clicked

        Layout.fillWidth: true
        implicitWidth: 56
        implicitHeight: circle.height + name.implicitHeight + Tokens.spacing.extraSmall

        StyledRect {
            id: circle

            anchors.horizontalCenter: parent.horizontalCenter
            width: 50
            height: 50
            radius: toggle.checked ? Tokens.rounding.large : Tokens.rounding.full
            color: toggle.checked ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainerHigh

            Behavior on radius {
                Anim {
                    type: Anim.FastSpatial
                }
            }

            StateLayer {
                radius: circle.radius
                color: toggle.checked ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                onClicked: toggle.clicked()
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: toggle.icon
                fill: toggle.checked ? 1 : 0
                color: toggle.checked ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.medium

                Behavior on fill {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }
        }

        StyledText {
            id: name

            anchors.top: circle.bottom
            anchors.topMargin: Tokens.spacing.extraSmall
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width + Tokens.spacing.small
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: toggle.label
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
        }
    }

    // What is playing, with the cover behind; the time and date when nothing plays.
    component MediaCard: StyledClippingRect {
        id: media

        readonly property var player: Players.active

        implicitHeight: 136
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainerHigh

        Image {
            anchors.fill: parent
            visible: media.player !== null && status === Image.Ready
            source: media.player?.trackArtUrl ?? ""
            sourceSize.width: 256
            sourceSize.height: 256
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            opacity: 0.45
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            visible: media.player !== null
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WordWrap
                text: media.player?.trackTitle || Tr.tr("Nothing playing")
                font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                color: Colours.palette.m3onSurface
            }

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: media.player?.trackArtist ?? ""
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }

            Item {
                Layout.fillHeight: true
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Tokens.spacing.extraSmall

                IconButton {
                    type: IconButton.Text
                    isRound: true
                    icon: "skip_previous"
                    disabled: !(media.player?.canGoPrevious ?? false)
                    onClicked: media.player?.previous()
                }

                IconButton {
                    type: IconButton.Filled
                    isRound: true
                    icon: media.player?.isPlaying ? "pause" : "play_arrow"
                    onClicked: media.player?.togglePlaying()
                }

                IconButton {
                    type: IconButton.Text
                    isRound: true
                    icon: "skip_next"
                    disabled: !(media.player?.canGoNext ?? false)
                    onClicked: media.player?.next()
                }
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            visible: media.player === null
            spacing: 0

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Time.hourStr + ":" + Time.minuteStr
                font: Tokens.font.body.builders.large.size(34).weight(Font.DemiBold).build()
                color: Colours.palette.m3primary
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: {
                    Time.hours;
                    return new Date().toLocaleDateString(Qt.locale(), "ddd d MMM");
                }
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }
    }
}
