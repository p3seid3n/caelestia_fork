pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

// Content of the "Add a device" sheet, after the iOS control gallery: search on top,
// devices grouped by category underneath.
//
// Home Assistant knows hundreds of entities, most of them noise. So the categories start
// folded (a handful of rows to begin with), searching opens every category that matches,
// and an open category shows its first 40 devices with a "Show all" row for the rest.
ColumnLayout {
    id: root

    property bool showSensitive
    // category key -> true when folded open / when the 40 device cap is lifted
    property var expanded: ({})
    property var showAll: ({})

    readonly property int cap: 40
    readonly property bool searching: search.text.trim() !== ""

    readonly property var categories: [
        {
            key: "light",
            title: Tr.tr("Lights"),
            icon: "lightbulb"
        },
        {
            key: "switch",
            title: Tr.tr("Switches and plugs"),
            icon: "toggle_on"
        },
        {
            key: "climate",
            title: Tr.tr("Climate and fans"),
            icon: "thermostat"
        },
        {
            key: "cover",
            title: Tr.tr("Blinds and covers"),
            icon: "blinds"
        },
        {
            key: "media",
            title: Tr.tr("Media players"),
            icon: "speaker"
        },
        {
            key: "scene",
            title: Tr.tr("Scenes and scripts"),
            icon: "palette"
        },
        {
            key: "automation",
            title: Tr.tr("Automations and buttons"),
            icon: "smart_toy"
        },
        {
            key: "sensor",
            title: Tr.tr("Sensors"),
            icon: "sensors"
        },
        {
            key: "person",
            title: Tr.tr("People"),
            icon: "person"
        },
        {
            key: "security",
            title: Tr.tr("Doors, locks and alarms"),
            icon: "lock"
        },
        {
            key: "other",
            title: Tr.tr("Everything else"),
            icon: "category"
        }
    ]

    // Entity ids per category for the current search.
    readonly property var groups: {
        const q = search.text.trim().toLowerCase();
        const out = {};
        for (const e of HomeAssistant.entities) {
            const key = HomeAssistant.categoryOf(e.entity_id);
            if (key === "security" && !showSensitive)
                continue;
            if (q !== "" && !e.entity_id.toLowerCase().includes(q) && !e.attributes.friendly_name.toLowerCase().includes(q))
                continue;
            if (!out[key])
                out[key] = [];
            out[key].push(e.entity_id);
        }
        return out;
    }

    // What the list shows, as plain strings so the list keeps its place when Home Assistant
    // refreshes: "h:<category>" header, "e:<entity id>" device, "m:<category>" show-all row.
    readonly property var rows: {
        const out = [];
        for (const c of categories) {
            const ids = groups[c.key];
            if (!ids)
                continue;
            out.push("h:" + c.key);
            if (!searching && !expanded[c.key])
                continue;
            const limit = showAll[c.key] ? ids.length : Math.min(ids.length, cap);
            for (let i = 0; i < limit; i++)
                out.push("e:" + ids[i]);
            if (limit < ids.length)
                out.push("m:" + c.key);
        }
        return out;
    }

    function toggleCategory(key: string): void {
        const next = Object.assign({}, expanded);
        next[key] = !next[key];
        expanded = next;
    }

    function revealAll(key: string): void {
        const next = Object.assign({}, showAll);
        next[key] = true;
        showAll = next;
    }

    spacing: Tokens.spacing.small

    StyledTextField {
        id: search

        Layout.fillWidth: true
        placeholderText: Tr.tr("Search devices")
        leadingIcon: "search"
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: Tr.tr("Show doors, locks and alarms (they always ask for a second tap)")
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
        }

        StyledSwitch {
            checked: root.showSensitive
            onToggled: root.showSensitive = checked
        }
    }

    StyledListView {
        id: list

        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: Tokens.spacing.extraSmall
        boundsBehavior: Flickable.StopAtBounds
        model: ScriptModel {
            values: root.rows
        }

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: list
        }

        delegate: Item {
            id: row

            required property string modelData
            readonly property string kind: modelData.charAt(0)
            readonly property string key: modelData.slice(2)
            readonly property var category: root.categories.find(c => c.key === key) ?? null
            readonly property var entity: HomeAssistant.byId[key] ?? null
            readonly property bool added: HomeAssistant.isSelected(key)
            readonly property bool open: root.searching || (root.expanded[key] ?? false)

            width: list.width
            implicitHeight: kind === "h" ? 56 : kind === "e" ? 60 : 44

            // Category header
            StyledRect {
                anchors.fill: parent
                visible: row.kind === "h"
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainer

                StateLayer {
                    radius: parent.radius
                    disabled: root.searching
                    onClicked: root.toggleCategory(row.key)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.large
                    anchors.rightMargin: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: 36
                        implicitHeight: 36
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primaryContainer

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: row.category?.icon ?? "category"
                            fill: 1
                            color: Colours.palette.m3onPrimaryContainer
                            fontStyle: Tokens.font.icon.medium
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: row.category?.title ?? row.key
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        text: String(root.groups[row.key]?.length ?? 0)
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    MaterialIcon {
                        text: "expand_more"
                        color: Colours.palette.m3onSurfaceVariant
                        rotation: row.open ? 180 : 0
                        opacity: root.searching ? 0.3 : 1

                        Behavior on rotation {
                            Anim {
                                type: Anim.FastSpatial
                            }
                        }
                    }
                }
            }

            // Device
            StyledRect {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.medium
                visible: row.kind === "e"
                radius: Tokens.rounding.large
                color: row.added ? Colours.tPalette.m3surfaceContainerHigh : "transparent"

                StateLayer {
                    radius: parent.radius
                    onClicked: HomeAssistant.setSelected(row.key, !row.added)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.rightMargin: Tokens.padding.medium
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        implicitWidth: 36
                        implicitHeight: 36
                        radius: Tokens.rounding.full
                        color: row.added ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainerHighest

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: HomeAssistant.iconOf(row.key, false)
                            color: row.added ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.medium
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: row.entity?.attributes.friendly_name ?? row.key
                            elide: Text.ElideRight
                            font: Tokens.font.body.medium
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: row.key
                            elide: Text.ElideRight
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }

                    IconButton {
                        type: row.added ? IconButton.Filled : IconButton.Tonal
                        isRound: true
                        icon: row.added ? "check" : "add"
                        onClicked: HomeAssistant.setSelected(row.key, !row.added)
                    }
                }
            }

            // Show the rest of a long category
            TextButton {
                anchors.centerIn: parent
                visible: row.kind === "m"
                type: TextButton.Text
                text: Tr.tr("Show all %1").arg(root.groups[row.key]?.length ?? 0)
                onClicked: root.revealAll(row.key)
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.rows.length === 0
        horizontalAlignment: Text.AlignHCenter
        text: HomeAssistant.entities.length === 0 ? Tr.tr("Loading devices...") : Tr.tr("No matching devices")
        font: Tokens.font.body.small
        color: Colours.palette.m3onSurfaceVariant
    }
}
