pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus

// Quick settings (bottom-right panel): only the things you switch often.
//   header        date, battery (laptops), settings, power
//   connectivity  Wi-Fi and Bluetooth; the icon switches them on and off, the rest of the tile
//                 opens the list of networks / devices underneath (join, connect, disconnect)
//   toggles       focus, night light, keep awake, game mode, floating windows, dark mode,
//                 screen recording, VPN
//   Super devices this PC with the devices around it (SuperDevices.qml)
// Media, volume and brightness live in the dashboard and the bar.
// Built once after login (utilities/Wrapper.qml); nothing here polls on its own.
ColumnLayout {
    id: root

    required property ScreenState screenState

    readonly property bool shown: screenState.utilities
    readonly property var btAdapter: Bluetooth.defaultAdapter // qmllint disable unresolved-type
    readonly property var btConnected: Bluetooth.devices.values.filter(d => d.connected) // qmllint disable unresolved-type
    // The open list under the connectivity tiles: "net", "bt" or "" (closed).
    property string expanded
    // What the list shows; kept while it closes, so it doesn't empty mid-animation.
    property string listShown
    // Network asking for its password (inline field in the Wi-Fi list).
    property string passwordFor
    // Opening: the rows rise into place one after another (0 -> 1).
    property real enter: 1

    function closeAnd(action: var): void {
        root.screenState.utilities = false;
        action();
    }

    // How far row `i` is into its entrance.
    function stage(i: int): real {
        const t = Math.max(0, Math.min(1, (enter - i * 0.08) / 0.68));
        return 1 - Math.pow(1 - t, 3);
    }

    function toggleList(which: string): void {
        expanded = expanded === which ? "" : which;
        if (expanded !== "")
            listShown = expanded;
        if (expanded === "net" && Nmcli.wifiEnabled)
            Nmcli.rescanWifi();
        if (expanded !== "net")
            passwordFor = "";
    }

    spacing: Tokens.spacing.medium

    onShownChanged: {
        if (shown) {
            enter = 0;
            enterAnim.restart();
        } else {
            expanded = "";
            passwordFor = "";
        }
    }

    // Keyboard focus only while a password is being typed.
    Binding {
        target: root.screenState
        property: "utilitiesInput"
        value: root.passwordFor !== ""
    }

    NumberAnimation {
        id: enterAnim

        target: root
        property: "enter"
        to: 1
        duration: Tokens.anim.durations.expressiveDefaultSpatial
        easing.type: Easing.Linear
    }

    // --- Header ---------------------------------------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.padding.small
        spacing: Tokens.spacing.small
        opacity: root.stage(0)
        transform: Translate {
            y: (1 - root.stage(0)) * 16
        }

        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: {
                Time.hours;
                return new Date().toLocaleDateString(Qt.locale(), "dddd, d MMMM");
            }
            font: Tokens.font.title.small
            color: Colours.palette.m3onSurface
        }

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

    // --- Connectivity ---------------------------------------------------------------------
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small
        opacity: root.stage(1)
        transform: Translate {
            y: (1 - root.stage(1)) * 20
        }

        // The open list. It sits above the tiles and grows upwards: the panel hangs from the
        // bottom of the screen, so the tiles stay under the pointer while it opens and closes
        // (growing downwards moved them up and away, and the panel closed on collapse).
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.expanded !== "" ? list.implicitHeight : 0
            visible: Layout.preferredHeight > 0.5
            opacity: root.expanded !== "" ? 1 : 0
            clip: true

            Behavior on Layout.preferredHeight {
                Anim {
                    type: Anim.DefaultSpatial
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            StyledRect {
                id: list

                anchors.bottom: parent.bottom
                width: parent.width
                implicitHeight: listLoader.implicitHeight + Tokens.padding.small * 2
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainer

                Loader {
                    id: listLoader

                    x: Tokens.padding.small
                    y: Tokens.padding.small
                    width: parent.width - Tokens.padding.small * 2
                    sourceComponent: root.listShown === "bt" ? btList : root.listShown === "net" ? netList : null
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            ConnTile {
                key: "net"
                icon: Nmcli.activeEthernet && !Nmcli.active ? "lan" : Nmcli.wifiEnabled ? Icons.getNetworkIcon(Nmcli.active?.strength ?? 100) : "wifi_off"
                label: Nmcli.activeEthernet && !Nmcli.active ? Tr.tr("Ethernet") : Tr.tr("Wi-Fi")
                sub: {
                    if (Nmcli.active)
                        return Nmcli.active.ssid;
                    if (Nmcli.activeEthernet)
                        return Nmcli.wifiEnabled ? Tr.tr("Connected · Wi-Fi on") : Tr.tr("Connected");
                    return Nmcli.wifiEnabled ? Tr.tr("Not connected") : Tr.tr("Off");
                }
                checked: Nmcli.wifiEnabled || Nmcli.activeEthernet !== null
                onToggled: Nmcli.toggleWifi()
            }

            ConnTile {
                key: "bt"
                icon: root.btAdapter?.enabled ? (root.btConnected.length > 0 ? "bluetooth_connected" : "bluetooth") : "bluetooth_disabled"
                label: Tr.tr("Bluetooth")
                sub: {
                    if (!root.btAdapter?.enabled)
                        return Tr.tr("Off");
                    if (root.btConnected.length === 1)
                        return root.btConnected[0].name;
                    if (root.btConnected.length > 1)
                        return Tr.trN("%n devices", "%n devices", root.btConnected.length);
                    return Tr.tr("On");
                }
                checked: root.btAdapter?.enabled ?? false
                onToggled: {
                    if (root.btAdapter)
                        root.btAdapter.enabled = !root.btAdapter.enabled;
                }
            }
        }
    }

    // --- Toggles --------------------------------------------------------------------------
    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: Tokens.spacing.small
        rowSpacing: Tokens.spacing.small
        uniformCellWidths: true
        opacity: root.stage(2)
        transform: Translate {
            y: (1 - root.stage(2)) * 24
        }

        Toggle {
            icon: "do_not_disturb_on"
            label: Tr.tr("Focus")
            checked: Notifs.dnd
            onClicked: Notifs.dnd = !Notifs.dnd
        }

        Toggle {
            visible: NightLight.available
            icon: "nightlight"
            label: Tr.tr("Night light")
            checked: NightLight.on
            onClicked: NightLight.toggle()
        }

        Toggle {
            icon: "coffee"
            label: Tr.tr("Keep awake")
            checked: IdleInhibitor.enabled
            onClicked: IdleInhibitor.enabled = !IdleInhibitor.enabled
        }

        Toggle {
            icon: "sports_esports"
            label: Tr.tr("Game mode")
            checked: GameMode.enabled
            onClicked: GameMode.enabled = !GameMode.enabled
        }

        Toggle {
            icon: WindowLayout.floating ? "select_window" : "grid_view"
            label: Tr.tr("Floating windows")
            checked: WindowLayout.floating
            onClicked: WindowLayout.toggle()
        }

        Toggle {
            icon: "dark_mode"
            label: Tr.tr("Dark mode")
            checked: !Colours.light
            onClicked: Colours.setMode(Colours.light ? "dark" : "light")
        }

        Toggle {
            icon: Recorder.running ? "stop_circle" : "screen_record"
            label: Recorder.running ? `${String(Math.floor(Recorder.elapsed / 60)).padStart(2, "0")}:${String(Math.floor(Recorder.elapsed % 60)).padStart(2, "0")}` : Tr.tr("Record screen")
            checked: Recorder.running
            onClicked: Recorder.running ? Recorder.stop() : root.closeAnd(() => Recorder.start())
        }

        Toggle {
            visible: GlobalConfig.utilities.vpn.selectedProvider.length > 0
            icon: "vpn_key"
            label: Tr.tr("VPN")
            checked: VPN.connected
            onClicked: VPN.toggle()
        }
    }

    // --- Super devices --------------------------------------------------------------------
    SuperDevices {
        Layout.fillWidth: true
        active: root.shown
        opacity: root.stage(3)
        transform: Translate {
            y: (1 - root.stage(3)) * 28
        }
    }

    // --- Lists -----------------------------------------------------------------------------
    Component {
        id: netList

        ColumnLayout {
            id: netColumn

            readonly property var networks: [...Nmcli.networks].sort((a, b) => (b.active - a.active) || (b.strength - a.strength)).slice(0, 6) // qmllint disable missing-property

            spacing: 2

            ListHeader {
                title: Tr.tr("Wi-Fi")
                checked: Nmcli.wifiEnabled
                busy: Nmcli.scanning
                onRefresh: Nmcli.rescanWifi()
                onToggled: on => Nmcli.enableWifi(on)
            }

            ListRow {
                visible: Nmcli.activeEthernet !== null
                icon: "lan"
                title: Tr.tr("Ethernet")
                sub: Nmcli.activeEthernet?.ipAddress || Tr.tr("Connected")
                active: true
            }

            Repeater {
                model: ScriptModel {
                    values: netColumn.networks
                }

                ColumnLayout {
                    id: net

                    required property var modelData
                    readonly property bool asking: root.passwordFor === modelData.ssid

                    Layout.fillWidth: true
                    spacing: 2

                    ListRow {
                        icon: Icons.getNetworkIcon(net.modelData.strength)
                        title: net.modelData.ssid
                        sub: net.modelData.active ? Tr.tr("Connected") : net.modelData.isSecure ? Tr.tr("Secured") : Tr.tr("Open")
                        trailing: net.modelData.isSecure && !net.modelData.active ? "lock" : ""
                        active: net.modelData.active
                        busy: Nmcli.connecting && Nmcli.connectingSsid() === net.modelData.ssid
                        onClicked: {
                            if (net.modelData.active)
                                return;
                            root.passwordFor = "";
                            NetworkConnection.handleConnect(net.modelData, null, n => root.passwordFor = n.ssid);
                        }
                    }

                    // Password, right under the network that asks for it.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Tokens.padding.small
                        Layout.rightMargin: Tokens.padding.small
                        Layout.bottomMargin: Tokens.padding.small
                        visible: net.asking
                        spacing: Tokens.spacing.small

                        StyledTextField {
                            id: password

                            Layout.fillWidth: true
                            placeholderText: Tr.tr("Password")
                            leadingIcon: "key"
                            echoMode: TextInput.Password
                            onVisibleChanged: {
                                text = "";
                                if (visible)
                                    forceActiveFocus();
                            }
                            onAccepted: {
                                if (password.text.length >= 8)
                                    join.clicked();
                            }
                        }

                        TextButton {
                            id: join

                            type: TextButton.Filled
                            text: Tr.tr("Join")
                            disabled: password.text.length < 8
                            onClicked: {
                                NetworkConnection.connectWithPassword(net.modelData, password.text, null);
                                root.passwordFor = "";
                            }
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.margins: Tokens.padding.small
                visible: Nmcli.wifiEnabled && netColumn.networks.length === 0
                wrapMode: Text.WordWrap
                text: Nmcli.scanning ? Tr.tr("Looking for networks...") : Tr.tr("No networks found")
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }

            SettingsLink {
                text: Tr.tr("Network settings")
            }
        }
    }

    Component {
        id: btList

        ColumnLayout {
            id: btColumn

            readonly property var devices: Bluetooth.devices.values.filter(d => d.paired || d.connected).sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name)).slice(0, 6) // qmllint disable unresolved-type

            spacing: 2

            ListHeader {
                title: Tr.tr("Bluetooth")
                checked: root.btAdapter?.enabled ?? false
                showRefresh: false
                onToggled: on => {
                    if (root.btAdapter)
                        root.btAdapter.enabled = on;
                }
            }

            Repeater {
                model: ScriptModel {
                    values: btColumn.devices
                }

                ListRow {
                    required property var modelData
                    readonly property bool changing: modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting // qmllint disable unresolved-type

                    icon: Icons.getBluetoothIcon(modelData.icon)
                    title: modelData.name
                    sub: {
                        if (changing)
                            return modelData.connected ? Tr.tr("Disconnecting...") : Tr.tr("Connecting...");
                        if (!modelData.connected)
                            return Tr.tr("Not connected");
                        return modelData.batteryAvailable ? Tr.tr("Connected · %1%").arg(Math.round(modelData.battery * 100)) : Tr.tr("Connected");
                    }
                    active: modelData.connected
                    busy: changing
                    onClicked: modelData.connected = !modelData.connected
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.margins: Tokens.padding.small
                visible: (root.btAdapter?.enabled ?? false) && btColumn.devices.length === 0
                wrapMode: Text.WordWrap
                text: Tr.tr("No paired devices yet")
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }

            SettingsLink {
                text: Tr.tr("Pair a new device")
            }
        }
    }

    // A connectivity tile: the round icon switches it on/off, the rest opens its list.
    component ConnTile: StyledRect {
        id: tile

        required property string key
        property string icon
        property string label
        property string sub
        property bool checked
        readonly property bool open: root.expanded === key

        signal toggled

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 68
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
            onClicked: root.toggleList(tile.key)
        }

        StyledRect {
            id: iconCircle

            anchors.left: parent.left
            anchors.leftMargin: Tokens.padding.small + 2
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: 44
            implicitHeight: 44
            radius: Tokens.rounding.full
            color: tile.checked ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainerHighest

            StateLayer {
                radius: Tokens.rounding.full
                color: tile.checked ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                onClicked: tile.toggled()
            }

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
            anchors.left: iconCircle.right
            anchors.right: chevron.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.spacing.medium
            anchors.rightMargin: Tokens.spacing.extraSmall
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
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: tile.sub
                font: Tokens.font.body.small
                color: tile.checked ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                opacity: 0.85
            }
        }

        MaterialIcon {
            id: chevron

            anchors.right: parent.right
            anchors.rightMargin: Tokens.padding.medium
            anchors.verticalCenter: parent.verticalCenter
            // Points to where the list opens (above).
            text: "expand_less"
            rotation: tile.open ? 180 : 0
            color: tile.checked ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant

            Behavior on rotation {
                Anim {
                    type: Anim.FastSpatial
                }
            }
        }
    }

    // A toggle: icon and name in a pill that squares off a little when on.
    component Toggle: StyledRect {
        id: toggle

        property string icon
        property string label
        property bool checked

        signal clicked

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 52
        radius: checked ? Tokens.rounding.large : Tokens.rounding.full
        color: checked ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainerHigh

        Behavior on radius {
            Anim {
                type: Anim.FastSpatial
            }
        }

        StateLayer {
            radius: toggle.radius
            color: toggle.checked ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
            onClicked: toggle.clicked()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.large
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: toggle.icon
                fill: toggle.checked ? 1 : 0
                color: toggle.checked ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small

                Behavior on fill {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: toggle.label
                font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
                color: toggle.checked ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
            }
        }
    }

    // Top of a list: its name, a refresh button and the on/off switch.
    component ListHeader: RowLayout {
        id: header

        property string title
        property bool checked
        property bool busy
        property bool showRefresh: true

        signal toggled(on: bool)
        signal refresh

        Layout.fillWidth: true
        Layout.leftMargin: Tokens.padding.small
        Layout.bottomMargin: Tokens.spacing.extraSmall
        spacing: Tokens.spacing.small

        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: header.title
            font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
            color: Colours.palette.m3onSurface
        }

        IconButton {
            visible: header.showRefresh && header.checked
            type: IconButton.Text
            isRound: true
            icon: "refresh"
            disabled: header.busy
            onClicked: header.refresh()
        }

        StyledSwitch {
            checked: header.checked
            onToggled: header.toggled(checked)
        }
    }

    // A network or device in a list.
    component ListRow: StyledRect {
        id: row

        property string icon
        property string title
        property string sub
        property string trailing
        property bool active
        property bool busy

        signal clicked

        Layout.fillWidth: true
        implicitHeight: 52
        radius: Tokens.rounding.medium
        color: active ? Colours.palette.m3secondaryContainer : "transparent"

        StateLayer {
            radius: row.radius
            color: row.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
            onClicked: row.clicked()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.padding.medium
            anchors.rightMargin: Tokens.padding.medium
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: row.icon
                fill: row.active ? 1 : 0
                color: row.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.medium
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: row.title
                    font: Tokens.font.body.builders.medium.weight(row.active ? Font.DemiBold : Font.Normal).build()
                    color: row.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: row.sub
                    font: Tokens.font.body.small
                    color: row.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                }
            }

            MaterialIcon {
                visible: row.trailing !== "" && !row.busy
                text: row.trailing
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            MaterialIcon {
                visible: row.active && !row.busy
                text: "check_circle"
                fill: 1
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.small
            }

            CircularIndicator {
                visible: row.busy
                running: row.busy
                implicitWidth: 20
                implicitHeight: 20
            }
        }
    }

    // "... settings" at the bottom of a list.
    component SettingsLink: TextButton {
        Layout.alignment: Qt.AlignRight
        Layout.topMargin: Tokens.spacing.extraSmall
        type: TextButton.Text
        onClicked: root.closeAnd(() => WindowFactory.create())
    }
}
