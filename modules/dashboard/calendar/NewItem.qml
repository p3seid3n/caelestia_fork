pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

// Content of the "New" / "Edit" sheet of the Calendar tab, for own events, homework, exams and
// reminders. Placing the time is meant to be quick:
//   - the day: arrows, or the chips Today / Tomorrow / Next <subject> lesson
//   - the time: the hour and minute boxes (scroll, arrows or type), or one of that day's lessons,
//     which also takes the lesson's subject and length
//   - events get a length from chips instead of an end time
StyledFlickable {
    id: root

    property string type: "event"
    property date day: new Date()
    property int minutes: 9 * 60
    property int duration: 60
    property bool allDay
    property bool timed: true
    property string subject
    property string error
    // Editing an existing own event ("event") or homework / exam / reminder ("task").
    property string editId
    property string editKind

    readonly property bool isTask: type !== "event"
    readonly property var dayLessons: Calendars.lessonsOn(day).filter(e => !e.cancelled)
    readonly property var next: subject ? Calendars.nextLesson(subject, Date.now()) : null

    signal saved

    function startOf(d: date): date {
        return new Date(d.getFullYear(), d.getMonth(), d.getDate());
    }

    function clock(ms: double): string {
        return Qt.formatTime(new Date(ms), Qt.locale().timeFormat(Locale.ShortFormat));
    }

    function reset(): void {
        error = "";
        editId = "";
        editKind = "";
        titleField.text = "";
        extraField.text = "";
        allDay = false;
        timed = true;
        duration = 60;
        contentY = 0;
    }

    // A new entry on a day; `at` is minutes after midnight, or -1 for "the next full hour".
    function openNew(d: date, at: int, kind: string): void {
        reset();
        type = kind;
        day = startOf(d);
        subject = "";
        minutes = at >= 0 ? at : Math.min(22, new Date().getHours() + 1) * 60;
        // Clicking into a lesson's slot takes that lesson.
        const inside = dayLessons.find(l => {
            const s = (l.start - day.getTime()) / 60000;
            return at >= 0 && s <= at && at < s + (l.end - l.start) / 60000;
        });
        if (inside)
            pickLesson(inside);
        Qt.callLater(() => titleField.forceActiveFocus());
    }

    function openEvent(e: var): void {
        reset();
        editId = e.id;
        editKind = "event";
        type = "event";
        day = startOf(new Date(e.start));
        minutes = Math.round((e.start - day.getTime()) / 60000);
        duration = Math.max(15, Math.round((e.end - e.start) / 60000));
        allDay = e.allDay;
        subject = e.subject ?? "";
        titleField.text = e.title;
        extraField.text = e.location ?? "";
    }

    function openTask(t: var): void {
        reset();
        editId = t.id;
        editKind = "task";
        type = t.type;
        day = startOf(new Date(t.due));
        minutes = Math.round((t.due - day.getTime()) / 60000);
        timed = t.hasTime;
        subject = t.subject;
        titleField.text = t.title;
        extraField.text = t.notes;
    }

    function pickLesson(l: var): void {
        day = startOf(new Date(l.start));
        minutes = Math.round((l.start - day.getTime()) / 60000);
        duration = Math.max(15, Math.round((l.end - l.start) / 60000));
        allDay = false;
        timed = true;
        if (l.subject)
            subject = l.subject;
    }

    function save(): void {
        const start = day.getTime() + minutes * 60000;
        if (isTask) {
            const title = titleField.text.trim();
            if (title === "" && subject === "") {
                error = Tr.tr("Give it a title or a subject.");
                return;
            }
            const due = timed ? start : day.getTime();
            if (editKind === "task")
                Assignments.update(editId, {
                    title: title,
                    type: type,
                    subject: subject,
                    due: due,
                    hasTime: timed,
                    notes: extraField.text.trim()
                });
            else
                Assignments.add(title, type, subject, due, timed, extraField.text);
        } else {
            const title = titleField.text.trim() !== "" ? titleField.text : Subjects.nameOf(subject);
            const s = allDay ? day.getTime() : start;
            const e = allDay ? new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1).getTime() : start + duration * 60000;
            if (editKind === "event")
                Calendars.updateEvent(editId, {
                    title: title.trim() || Tr.tr("(no title)"),
                    location: extraField.text.trim(),
                    allDay: allDay,
                    start: s,
                    end: e,
                    subject: subject
                });
            else
                Calendars.addEvent(title, extraField.text, allDay, s, e, subject);
        }
        saved();
    }

    function remove(): void {
        if (editKind === "task")
            Assignments.remove(editId);
        else if (editKind === "event")
            Calendars.removeEvent(editId);
        saved();
    }

    contentWidth: width
    contentHeight: layout.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: layout

        width: root.width
        spacing: Tokens.spacing.medium

        // Kind
        Row {
            spacing: Tokens.spacing.extraSmall
            visible: root.editKind === ""

            Repeater {
                model: [
                    {
                        key: "event",
                        name: Tr.tr("Event"),
                        icon: "event"
                    },
                    {
                        key: "homework",
                        name: Tr.tr("Homework"),
                        icon: "assignment"
                    },
                    {
                        key: "exam",
                        name: Tr.tr("Exam"),
                        icon: "quiz"
                    },
                    {
                        key: "reminder",
                        name: Tr.tr("Reminder"),
                        icon: "notifications"
                    }
                ]

                IconTextButton {
                    required property var modelData

                    type: IconTextButton.Tonal
                    checked: root.type === modelData.key
                    icon: modelData.icon
                    text: modelData.name
                    onClicked: root.type = modelData.key
                }
            }
        }

        StyledTextField {
            id: titleField

            Layout.fillWidth: true
            placeholderText: root.type === "exam" ? Tr.tr("What is the exam about?") : root.type === "homework" ? Tr.tr("What needs to be done?") : root.type === "reminder" ? Tr.tr("Remind me to ...") : Tr.tr("Title")
            leadingIcon: root.type === "exam" ? "quiz" : root.type === "homework" ? "assignment" : root.type === "reminder" ? "notifications" : "edit_calendar"
            onAccepted: root.save()
        }

        // Subject
        ColumnLayout {
            Layout.fillWidth: true
            visible: Subjects.list.length > 0
            spacing: Tokens.spacing.extraSmall

            StyledText {
                text: Tr.tr("Subject")
                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                color: Colours.palette.m3primary
            }

            SubjectChips {
                Layout.fillWidth: true
                subject: root.subject
                onPicked: id => root.subject = id
            }
        }

        // Day
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            StyledText {
                text: root.isTask ? Tr.tr("Due") : Tr.tr("When")
                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                color: Colours.palette.m3primary
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                IconButton {
                    type: IconButton.Text
                    isRound: true
                    icon: "chevron_left"
                    onClicked: root.day = new Date(root.day.getFullYear(), root.day.getMonth(), root.day.getDate() - 1)
                }

                StyledText {
                    Layout.preferredWidth: 190
                    horizontalAlignment: Text.AlignHCenter
                    text: root.day.toLocaleDateString(Qt.locale(), "dddd, d MMMM")
                    font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                    color: Colours.palette.m3onSurface
                }

                IconButton {
                    type: IconButton.Text
                    isRound: true
                    icon: "chevron_right"
                    onClicked: root.day = new Date(root.day.getFullYear(), root.day.getMonth(), root.day.getDate() + 1)
                }

                Item {
                    Layout.fillWidth: true
                }

                TextButton {
                    type: TextButton.Tonal
                    text: Tr.tr("Today")
                    onClicked: root.day = root.startOf(new Date())
                }

                TextButton {
                    type: TextButton.Tonal
                    text: Tr.tr("Tomorrow")
                    onClicked: {
                        const d = new Date();
                        root.day = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1);
                    }
                }

                TextButton {
                    visible: root.next !== null
                    type: TextButton.Tonal
                    text: Tr.tr("Next lesson")
                    onClicked: root.pickLesson(root.next)
                }
            }
        }

        // Time
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.large

            RowLayout {
                spacing: Tokens.spacing.small

                StyledText {
                    text: root.isTask ? Tr.tr("At a time") : Tr.tr("All day")
                    font: Tokens.font.body.medium
                    color: Colours.palette.m3onSurface
                }

                StyledSwitch {
                    id: timeSwitch

                    onToggled: {
                        if (root.isTask)
                            root.timed = checked;
                        else
                            root.allDay = checked;
                    }

                    Binding {
                        target: timeSwitch
                        property: "checked"
                        value: root.isTask ? root.timed : root.allDay
                    }
                }
            }

            TimeField {
                visible: root.isTask ? root.timed : !root.allDay
                minutes: root.minutes
                onEdited: value => root.minutes = value
            }

            // Length of an event
            ColumnLayout {
                Layout.fillWidth: true
                visible: !root.isTask && !root.allDay
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    text: Tr.tr("until %1").arg(root.clock(root.day.getTime() + (root.minutes + root.duration) * 60000))
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    Repeater {
                        model: [15, 30, 45, 60, 90, 120, 180]

                        TextButton {
                            required property int modelData

                            type: TextButton.Tonal
                            checked: root.duration === modelData
                            text: modelData < 60 ? Tr.tr("%1 min").arg(modelData) : Tr.tr("%1 h").arg(modelData / 60)
                            onClicked: root.duration = modelData
                        }
                    }
                }
            }
        }

        // That day's lessons: one click takes the slot (and the subject)
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.dayLessons.length > 0 && (root.isTask ? root.timed : !root.allDay)
            spacing: Tokens.spacing.extraSmall

            StyledText {
                text: Tr.tr("In a lesson")
                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                color: Colours.palette.m3primary
            }

            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                Repeater {
                    model: root.dayLessons

                    StyledRect {
                        id: lessonChip

                        required property var modelData
                        readonly property bool on: root.minutes === Math.round((modelData.start - root.day.getTime()) / 60000)

                        implicitWidth: lessonRow.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: 32
                        radius: Tokens.rounding.small
                        color: on ? Subjects.containerOf(modelData.subject) : "transparent"
                        border.width: on ? 0 : 1
                        border.color: Colours.palette.m3outlineVariant

                        StateLayer {
                            radius: parent.radius
                            onClicked: root.pickLesson(lessonChip.modelData)
                        }

                        Row {
                            id: lessonRow

                            anchors.centerIn: parent
                            spacing: Tokens.spacing.small

                            StyledRect {
                                anchors.verticalCenter: parent.verticalCenter
                                implicitWidth: 8
                                implicitHeight: 8
                                radius: Tokens.rounding.full
                                color: Subjects.colourOf(lessonChip.modelData.subject)
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.clock(lessonChip.modelData.start) + "  " + (Subjects.subjects[lessonChip.modelData.subject]?.short ?? Calendars.titleOf(lessonChip.modelData))
                                font: Tokens.font.body.small
                                color: lessonChip.on ? Subjects.onContainerOf(lessonChip.modelData.subject) : Colours.palette.m3onSurfaceVariant
                            }
                        }
                    }
                }
            }
        }

        StyledTextField {
            id: extraField

            Layout.fillWidth: true
            placeholderText: root.isTask ? Tr.tr("Notes (optional)") : Tr.tr("Place (optional)")
            leadingIcon: root.isTask ? "notes" : "location_on"
            onAccepted: root.save()
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.error !== ""
            text: root.error
            font: Tokens.font.body.small
            color: Colours.palette.m3error
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            TextButton {
                visible: root.editKind !== ""
                type: TextButton.Text
                text: Tr.tr("Delete")
                inactiveOnColour: Colours.palette.m3error
                onClicked: root.remove()
            }

            Item {
                Layout.fillWidth: true
            }

            TextButton {
                type: TextButton.Filled
                horizontalPadding: Tokens.padding.extraLarge
                text: root.editKind !== "" ? Tr.tr("Save") : root.type === "event" ? Tr.tr("Add event") : root.type === "exam" ? Tr.tr("Add exam") : root.type === "reminder" ? Tr.tr("Add reminder") : Tr.tr("Add homework")
                onClicked: root.save()
            }
        }
    }
}
