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

// Side panel of the Calendar tab for the chosen day: exams first, then homework and reminders
// (tick them off right here), other events, the day's lessons in one compact list, and finally
// what is coming up (exams and open homework, not every lesson).
ColumnLayout {
    id: root

    property date day: new Date()

    readonly property bool isToday: sameDay(day, new Date())
    readonly property var dayEvents: Calendars.eventsOn(day)
    readonly property var exams: dayEvents.filter(e => e.kind === "test")
    readonly property var others: dayEvents.filter(e => e.kind === "event")
    readonly property var lessons: dayEvents.filter(e => e.kind === "lesson")
    readonly property var tasks: Assignments.on(day)
    readonly property var coming: {
        const here = new Set(dayEvents.map(e => e.id).concat(tasks.map(t => t.id)));
        return Calendars.upcoming(14).filter(u => !here.has(u.id) && !sameDay(new Date(u.start), day)).slice(0, 6);
    }
    readonly property var comingById: {
        const map = {};
        for (const u of coming)
            map[u.id] = u;
        return map;
    }
    // Plain strings keep the list in place when events refresh.
    readonly property var rows: {
        const out = exams.map(e => "x:" + e.id).concat(tasks.map(t => "t:" + t.id), others.map(e => "e:" + e.id));
        if (lessons.length > 0) {
            out.push("lh:");
            for (const e of lessons)
                out.push("l:" + e.id);
        }
        if (out.length === 0)
            out.push("n:");
        if (coming.length > 0) {
            out.push("uh:");
            for (const u of coming)
                out.push("u:" + u.id);
        }
        return out;
    }

    signal addRequested
    signal calendarsRequested
    signal eventPicked(e: var)
    signal taskPicked(t: var)

    function sameDay(a: date, b: date): bool {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    function clock(ms: double): string {
        return Qt.formatTime(new Date(ms), Qt.locale().timeFormat(Locale.ShortFormat));
    }

    function span(e: var): string {
        if (e.allDay)
            return Tr.tr("All day");
        return clock(e.start) + (e.end > e.start ? " – " + clock(e.end) : "");
    }

    function relative(ms: double): string {
        const d = new Date(ms);
        const now = new Date();
        const days = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - new Date(now.getFullYear(), now.getMonth(), now.getDate())) / 86400000);
        if (days < 0)
            return Tr.tr("Overdue");
        if (days === 0)
            return Tr.tr("Today");
        if (days === 1)
            return Tr.tr("Tomorrow");
        if (days < 7)
            return d.toLocaleDateString(Qt.locale(), "dddd");
        return d.toLocaleDateString(Qt.locale(), "ddd d MMM");
    }

    spacing: Tokens.spacing.small

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.isToday ? Tr.tr("Today") : root.day.toLocaleDateString(Qt.locale(), "dddd")
                font: Tokens.font.body.builders.large.size(22).weight(Font.DemiBold).build()
                color: Colours.palette.m3onSurface
            }

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.day.toLocaleDateString(Qt.locale(), "d MMMM yyyy")
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }

        IconButton {
            type: IconButton.Text
            isRound: true
            icon: "event_list"
            onClicked: root.calendarsRequested()
        }

        IconButton {
            type: IconButton.Tonal
            isRound: true
            icon: "add"
            onClicked: root.addRequested()
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
            readonly property string kind: modelData.slice(0, modelData.indexOf(":"))
            readonly property string key: modelData.slice(modelData.indexOf(":") + 1)
            readonly property var event: kind === "x" || kind === "e" || kind === "l" ? (Calendars.byId[key] ?? null) : null
            readonly property var task: kind === "t" ? (Assignments.byId[key] ?? null) : null
            readonly property var up: kind === "u" ? (root.comingById[key] ?? null) : null

            width: list.width
            implicitHeight: {
                switch (kind) {
                case "l":
                    return 30;
                case "lh":
                case "uh":
                    return 30;
                case "n":
                    return 40;
                default:
                    return 54;
                }
            }

            // Section headings and empty state
            StyledText {
                anchors.fill: parent
                anchors.topMargin: Tokens.padding.small
                visible: row.kind === "lh" || row.kind === "uh"
                verticalAlignment: Text.AlignVCenter
                text: row.kind === "lh" ? Tr.trN("%n lesson", "%n lessons", root.lessons.length) : Tr.tr("Coming up")
                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                color: Colours.palette.m3primary
            }

            StyledText {
                anchors.fill: parent
                visible: row.kind === "n"
                verticalAlignment: Text.AlignVCenter
                text: Tr.tr("Nothing planned")
                font: Tokens.font.body.medium
                color: Colours.palette.m3onSurfaceVariant
            }

            // Lesson: one compact line
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.small
                anchors.rightMargin: Tokens.padding.small
                visible: row.kind === "l" && row.event !== null
                spacing: Tokens.spacing.small
                opacity: row.event?.cancelled ? 0.5 : 1

                StyledText {
                    Layout.preferredWidth: 44
                    text: row.event ? root.clock(row.event.start) : ""
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }

                StyledRect {
                    implicitWidth: 8
                    implicitHeight: 8
                    radius: Tokens.rounding.full
                    color: row.event ? Calendars.accentOf(row.event) : "transparent"
                }

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: row.event ? Calendars.titleOf(row.event) + (row.event.cancelled ? " · " + Tr.tr("cancelled") : "") : ""
                    font: {
                        const f = Tokens.font.body.builders.medium.build();
                        f.strikeout = row.event?.cancelled ?? false;
                        return f;
                    }
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    text: row.event?.location ?? ""
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            StateLayer {
                anchors.fill: parent
                visible: row.kind === "l"
                radius: Tokens.rounding.small
                onClicked: root.eventPicked(row.event)
            }

            // Exam, event, homework or upcoming item: a card
            StyledRect {
                id: card

                readonly property bool exam: row.kind === "x" || (row.up?.kind === "test") || (row.task?.type === "exam") || (row.up?.task?.type === "exam")
                readonly property var theTask: row.task ?? row.up?.task ?? null
                readonly property color accent: {
                    if (row.event)
                        return Calendars.accentOf(row.event);
                    if (row.up)
                        return row.up.accent;
                    if (row.task)
                        return row.task.subject ? Subjects.colourOf(row.task.subject) : Colours.palette.m3primary;
                    return Colours.palette.m3primary;
                }

                anchors.fill: parent
                visible: (row.kind === "x" || row.kind === "e" || row.kind === "t" || row.kind === "u") && (row.event || row.task || row.up)
                radius: Tokens.rounding.large
                color: exam ? Qt.alpha(Colours.palette.m3error, 0.12) : Colours.tPalette.m3surfaceContainer
                opacity: card.theTask?.done ? 0.55 : 1

                StateLayer {
                    radius: parent.radius
                    onClicked: {
                        if (card.theTask)
                            root.taskPicked(card.theTask);
                        else if (row.event)
                            root.eventPicked(row.event);
                        else if (row.up?.event)
                            root.eventPicked(row.up.event);
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.rightMargin: Tokens.padding.small
                    spacing: Tokens.spacing.medium

                    // Homework gets a round check, everything else an icon or a colour bar.
                    Item {
                        implicitWidth: 24
                        implicitHeight: 24

                        StyledRect {
                            anchors.fill: parent
                            visible: card.theTask !== null
                            radius: Tokens.rounding.full
                            color: card.theTask?.done ? card.accent : "transparent"
                            border.width: 2
                            border.color: card.accent

                            MaterialIcon {
                                anchors.centerIn: parent
                                visible: card.theTask?.done ?? false
                                text: "check"
                                color: Colours.palette.m3surface
                                fontStyle: Tokens.font.icon.small
                            }

                            StateLayer {
                                radius: parent.radius
                                onClicked: Assignments.toggle(card.theTask.id)
                            }
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            visible: card.theTask === null && card.exam
                            text: "quiz"
                            fill: 1
                            color: Colours.palette.m3error
                            fontStyle: Tokens.font.icon.medium
                        }

                        StyledRect {
                            anchors.centerIn: parent
                            visible: card.theTask === null && !card.exam
                            implicitWidth: 4
                            implicitHeight: 24
                            radius: Tokens.rounding.full
                            color: card.accent
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: {
                                if (row.up)
                                    return row.up.title;
                                if (row.event)
                                    return Calendars.titleOf(row.event);
                                return row.task ? (row.task.title || Subjects.nameOf(row.task.subject)) : "";
                            }
                            font: {
                                const f = Tokens.font.body.builders.medium.build();
                                f.strikeout = card.theTask?.done ?? false;
                                return f;
                            }
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: {
                                if (row.up) {
                                    const when = root.relative(row.up.start) + (row.up.allDay ? "" : " · " + root.clock(row.up.start));
                                    return row.up.detail ? when + " · " + row.up.detail : when;
                                }
                                if (row.event) {
                                    const detail = Calendars.detailOf(row.event);
                                    return root.span(row.event) + (detail ? " · " + detail : "");
                                }
                                if (row.task) {
                                    const parts = [row.task.type === "exam" ? Tr.tr("Exam") : row.task.type === "reminder" ? Tr.tr("Reminder") : Tr.tr("Homework")];
                                    if (row.task.subject)
                                        parts.push(Subjects.nameOf(row.task.subject));
                                    if (row.task.hasTime)
                                        parts.push(root.clock(row.task.due));
                                    return parts.join(" · ");
                                }
                                return "";
                            }
                            font: Tokens.font.body.small
                            color: card.exam ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                        }
                    }
                }
            }
        }
    }
}
