pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.containers
import qs.services

// The week as a timetable: lessons in their subject's colours, exams outlined in red, cancelled
// lessons struck through, other calendars' events tinted with their calendar colour and timed
// homework as small pills. Clicking an empty slot asks for a new entry at that time (rounded to a
// quarter hour); a ghost block shows where it would go. Changing week slides like the month grid.
Item {
    id: root

    property date weekStart: new Date()
    property date selected: new Date()

    property date shownWeek: weekStart
    readonly property int animDirection: weekStart > shownWeek ? -1 : 1
    property real animTranslate
    property real animOpacity: 1

    readonly property real gutter: 40
    readonly property real hourHeight: 44
    readonly property var allDays: Array.from({
        length: 7
    }, (_, i) => new Date(shownWeek.getFullYear(), shownWeek.getMonth(), shownWeek.getDate() + i))
    // Saturday and Sunday only take room when something happens on them.
    readonly property var days: {
        const weekendFree = allDays.filter(d => d.getDay() === 0 || d.getDay() === 6).every(d => Calendars.eventsOn(d).length === 0 && Assignments.on(d).length === 0);
        return weekendFree ? allDays.filter(d => d.getDay() !== 0 && d.getDay() !== 6) : allDays;
    }
    readonly property real dayWidth: (width - gutter) / Math.max(1, days.length)
    // Hours shown: at least 7:00 to 18:00, more when the week needs it.
    readonly property var range: {
        let first = 7;
        let last = 18;
        for (const d of days) {
            for (const e of Calendars.eventsOn(d)) {
                if (e.allDay)
                    continue;
                const s = new Date(Math.max(e.start, d.getTime()));
                const end = new Date(Math.min(e.end, d.getTime() + 86400000 - 1));
                first = Math.min(first, s.getHours());
                last = Math.max(last, end.getHours() + (end.getMinutes() > 0 ? 1 : 0));
            }
        }
        return [first, Math.min(24, Math.max(last, first + 1))];
    }
    readonly property int firstHour: range[0]
    readonly property int lastHour: range[1]

    signal slotPicked(day: date, minutes: int)
    signal eventPicked(e: var)
    signal taskPicked(t: var)
    signal dayPicked(day: date)

    function sameDay(a: date, b: date): bool {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    function yOf(ms: double, day: date): real {
        const minutes = (ms - day.getTime()) / 60000;
        return (minutes / 60 - firstHour) * hourHeight;
    }

    // Timed items of a day with their column inside groups of overlapping items.
    function layoutDay(day: date): var {
        const items = [];
        for (const e of Calendars.eventsOn(day)) {
            if (!e.allDay)
                items.push({
                    kind: e.kind,
                    start: Math.max(e.start, day.getTime()),
                    end: Math.max(Math.min(e.end, day.getTime() + 86400000), Math.max(e.start, day.getTime()) + 15 * 60000),
                    event: e,
                    task: null
                });
        }
        for (const t of Assignments.on(day)) {
            if (t.hasTime)
                items.push({
                    kind: "task",
                    start: t.due,
                    end: t.due + 30 * 60000,
                    event: null,
                    task: t
                });
        }
        items.sort((a, b) => a.start - b.start || b.end - a.end);
        let group = [];
        let groupEnd = 0;
        const columnsEnd = [];
        const finish = () => {
            const cols = Math.max(1, columnsEnd.length);
            for (const g of group)
                g.cols = cols;
            group = [];
            columnsEnd.length = 0;
        };
        for (const it of items) {
            if (group.length > 0 && it.start >= groupEnd)
                finish();
            let col = columnsEnd.findIndex(end => end <= it.start);
            if (col < 0) {
                col = columnsEnd.length;
                columnsEnd.push(it.end);
            } else {
                columnsEnd[col] = it.end;
            }
            it.col = col;
            group.push(it);
            groupEnd = Math.max(groupEnd, it.end);
        }
        finish();
        return items;
    }

    function scrollToFirst(): void {
        let first = 24 * 60;
        for (const d of days)
            for (const it of layoutDay(d))
                first = Math.min(first, (it.start - d.getTime()) / 60000);
        if (first === 24 * 60)
            first = 8 * 60;
        flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, (first / 60 - firstHour) * hourHeight - Tokens.padding.small));
    }

    onShownWeekChanged: Qt.callLater(scrollToFirst)
    Component.onCompleted: Qt.callLater(scrollToFirst)

    Anim {
        id: trOutAnim

        running: false
        target: root
        property: "animTranslate"
        to: root.Tokens.padding.extraLarge * root.animDirection
        type: Anim.FastSpatial
    }

    Behavior on shownWeek {
        SequentialAnimation {
            ParallelAnimation {
                ScriptAction {
                    script: Qt.callLater(() => trOutAnim.start())
                }
                Anim {
                    target: root
                    property: "animOpacity"
                    to: 0
                    type: Anim.FastEffects
                }
            }
            ScriptAction {
                script: {
                    trOutAnim.complete();
                    root.animTranslate = root.Tokens.padding.extraLarge * -root.animDirection;
                }
            }
            PropertyAction {}
            ParallelAnimation {
                Anim {
                    target: root
                    property: "animTranslate"
                    to: 0
                    type: Anim.DefaultSpatial
                }
                Anim {
                    target: root
                    property: "animOpacity"
                    to: 1
                    type: Anim.DefaultEffects
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacing.extraSmall
        opacity: root.animOpacity
        transform: Translate {
            x: root.animTranslate
        }

        // Day headers
        Row {
            Layout.leftMargin: root.gutter

            Repeater {
                model: root.days

                Item {
                    id: head

                    required property date modelData
                    readonly property bool today: root.sameDay(modelData, new Date())

                    width: root.dayWidth
                    height: 44

                    StateLayer {
                        radius: Tokens.rounding.large
                        onClicked: root.dayPicked(head.modelData)
                    }

                    Column {
                        anchors.centerIn: parent

                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.locale().dayName(head.modelData.getDay(), Locale.ShortFormat)
                            font: Tokens.font.body.small
                            color: head.today ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                        }

                        StyledRect {
                            anchors.horizontalCenter: parent.horizontalCenter
                            implicitWidth: 26
                            implicitHeight: 22
                            radius: Tokens.rounding.full
                            color: head.today ? Colours.palette.m3primary : "transparent"

                            StyledText {
                                anchors.centerIn: parent
                                text: head.modelData.getDate()
                                font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                                color: head.today ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                            }
                        }
                    }
                }
            }
        }

        // All-day events and homework without a time
        Row {
            id: allDayRow

            readonly property bool any: root.days.some(d => Calendars.eventsOn(d).some(e => e.allDay) || Assignments.on(d).some(t => !t.hasTime))

            Layout.fillWidth: true
            visible: any

            StyledText {
                width: root.gutter
                anchors.verticalCenter: parent.verticalCenter
                text: Tr.tr("all day")
                font: Tokens.font.body.small
                color: Colours.palette.m3outline
            }

            Repeater {
                model: root.days

                Column {
                    id: allDayCol

                    required property date modelData
                    readonly property var items: Calendars.eventsOn(modelData).filter(e => e.allDay).map(e => ({
                                event: e,
                                task: null
                            })).concat(Assignments.on(modelData).filter(t => !t.hasTime).map(t => ({
                                event: null,
                                task: t
                            })))

                    width: root.dayWidth
                    spacing: 2

                    Repeater {
                        model: allDayCol.items.slice(0, 2)

                        StyledRect {
                            id: chip

                            required property var modelData
                            readonly property color accent: modelData.event ? Calendars.accentOf(modelData.event) : (modelData.task.subject ? Subjects.colourOf(modelData.task.subject) : Colours.palette.m3primary)

                            width: root.dayWidth - 4
                            x: 2
                            implicitHeight: 20
                            radius: Tokens.rounding.small
                            color: Qt.alpha(accent, modelData.task ? 0 : 0.25)
                            border.width: modelData.task ? 1 : 0
                            border.color: accent
                            opacity: modelData.task?.done ? 0.5 : 1

                            StateLayer {
                                radius: parent.radius
                                onClicked: chip.modelData.event ? root.eventPicked(chip.modelData.event) : root.taskPicked(chip.modelData.task)
                            }

                            StyledText {
                                anchors.fill: parent
                                anchors.leftMargin: Tokens.padding.small
                                anchors.rightMargin: Tokens.padding.small
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                                text: chip.modelData.event ? Calendars.titleOf(chip.modelData.event) : (chip.modelData.task.title || Subjects.nameOf(chip.modelData.task.subject))
                                font.pointSize: Tokens.font.body.small.pointSize * 0.92
                                font.strikeout: chip.modelData.task?.done ?? false
                                color: Colours.palette.m3onSurface
                            }
                        }
                    }

                    StyledText {
                        visible: allDayCol.items.length > 2
                        x: Tokens.padding.small
                        text: "+" + (allDayCol.items.length - 2)
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }
        }

        StyledFlickable {
            id: flick

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: (root.lastHour - root.firstHour) * root.hourHeight
            boundsBehavior: Flickable.StopAtBounds

            // Hour lines and labels
            Repeater {
                model: root.lastHour - root.firstHour + 1

                Item {
                    id: hourLine

                    required property int index

                    y: index * root.hourHeight
                    width: flick.width
                    height: 1

                    StyledText {
                        x: 0
                        width: root.gutter - Tokens.padding.small
                        y: -height / 2
                        horizontalAlignment: Text.AlignRight
                        visible: hourLine.index > 0 && hourLine.index < root.lastHour - root.firstHour
                        text: (root.firstHour + hourLine.index < 10 ? "0" : "") + (root.firstHour + hourLine.index) + ":00"
                        font.pointSize: Tokens.font.body.small.pointSize * 0.9
                        color: Colours.palette.m3outline
                    }

                    StyledRect {
                        x: root.gutter
                        width: parent.width - root.gutter
                        height: 1
                        color: Colours.palette.m3outlineVariant
                        opacity: 0.5
                    }
                }
            }

            // Days
            Repeater {
                model: root.days

                Item {
                    id: column

                    required property date modelData
                    required property int index
                    readonly property bool today: root.sameDay(modelData, new Date())
                    readonly property var items: root.layoutDay(modelData)

                    x: root.gutter + index * root.dayWidth
                    width: root.dayWidth
                    height: flick.contentHeight

                    StyledRect {
                        anchors.fill: parent
                        color: Colours.palette.m3primary
                        opacity: column.today ? 0.05 : 0
                    }

                    StyledRect {
                        width: 1
                        height: parent.height
                        color: Colours.palette.m3outlineVariant
                        opacity: 0.5
                    }

                    // Empty slot: hover shows where a new entry would go, click adds it.
                    MouseArea {
                        id: slotArea

                        readonly property int slotMinutes: Math.max(0, Math.min(24 * 60 - 15, root.firstHour * 60 + Math.floor(mouseY / root.hourHeight * 4) * 15))

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.slotPicked(column.modelData, slotMinutes)
                    }

                    StyledRect {
                        x: 2
                        y: (slotArea.slotMinutes / 60 - root.firstHour) * root.hourHeight
                        width: parent.width - 4
                        height: root.hourHeight
                        radius: Tokens.rounding.small
                        color: Qt.alpha(Colours.palette.m3primary, 0.12)
                        border.width: 1
                        border.color: Qt.alpha(Colours.palette.m3primary, 0.5)
                        visible: slotArea.containsMouse

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "add"
                            color: Colours.palette.m3primary
                        }
                    }

                    Repeater {
                        model: column.items

                        Block {
                            required property var modelData

                            item: modelData
                            day: column.modelData
                        }
                    }

                    // Now
                    StyledRect {
                        readonly property real nowY: root.yOf(Time.date.getTime(), column.modelData)

                        visible: column.today && nowY >= 0 && nowY <= parent.height
                        y: nowY - 1
                        width: parent.width
                        height: 2
                        color: Colours.palette.m3error

                        StyledRect {
                            x: -4
                            y: -3
                            implicitWidth: 8
                            implicitHeight: 8
                            radius: Tokens.rounding.full
                            color: Colours.palette.m3error
                        }
                    }
                }
            }
        }
    }

    component Block: StyledRect {
        id: block

        required property var item
        required property date day
        readonly property var e: item.event
        readonly property var t: item.task
        readonly property bool isTask: t !== null
        readonly property bool isTest: item.kind === "test"
        readonly property bool cancelled: e?.cancelled ?? false
        readonly property string subject: e?.subject ?? t?.subject ?? ""
        readonly property color accent: isTask ? (subject ? Subjects.colourOf(subject) : Colours.palette.m3primary) : Calendars.accentOf(e)
        readonly property bool compact: height < 34
        readonly property real columnWidth: (root.dayWidth - 4) / item.cols

        x: 2 + item.col * columnWidth
        y: root.yOf(item.start, day) + 1
        width: columnWidth - 2
        height: Math.max(16, (item.end - item.start) / 3600000 * root.hourHeight - 2)
        radius: isTask ? Tokens.rounding.full : Tokens.rounding.small
        color: {
            if (isTask)
                return Colours.tPalette.m3surfaceContainerHighest;
            if (e.kind === "lesson" || isTest)
                return subject ? Subjects.containerOf(subject) : Colours.palette.m3secondaryContainer;
            return Qt.alpha(accent, 0.28);
        }
        border.width: isTest ? 2 : isTask ? 1 : 0
        border.color: isTest ? Colours.palette.m3error : accent
        opacity: cancelled || (t?.done ?? false) ? 0.45 : 1
        clip: true

        StateLayer {
            radius: parent.radius
            onClicked: block.isTask ? root.taskPicked(block.t) : root.eventPicked(block.e)
        }

        // Calendar colour bar for events from other calendars
        StyledRect {
            visible: !block.isTask && block.e.kind === "event"
            width: 3
            height: parent.height
            color: block.accent
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: Tokens.padding.small + (block.isTask ? 2 : 0)
            anchors.rightMargin: Tokens.padding.extraSmall
            anchors.topMargin: block.compact ? 0 : 2
            spacing: 0

            Row {
                width: parent.width
                spacing: 2

                MaterialIcon {
                    visible: block.isTest || block.isTask
                    anchors.verticalCenter: parent.verticalCenter
                    text: block.isTest || block.t?.type === "exam" ? "quiz" : block.t?.done ? "check_circle" : "assignment"
                    color: block.isTest ? Colours.palette.m3error : block.accent
                    fontStyle: Tokens.font.icon.small
                }

                StyledText {
                    width: parent.width - (block.isTest || block.isTask ? 18 : 0)
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: {
                        if (block.isTask)
                            return block.t.title || Subjects.nameOf(block.t.subject);
                        // Narrow columns get the subject's short name.
                        if (block.e.kind === "lesson" && block.subject && block.width < 70)
                            return Subjects.subjects[block.subject]?.short ?? Calendars.titleOf(block.e);
                        return Calendars.titleOf(block.e);
                    }
                    font: {
                        const f = Tokens.font.body.builders.small.weight(Font.DemiBold).build();
                        f.strikeout = block.cancelled || (block.t?.done ?? false);
                        return f;
                    }
                    color: block.isTask || block.e.kind === "event" ? Colours.palette.m3onSurface : (block.subject ? Subjects.onContainerOf(block.subject) : Colours.palette.m3onSecondaryContainer)
                }
            }

            StyledText {
                width: parent.width
                visible: !block.compact && !block.isTask && (block.e.location ?? "") !== ""
                elide: Text.ElideRight
                text: block.e?.location ?? ""
                font.pointSize: Tokens.font.body.small.pointSize * 0.9
                color: block.isTask || block.e?.kind === "event" ? Colours.palette.m3onSurfaceVariant : (block.subject ? Subjects.onContainerOf(block.subject) : Colours.palette.m3onSecondaryContainer)
                opacity: 0.8
            }
        }
    }
}
