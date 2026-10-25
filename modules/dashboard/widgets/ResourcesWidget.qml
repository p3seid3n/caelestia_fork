import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Services
import qs.components
import qs.services

// Processor, memory and disk use as three bars.
Item {
    id: root

    readonly property var rows: [
        {
            icon: "memory",
            label: Tr.tr("CPU"),
            value: Cpu.percentage,
            colour: Colours.palette.m3primary
        },
        {
            icon: "memory_alt",
            label: Tr.tr("Memory"),
            value: Memory.percentage,
            colour: Colours.palette.m3tertiary
        },
        {
            icon: "hard_disk",
            label: Tr.tr("Disk"),
            value: Storage.percentage,
            colour: Colours.palette.m3secondary
        }
    ]

    ServiceRef {
        service: Cpu
    }

    ServiceRef {
        service: Memory
    }

    ServiceRef {
        service: Storage
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        Item {
            Layout.fillHeight: true
        }

        Repeater {
            model: root.rows

            RowLayout {
                id: row

                required property var modelData
                readonly property real clamped: Math.max(0, Math.min(1, modelData.value))

                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: row.modelData.icon
                    color: row.modelData.colour
                    fontStyle: Tokens.font.icon.medium
                }

                StyledText {
                    Layout.preferredWidth: 64
                    visible: root.width > 220
                    text: row.modelData.label
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 8
                    radius: Tokens.rounding.full
                    color: Colours.tPalette.m3surfaceContainerHighest

                    StyledRect {
                        width: parent.width * row.clamped
                        height: parent.height
                        radius: parent.radius
                        color: row.modelData.colour

                        Behavior on width {
                            Anim {}
                        }
                    }
                }

                StyledText {
                    Layout.preferredWidth: 38
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(row.clamped * 100) + "%"
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurface
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
