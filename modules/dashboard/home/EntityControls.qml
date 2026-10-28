pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// Controls for one device, picked from what it can do (HomeAssistant.features()).
// level 1: the main control only (brightness, cover buttons, target temperature, playback).
// level 2: everything (colour, colour temperature, position, HVAC modes, volume...).
// On wide tiles the extra controls sit two per row, so they fit the tile's height.
GridLayout {
    id: root

    required property string entityId
    property int level: 2
    property bool wide

    readonly property var entity: HomeAssistant.byId[entityId] ?? null
    readonly property var attrs: entity?.attributes ?? ({})
    readonly property var can: HomeAssistant.features(entityId)
    readonly property string domain: HomeAssistant.domainOf(entityId)
    readonly property bool sensitive: HomeAssistant.isSensitive(entityId)
    readonly property bool on: HomeAssistant.isOn(entityId)

    // Sensitive devices: the first tap arms a button for 3 s, the second one acts.
    property string armed

    function guarded(key: string, action: var): void {
        if (sensitive && armed !== key) {
            armed = key;
            disarm.restart();
            return;
        }
        armed = "";
        action();
    }

    columns: wide ? 2 : 1
    columnSpacing: Tokens.spacing.large
    rowSpacing: Tokens.spacing.small
    visible: level > 0

    Timer {
        id: disarm

        interval: 3000
        onTriggered: root.armed = ""
    }

    // --- Light -----------------------------------------------------------------
    ControlRow {
        Layout.columnSpan: root.wide ? 2 : 1
        visible: root.can.brightness
        icon: "brightness_6"

        StyledSlider {
            Layout.fillWidth: true
            implicitHeight: 24
            value: root.on ? (root.attrs.brightness ?? 0) / 255 : 0
            onInteraction: v => HomeAssistant.callThrottled("light", "turn_on", {
                    entity_id: root.entityId,
                    brightness_pct: Math.max(1, Math.round(v * 100))
                }, {
                    state: "on",
                    attributes: {
                        brightness: Math.round(v * 255)
                    }
                })
        }
    }

    ControlRow {
        visible: root.level >= 2 && root.can.colour
        icon: "palette"

        GradientSlider {
            Layout.fillWidth: true
            kind: "hue"
            value: (root.attrs.hs_color?.[0] ?? 0) / 360
            onMoved: v => HomeAssistant.callThrottled("light", "turn_on", {
                    entity_id: root.entityId,
                    hs_color: [Math.round(v * 360), 100]
                }, {
                    state: "on",
                    attributes: {
                        hs_color: [v * 360, 100]
                    }
                })
        }
    }

    ControlRow {
        visible: root.level >= 2 && root.can.colourTemp
        icon: "thermometer"

        readonly property real minK: root.attrs.min_color_temp_kelvin ?? 2000
        readonly property real maxK: root.attrs.max_color_temp_kelvin ?? 6500

        GradientSlider {
            Layout.fillWidth: true
            kind: "temperature"
            value: ((root.attrs.color_temp_kelvin ?? parent.minK) - parent.minK) / Math.max(1, parent.maxK - parent.minK)
            onMoved: v => HomeAssistant.callThrottled("light", "turn_on", {
                    entity_id: root.entityId,
                    color_temp_kelvin: Math.round(parent.minK + v * (parent.maxK - parent.minK))
                }, {
                    state: "on"
                })
        }
    }

    // --- Cover (blinds, garage) --------------------------------------------------
    RowLayout {
        Layout.columnSpan: root.wide ? 2 : 1
        visible: root.domain === "cover"
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        Repeater {
            model: [
                {
                    key: "open",
                    icon: "arrow_upward",
                    service: "open_cover"
                },
                {
                    key: "stop",
                    icon: "stop",
                    service: "stop_cover"
                },
                {
                    key: "close",
                    icon: "arrow_downward",
                    service: "close_cover"
                }
            ]

            IconButton {
                required property var modelData

                Layout.fillWidth: true
                type: IconButton.Tonal
                icon: root.armed === modelData.key ? "warning" : modelData.icon
                inactiveColour: root.armed === modelData.key ? Colours.palette.m3errorContainer : Colours.palette.m3secondaryContainer
                inactiveOnColour: root.armed === modelData.key ? Colours.palette.m3onErrorContainer : Colours.palette.m3onSecondaryContainer
                onClicked: root.guarded(modelData.key, () => HomeAssistant.call("cover", modelData.service, {
                        entity_id: root.entityId
                    }, null))
            }
        }
    }

    ControlRow {
        // No position slider for doors/garages: too easy to move by accident.
        visible: root.level >= 2 && root.can.position && !root.sensitive
        icon: "blinds"

        StyledSlider {
            Layout.fillWidth: true
            implicitHeight: 24
            interactionOnMove: false
            value: (root.attrs.current_position ?? 0) / 100
            onInteraction: v => HomeAssistant.call("cover", "set_cover_position", {
                    entity_id: root.entityId,
                    position: Math.round(v * 100)
                }, {
                    attributes: {
                        current_position: Math.round(v * 100)
                    }
                })
        }
    }

    // --- Climate --------------------------------------------------------------
    RowLayout {
        Layout.columnSpan: root.wide ? 2 : 1
        visible: root.can.climate
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        readonly property real step: root.attrs.target_temp_step ?? 0.5
        readonly property real target: root.attrs.temperature ?? 0

        function setTarget(t: real): void {
            const clamped = Math.max(root.attrs.min_temp ?? 5, Math.min(root.attrs.max_temp ?? 35, t));
            HomeAssistant.callThrottled("climate", "set_temperature", {
                entity_id: root.entityId,
                temperature: clamped
            }, {
                attributes: {
                    temperature: clamped
                }
            });
        }

        IconButton {
            type: IconButton.Tonal
            isRound: true
            icon: "remove"
            onClicked: parent.setTarget(parent.target - parent.step)
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: `${parent.target}°`
            font: Tokens.font.title.large
            color: Colours.palette.m3onSurface
        }

        IconButton {
            type: IconButton.Tonal
            isRound: true
            icon: "add"
            onClicked: parent.setTarget(parent.target + parent.step)
        }
    }

    Flow {
        Layout.columnSpan: root.wide ? 2 : 1
        visible: root.level >= 2 && root.can.climate
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        Repeater {
            model: root.attrs.hvac_modes ?? []

            TextButton {
                required property string modelData

                type: TextButton.Tonal
                isToggle: true
                checked: root.entity?.state === modelData
                internalChecked: checked
                text: modelData.charAt(0).toUpperCase() + modelData.slice(1).replace("_", " ")
                onClicked: HomeAssistant.call("climate", "set_hvac_mode", {
                    entity_id: root.entityId,
                    hvac_mode: modelData
                }, {
                    state: modelData
                })
            }
        }
    }

    // --- Media player -----------------------------------------------------------
    StyledText {
        Layout.columnSpan: root.wide ? 2 : 1
        visible: root.level >= 2 && root.can.media && !!root.attrs.media_title
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: root.attrs.media_artist ? `${root.attrs.media_title} · ${root.attrs.media_artist}` : (root.attrs.media_title ?? "")
        font: Tokens.font.body.medium
        color: Colours.palette.m3onSurfaceVariant
    }

    RowLayout {
        Layout.columnSpan: root.wide ? 2 : 1
        visible: root.can.media
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        Repeater {
            model: [
                {
                    icon: "skip_previous",
                    service: "media_previous_track"
                },
                {
                    icon: root.entity?.state === "playing" ? "pause" : "play_arrow",
                    service: "media_play_pause"
                },
                {
                    icon: "skip_next",
                    service: "media_next_track"
                }
            ]

            IconButton {
                required property var modelData

                Layout.fillWidth: true
                type: IconButton.Tonal
                icon: modelData.icon
                onClicked: HomeAssistant.call("media_player", modelData.service, {
                    entity_id: root.entityId
                }, null)
            }
        }
    }

    ControlRow {
        visible: root.level >= 2 && root.can.volume
        icon: "volume_up"

        StyledSlider {
            Layout.fillWidth: true
            implicitHeight: 24
            value: root.attrs.volume_level ?? 0
            onInteraction: v => HomeAssistant.callThrottled("media_player", "volume_set", {
                    entity_id: root.entityId,
                    volume_level: Math.round(v * 100) / 100
                }, {
                    attributes: {
                        volume_level: v
                    }
                })
        }
    }

    // --- Fan ------------------------------------------------------------------
    ControlRow {
        visible: root.can.fanSpeed
        icon: "mode_fan"

        StyledSlider {
            Layout.fillWidth: true
            implicitHeight: 24
            value: (root.attrs.percentage ?? 0) / 100
            onInteraction: v => HomeAssistant.callThrottled("fan", "set_percentage", {
                    entity_id: root.entityId,
                    percentage: Math.round(v * 100)
                }, {
                    attributes: {
                        percentage: Math.round(v * 100)
                    }
                })
        }
    }

    // --- Lock -----------------------------------------------------------------
    TextButton {
        Layout.columnSpan: root.wide ? 2 : 1
        visible: root.domain === "lock"
        Layout.fillWidth: true
        type: root.armed === "lock" ? TextButton.Filled : TextButton.Tonal
        text: root.armed === "lock" ? Tr.tr("Tap again to confirm") : root.on ? Tr.tr("Lock") : Tr.tr("Unlock")
        onClicked: root.guarded("lock", () => HomeAssistant.activate(root.entityId))
    }

    // --- Scenes, scripts, buttons ---------------------------------------------
    TextButton {
        Layout.columnSpan: root.wide ? 2 : 1
        visible: root.domain in HomeAssistant.runServices
        Layout.fillWidth: true
        type: TextButton.Tonal
        text: Tr.tr("Run")
        onClicked: HomeAssistant.activate(root.entityId)
    }

    // --- Sensors: when it last changed ----------------------------------------
    StyledText {
        Layout.columnSpan: root.wide ? 2 : 1
        visible: root.level >= 2 && root.can.value && !!root.entity?.last_changed
        Layout.fillWidth: true
        text: Tr.tr("Changed %1").arg(Qt.formatDateTime(new Date(root.entity?.last_changed ?? 0), "ddd hh:mm"))
        font: Tokens.font.body.small
        color: Colours.palette.m3onSurfaceVariant
    }

    // Icon + control on one line.
    component ControlRow: RowLayout {
        property alias icon: rowIcon.text

        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        MaterialIcon {
            id: rowIcon

            color: Colours.palette.m3onSurfaceVariant
        }
    }
}
