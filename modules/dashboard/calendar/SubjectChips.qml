pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services

// Pick a subject: one chip per subject in its colour, plus "None". Wraps onto several lines.
Flow {
    id: root

    property string subject
    property bool allowNone: true

    signal picked(id: string)

    spacing: Tokens.spacing.extraSmall

    Chip {
        visible: root.allowNone
        subjectId: ""
        text: Tr.tr("None")
    }

    Repeater {
        model: Subjects.list.filter(s => !s.hidden)

        Chip {
            required property var modelData

            subjectId: modelData.id
            text: modelData.name
        }
    }

    component Chip: StyledRect {
        id: chip

        required property string subjectId
        property alias text: label.text
        readonly property bool on: root.subject === subjectId

        implicitWidth: row.implicitWidth + Tokens.padding.medium * 2
        implicitHeight: 32
        radius: Tokens.rounding.small
        color: on ? (subjectId ? Subjects.containerOf(subjectId) : Colours.palette.m3secondaryContainer) : "transparent"
        border.width: on ? 0 : 1
        border.color: Colours.palette.m3outlineVariant

        Behavior on color {
            CAnim {}
        }

        StateLayer {
            radius: parent.radius
            onClicked: {
                root.subject = chip.subjectId;
                root.picked(chip.subjectId);
            }
        }

        Row {
            id: row

            anchors.centerIn: parent
            spacing: Tokens.spacing.small

            StyledRect {
                anchors.verticalCenter: parent.verticalCenter
                visible: chip.subjectId !== ""
                implicitWidth: 8
                implicitHeight: 8
                radius: Tokens.rounding.full
                color: Subjects.colourOf(chip.subjectId)
            }

            StyledText {
                id: label

                anchors.verticalCenter: parent.verticalCenter
                font: Tokens.font.body.small
                color: chip.on ? (chip.subjectId ? Subjects.onContainerOf(chip.subjectId) : Colours.palette.m3onSecondaryContainer) : Colours.palette.m3onSurfaceVariant
            }
        }
    }
}
