pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services

// One Home Assistant device as a Material You tile. Content adapts to the tile size:
//   1 column            -> icon only (tall light/cover/volume tiles become a vertical slider)
//   2+ columns          -> icon, name and state
//   1 row, 4+ columns   -> main control inline next to the name
//   2+ rows             -> controls underneath (all of them on big tiles)
// The icon toggles the device; the rest of the tile opens the full view (expand()).
StyledRect {
    id: root

    required property string entityId
    property int cols: 2
    property int rows: 1
    property bool editing

    signal expand

    readonly property var entity: HomeAssistant.byId[entityId] ?? null
    readonly property var attrs: entity?.attributes ?? ({})
    readonly property var can: HomeAssistant.features(entityId)
    readonly property string domain: HomeAssistant.domainOf(entityId)
    readonly property bool unavailable: !entity || entity.state === "unavailable" || entity.state === "unknown"
    readonly property bool actionable: HomeAssistant.isActionable(entityId) && !unavailable
    readonly property bool sensitive: HomeAssistant.isSensitive(entityId)
    readonly property bool on: HomeAssistant.isOn(entityId) && !unavailable

    property bool confirming

    // Layout decisions
    readonly property bool showText: cols >= 2
    readonly property bool inlineControls: rows === 1 && cols >= 4
    readonly property int controlLevel: {
        if (cols < 2)
            return 0;
        if (rows === 1)
            return cols >= 4 ? 1 : 0;
        if (rows === 2)
            return cols >= 4 ? 2 : 1;
        return 2;
    }

    // Vertical slider mode (iOS-style) for narrow, tall tiles.
    readonly property bool verticalSlider: cols === 1 && rows >= 2 && sliderKind !== ""
    readonly property string sliderKind: {
        if (can.brightness)
            return "brightness";
        if (can.position && !sensitive)
            return "position";
        if (can.volume)
            return "volume";
        if (can.fanSpeed)
            return "fan";
        return "";
    }
    readonly property real sliderValue: {
        switch (sliderKind) {
        case "brightness":
            return on ? (attrs.brightness ?? 0) / 255 : 0;
        case "position":
            return (attrs.current_position ?? 0) / 100;
        case "volume":
            return attrs.volume_level ?? 0;
        case "fan":
            return (attrs.percentage ?? 0) / 100;
        }
        return 0;
    }

    function setSlider(v: real): void {
        const pct = Math.round(v * 100);
        if (sliderKind === "brightness")
            HomeAssistant.callThrottled("light", pct === 0 ? "turn_off" : "turn_on", pct === 0 ? {
                entity_id: entityId
            } : {
                entity_id: entityId,
                brightness_pct: pct
            }, {
                state: pct === 0 ? "off" : "on",
                attributes: {
                    brightness: Math.round(v * 255)
                }
            });
        else if (sliderKind === "position")
            HomeAssistant.callThrottled("cover", "set_cover_position", {
                entity_id: entityId,
                position: pct
            }, {
                attributes: {
                    current_position: pct
                }
            });
        else if (sliderKind === "volume")
            HomeAssistant.callThrottled("media_player", "volume_set", {
                entity_id: entityId,
                volume_level: pct / 100
            }, {
                attributes: {
                    volume_level: v
                }
            });
        else if (sliderKind === "fan")
            HomeAssistant.callThrottled("fan", "set_percentage", {
                entity_id: entityId,
                percentage: pct
            }, {
                attributes: {
                    percentage: pct
                }
            });
    }

    function toggle(): void {
        if (!actionable || editing)
            return;
        if (sensitive && !confirming) {
            confirming = true;
            confirmTimer.restart();
            return;
        }
        confirming = false;
        HomeAssistant.activate(entityId);
    }

    readonly property string iconName: {
        const dc = attrs.device_class ?? "";
        switch (domain) {
        case "light":
            return "lightbulb";
        case "switch":
        case "input_boolean":
            return "toggle_on";
        case "fan":
            return "mode_fan";
        case "climate":
            return "thermostat";
        case "media_player":
            return "speaker";
        case "scene":
            return "palette";
        case "script":
            return "play_arrow";
        case "automation":
            return "smart_toy";
        case "button":
        case "input_button":
            return "radio_button_checked";
        case "lock":
            return on ? "lock_open" : "lock";
        case "cover":
            return dc === "garage" ? "garage" : dc === "door" || dc === "gate" ? "door_front" : "blinds";
        case "person":
            return "person";
        case "binary_sensor":
            if (dc === "door" || dc === "garage_door" || dc === "window")
                return dc === "window" ? "window" : "door_front";
            if (dc === "motion" || dc === "occupancy" || dc === "presence")
                return on ? "directions_run" : "accessibility_new";
            return "sensors";
        case "sensor":
            if (dc === "temperature")
                return "thermostat";
            if (dc === "humidity")
                return "humidity_percentage";
            if (dc === "battery")
                return "battery_full";
            if (dc === "power" || dc === "energy")
                return "bolt";
            return "sensors";
        default:
            return "home";
        }
    }

    readonly property string stateText: {
        if (confirming)
            return Tr.tr("Tap again to confirm");
        if (!entity)
            return Tr.tr("Not found");
        if (unavailable)
            return Tr.tr("Unavailable");
        const dc = attrs.device_class ?? "";
        if (domain === "light" && on && attrs.brightness !== null)
            return `${Math.round(attrs.brightness / 2.55)}%`;
        if (domain === "cover" && attrs.current_position !== undefined && entity.state !== "closed")
            return Tr.tr("Open %1%").arg(attrs.current_position);
        if (domain === "climate")
            return attrs.current_temperature !== undefined ? `${attrs.current_temperature}° → ${attrs.temperature ?? "–"}°` : entity.state;
        if (domain === "media_player" && attrs.media_title)
            return attrs.media_title;
        if (domain === "binary_sensor") {
            if (dc === "motion" || dc === "occupancy" || dc === "presence")
                return on ? Tr.tr("Detected") : Tr.tr("Clear");
            if (dc === "door" || dc === "window" || dc === "garage_door" || dc === "opening")
                return on ? Tr.tr("Open") : Tr.tr("Closed");
        }
        if (domain in HomeAssistant.runServices)
            return Tr.tr("Run");
        if (entity.state === "on")
            return Tr.tr("On");
        if (entity.state === "off")
            return Tr.tr("Off");
        const unit = attrs.unit_of_measurement;
        return unit ? `${entity.state} ${unit}` : entity.state.charAt(0).toUpperCase() + entity.state.slice(1).replace("_", " ");
    }

    // Lights with a colour tint the icon with their actual colour.
    readonly property color accent: {
        if (domain === "light" && on && attrs.hs_color)
            return Qt.hsva(attrs.hs_color[0] / 360, Math.min(1, attrs.hs_color[1] / 100) * 0.7, 1, 1);
        return Colours.palette.m3primary;
    }

    radius: Tokens.rounding.large
    color: confirming ? Colours.palette.m3errorContainer : on ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainerHigh
    clip: true

    Behavior on color {
        CAnim {}
    }

    Timer {
        id: confirmTimer

        interval: 3000
        onTriggered: root.confirming = false
    }

    // Tap on the tile body: open the full view.
    StateLayer {
        visible: !root.verticalSlider
        disabled: root.editing
        radius: root.radius
        color: root.on ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
        onClicked: root.expand()
    }

    // --- Vertical slider tile ---------------------------------------------------
    Item {
        anchors.fill: parent
        visible: root.verticalSlider

        StyledRect {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: parent.height * (vMouse.pressed ? vMouse.value : root.sliderValue)
            color: root.sliderKind === "brightness" ? root.accent : Colours.palette.m3primary
            opacity: 0.85

            Behavior on height {
                enabled: !vMouse.pressed

                Anim {}
            }
        }

        MaterialIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Tokens.padding.large
            text: root.iconName
            fill: root.on ? 1 : 0
            fontStyle: Tokens.font.icon.large
            color: root.on ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
        }

        MouseArea {
            id: vMouse

            property real value
            property real startY
            property bool moved

            anchors.fill: parent
            enabled: !root.editing
            preventStealing: true

            function valueAt(y: real): real {
                return Math.max(0, Math.min(1, 1 - y / height));
            }

            onPressed: e => {
                startY = e.y;
                moved = false;
                value = root.sliderValue;
            }
            onPositionChanged: e => {
                if (Math.abs(e.y - startY) > 4)
                    moved = true;
                if (moved) {
                    value = valueAt(e.y);
                    root.setSlider(value);
                }
            }
            onReleased: e => {
                if (moved)
                    root.setSlider(valueAt(e.y));
                else
                    root.expand();
            }
        }
    }

    // --- Normal tile ------------------------------------------------------------
    GridLayout {
        id: content

        visible: !root.verticalSlider
        anchors.fill: parent
        anchors.margins: root.cols >= 2 ? Tokens.padding.large : 0
        columns: root.inlineControls ? 2 : 1
        columnSpacing: Tokens.spacing.large
        rowSpacing: Tokens.spacing.medium

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: root.showText ? Qt.AlignTop : Qt.AlignCenter
            Layout.fillHeight: !root.showText // small tiles: centre the icon
            Layout.preferredWidth: root.inlineControls ? content.width * 0.4 : -1
            spacing: Tokens.spacing.medium

            // Icon: tap toggles.
            StyledRect {
                Layout.alignment: root.showText ? Qt.AlignVCenter : Qt.AlignCenter
                implicitWidth: icon.implicitHeight + Tokens.padding.medium * 2
                implicitHeight: implicitWidth
                radius: Tokens.rounding.full
                color: root.on ? root.accent : Colours.tPalette.m3surfaceContainerHighest

                Behavior on color {
                    CAnim {}
                }

                MaterialIcon {
                    id: icon

                    anchors.centerIn: parent
                    text: root.iconName
                    fill: root.on ? 1 : 0
                    color: root.on ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium

                    Behavior on fill {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                StateLayer {
                    radius: Tokens.rounding.full
                    disabled: !root.actionable || root.editing
                    color: root.on ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                    onClicked: root.toggle()
                }
            }

            ColumnLayout {
                visible: root.showText
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.attrs.friendly_name ?? root.entityId
                    elide: Text.ElideRight
                    font: Tokens.font.body.medium
                    color: root.on ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.stateText
                    elide: Text.ElideRight
                    font: Tokens.font.body.small
                    color: root.on ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                    opacity: 0.8
                }
            }
        }

        EntityControls {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            entityId: root.entityId
            level: root.controlLevel
            enabled: !root.editing
        }

        Item {
            // Pushes the header to the top on tall tiles.
            visible: !root.inlineControls && root.showText
            Layout.fillHeight: true
        }
    }
}
