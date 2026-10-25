pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// Content of the details sheet for one calendar event. From a lesson, homework (due at the next
// lesson of that subject) or an exam (in that lesson) can be added in one step. Own events can be
// edited and deleted; events from subscribed calendars are read-only.
ColumnLayout {
    id: root

    property var event: null

    readonly property bool own: event?.cal === Calendars.localId
    readonly property bool school: event ? (event.kind === "lesson" || event.kind === "test") && event.subject !== "" : false

    signal editRequested(e: var)
    signal addRequested(kind: string, subject: string, start: double)
    signal done

    function clock(ms: double): string {
        return Qt.formatTime(new Date(ms), Qt.locale().timeFormat(Locale.ShortFormat));
    }

    spacing: Tokens.spacing.medium

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        StyledRect {
            implicitWidth: 44
            implicitHeight: 44
            radius: Tokens.rounding.full
            color: root.event ? (root.event.subject ? Subjects.containerOf(root.event.subject) : Qt.alpha(Calendars.accentOf(root.event), 0.25)) : "transparent"

            MaterialIcon {
                anchors.centerIn: parent
                text: root.event?.kind === "test" ? "quiz" : root.event?.subject ? (Subjects.subjects[root.event.subject]?.icon ?? "school") : "event"
                fill: 1
                color: root.event?.kind === "test" ? Colours.palette.m3error : root.event?.subject ? Subjects.onContainerOf(root.event.subject) : Colours.palette.m3onSurface
                fontStyle: Tokens.font.icon.medium
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.event ? Calendars.titleOf(root.event) : ""
                font: Tokens.font.body.builders.large.size(20).weight(Font.DemiBold).build()
                color: Colours.palette.m3onSurface
            }

            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: {
                    if (!root.event)
                        return "";
                    if (root.event.kind === "test")
                        return root.event.subject ? Tr.tr("Exam · %1").arg(Subjects.nameOf(root.event.subject)) : Tr.tr("Exam");
                    if (root.event.cancelled)
                        return Tr.tr("Cancelled");
                    return root.event.kind === "lesson" ? Tr.tr("Lesson") : "";
                }
                font: Tokens.font.body.medium
                color: root.event?.kind === "test" || root.event?.cancelled ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
            }
        }
    }

    // Facts
    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: Tokens.spacing.medium
        rowSpacing: Tokens.spacing.small

        Fact {
            icon: "schedule"
            text: {
                if (!root.event)
                    return "";
                const date = new Date(root.event.start).toLocaleDateString(Qt.locale(), "dddd, d MMMM");
                return root.event.allDay ? date : date + " · " + root.clock(root.event.start) + " – " + root.clock(root.event.end);
            }
        }

        Fact {
            icon: "location_on"
            text: root.event?.location ?? ""
        }

        Fact {
            icon: "person"
            text: root.event?.teacher ?? ""
        }

        Fact {
            icon: "notes"
            text: root.event?.kind === "lesson" ? (root.event?.note ?? "") : ""
        }

        Fact {
            icon: "calendar_month"
            text: root.event ? Calendars.nameOf(root.event.cal) : ""
        }
    }

    Item {
        Layout.fillHeight: true
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        TextButton {
            visible: root.own
            type: TextButton.Text
            text: Tr.tr("Delete")
            inactiveOnColour: Colours.palette.m3error
            onClicked: {
                Calendars.removeEvent(root.event.id);
                root.done();
            }
        }

        Item {
            Layout.fillWidth: true
        }

        IconTextButton {
            visible: root.school
            type: IconTextButton.Tonal
            icon: "assignment"
            text: Tr.tr("Add homework")
            onClicked: {
                // Homework is due at the next lesson of the subject.
                const next = Calendars.nextLesson(root.event.subject, root.event.end);
                root.addRequested("homework", root.event.subject, next ? next.start : root.event.start);
            }
        }

        IconTextButton {
            visible: root.school && root.event?.kind === "lesson"
            type: IconTextButton.Tonal
            icon: "quiz"
            text: Tr.tr("Add exam")
            onClicked: root.addRequested("exam", root.event.subject, root.event.start)
        }

        TextButton {
            visible: root.own
            type: TextButton.Filled
            horizontalPadding: Tokens.padding.extraLarge
            text: Tr.tr("Edit")
            onClicked: root.editRequested(root.event)
        }
    }

    component Fact: RowLayout {
        property alias icon: factIcon.text
        property alias text: factText.text

        Layout.fillWidth: true
        visible: factText.text !== ""
        spacing: Tokens.spacing.small

        MaterialIcon {
            id: factIcon

            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.small
        }

        StyledText {
            id: factText

            Layout.fillWidth: true
            elide: Text.ElideRight
            font: Tokens.font.body.medium
            color: Colours.palette.m3onSurface
        }
    }
}
