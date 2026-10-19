import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// One Home Assistant entity as a Material You tile.
// Built on ButtonBase, so it gets Caelestia's ripple, press shape-morph and colour fades.
ButtonBase {
    id: root

    required property string entityId

    readonly property var entity: HomeAssistant.byId[entityId] ?? null
    readonly property string domain: HomeAssistant.domainOf(entityId)
    readonly property bool unavailable: !entity || entity.state === "unavailable" || entity.state === "unknown"
    readonly property bool actionable: HomeAssistant.isActionable(entityId) && !unavailable
    readonly property bool sensitive: HomeAssistant.isSensitive(entityId)
    readonly property bool on: HomeAssistant.isOn(entityId)

    // Sensitive devices (garage, locks) need a second tap within 3 s.
    property bool confirming

    readonly property string iconName: {
        const dc = entity?.attributes?.device_class ?? "";
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
            return dc === "garage" ? "garage" : "blinds";
        case "person":
            return "person";
        case "binary_sensor":
            return dc === "door" || dc === "garage_door" ? "door_front" : dc === "motion" ? "directions_run" : "sensors";
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
        if (domain === "light" && on && entity.attributes.brightness !== null)
            return `${Math.round(entity.attributes.brightness / 2.55)}%`;
        if (domain in HomeAssistant.runServices)
            return Tr.tr("Run");
        if (entity.state === "on")
            return Tr.tr("On");
        if (entity.state === "off")
            return Tr.tr("Off");
        const unit = entity.attributes.unit_of_measurement;
        return unit ? `${entity.state} ${unit}` : entity.state.charAt(0).toUpperCase() + entity.state.slice(1);
    }

    implicitWidth: 196
    implicitHeight: content.implicitHeight + Tokens.padding.large * 2

    // Set both: ButtonBase only copies checked -> internalChecked on change, not at creation.
    checked: on && !unavailable
    internalChecked: on && !unavailable
    disabled: unavailable

    activeColour: Colours.palette.m3primaryContainer
    activeOnColour: Colours.palette.m3onPrimaryContainer
    inactiveColour: confirming ? Colours.palette.m3errorContainer : Colours.tPalette.m3surfaceContainerHigh
    inactiveOnColour: confirming ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSurface

    onClicked: {
        if (!actionable)
            return;
        if (sensitive && !confirming) {
            confirming = true;
            confirmTimer.restart();
            return;
        }
        confirming = false;
        HomeAssistant.activate(entityId);
    }

    Timer {
        id: confirmTimer

        interval: 3000
        onTriggered: root.confirming = false
    }

    RowLayout {
        id: content

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        // Icon in a soft circle that fills in when the device is on.
        StyledRect {
            implicitWidth: icon.implicitHeight + Tokens.padding.medium * 2
            implicitHeight: implicitWidth
            radius: width / 2
            color: root.internalChecked ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainerHighest

            MaterialIcon {
                id: icon

                anchors.centerIn: parent
                text: root.iconName
                fontStyle: Tokens.font.icon.medium
                fill: root.internalChecked ? 1 : 0
                color: root.internalChecked ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant

                Behavior on fill {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }

                Behavior on color {
                    CAnim {}
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.entity?.attributes?.friendly_name ?? root.entityId
                elide: Text.ElideRight
                font: Tokens.font.body.medium
                color: root.onColour
            }

            StyledText {
                Layout.fillWidth: true
                text: root.stateText
                elide: Text.ElideRight
                font: Tokens.font.body.small
                color: root.onColour
                opacity: 0.75
            }
        }
    }
}
