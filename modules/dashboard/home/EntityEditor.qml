pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

// Editor: pick which Home Assistant entities appear as tiles.
ColumnLayout {
    id: root

    property bool showSensitive

    readonly property var filtered: {
        const q = search.text.trim().toLowerCase();
        return HomeAssistant.entities.filter(e => {
            if (!showSensitive && HomeAssistant.isSensitive(e.entity_id))
                return false;
            if (q === "")
                return true;
            return e.entity_id.toLowerCase().includes(q) || e.attributes.friendly_name.toLowerCase().includes(q);
        });
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
        Layout.preferredHeight: 360
        clip: true
        spacing: Tokens.spacing.extraSmall
        model: root.filtered

        delegate: StyledRect {
            id: row

            required property var modelData

            width: list.width
            implicitHeight: rowLayout.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.medium
            color: HomeAssistant.isSelected(modelData.entity_id) ? Colours.tPalette.m3surfaceContainerHigh : "transparent"

            RowLayout {
                id: rowLayout

                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.medium
                anchors.rightMargin: Tokens.padding.medium
                spacing: Tokens.spacing.medium

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: row.modelData.attributes.friendly_name
                        elide: Text.ElideRight
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: row.modelData.entity_id
                        elide: Text.ElideRight
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }

                StyledSwitch {
                    checked: HomeAssistant.isSelected(row.modelData.entity_id)
                    onToggled: HomeAssistant.setSelected(row.modelData.entity_id, checked)
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.filtered.length === 0
        horizontalAlignment: Text.AlignHCenter
        text: HomeAssistant.entities.length === 0 ? Tr.tr("Loading devices...") : Tr.tr("No matching devices")
        font: Tokens.font.body.small
        color: Colours.palette.m3onSurfaceVariant
    }
}
