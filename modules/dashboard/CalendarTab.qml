pragma ComponentBehavior: Bound

import "calendar"
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// Dashboard "Calendar" tab: a calendar for school and everything else.
//   Month - month grid (dots per lesson in subject colours, red mark on exam days) next to the
//           chosen day's agenda (exams, homework to tick off, events, lessons, coming up)
//   Week  - the timetable; click an empty slot to add something at that time
// Calendars come from links (school timetable from portal.sbl.ch, Google, Outlook, ...) and
// imported .ics files (services/Calendars.qml); homework and exams typed in by hand are in
// services/Assignments.qml. The shown month is shared with the small calendar of the Dashboard
// tab (screenState.dashboardDate). Scroll to change month or week, middle-click for today.
CustomMouseArea {
    id: root

    required property ScreenState screenState

    // The day whose agenda is shown, and the week the week view shows.
    property date selected: new Date()
    readonly property bool week: Calendars.view === "week"
    // Read by Content.qml: keyboard focus while a sheet with text fields is open.
    readonly property bool wantsInput: newSheet.open || sourcesSheet.open
    readonly property int firstDay: Qt.locale().firstDayOfWeek % 7
    readonly property date weekStart: {
        const offset = (selected.getDay() - firstDay + 7) % 7;
        return new Date(selected.getFullYear(), selected.getMonth(), selected.getDate() - offset);
    }
    readonly property bool onToday: {
        const now = new Date();
        if (week)
            return weekView.sameDay(weekStart, new Date(now.getFullYear(), now.getMonth(), now.getDate() - (now.getDay() - firstDay + 7) % 7));
        return now.getFullYear() === screenState.dashboardDate.getFullYear() && now.getMonth() === screenState.dashboardDate.getMonth() && monthView.sameDay(selected, now);
    }

    function shift(by: int): void {
        if (week) {
            selected = new Date(selected.getFullYear(), selected.getMonth(), selected.getDate() + by * 7);
            screenState.dashboardDate = new Date(selected.getFullYear(), selected.getMonth(), 1);
        } else {
            const d = screenState.dashboardDate;
            screenState.dashboardDate = new Date(d.getFullYear(), d.getMonth() + by, 1);
        }
    }

    function goToday(): void {
        screenState.dashboardDate = new Date();
        selected = new Date();
    }

    function isoWeek(d: date): int {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
        const start = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
        return Math.ceil(((t - start) / 86400000 + 1) / 7);
    }

    function minutesOf(ms: double): int {
        const d = new Date(ms);
        return d.getHours() * 60 + d.getMinutes();
    }

    function openNew(day: date, minutes: int, kind: string, subject: string): void {
        detailsSheet.open = false;
        newItem.openNew(day, minutes, kind);
        if (subject !== "")
            newItem.subject = subject;
        newSheet.open = true;
    }

    function openTask(t: var): void {
        newItem.openTask(t);
        newSheet.open = true;
    }

    function openEvent(e: var): void {
        details.event = e;
        detailsSheet.open = true;
    }

    function onWheel(event: WheelEvent): void {
        shift(event.angleDelta.y > 0 ? -1 : 1);
    }

    implicitWidth: 840
    implicitHeight: 470 + Tokens.padding.large * 2

    acceptedButtons: Qt.MiddleButton
    onClicked: goToday()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Item {
                Layout.fillWidth: true
                implicitHeight: title.implicitHeight
                clip: true

                StyledText {
                    id: title

                    width: parent.width
                    elide: Text.ElideRight
                    opacity: root.week ? weekView.animOpacity : monthView.animOpacity
                    transform: Translate {
                        x: root.week ? weekView.animTranslate : monthView.animTranslate
                    }
                    text: {
                        if (root.week) {
                            const s = weekView.shownWeek;
                            const e = new Date(s.getFullYear(), s.getMonth(), s.getDate() + 6);
                            return Tr.tr("Week %1").arg(root.isoWeek(s)) + "  ·  " + s.toLocaleDateString(Qt.locale(), "d MMM") + " – " + e.toLocaleDateString(Qt.locale(), "d MMM");
                        }
                        return Qt.locale().monthName(monthView.month) + " " + monthView.year;
                    }
                    font: Tokens.font.body.builders.large.size(28).weight(Font.DemiBold).build()
                    color: Colours.palette.m3onSurface
                }
            }

            IconTextButton {
                type: IconTextButton.Tonal
                checked: !root.week
                icon: "calendar_view_month"
                text: Tr.tr("Month")
                onClicked: Calendars.view = "month"
            }

            IconTextButton {
                type: IconTextButton.Tonal
                checked: root.week
                icon: "calendar_view_week"
                text: Tr.tr("Week")
                onClicked: Calendars.view = "week"
            }

            TextButton {
                type: TextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                text: Tr.tr("Today")
                disabled: root.onToday
                onClicked: root.goToday()
            }

            IconButton {
                type: IconButton.Text
                isRound: true
                icon: "chevron_left"
                onClicked: root.shift(-1)
            }

            IconButton {
                type: IconButton.Text
                isRound: true
                icon: "chevron_right"
                onClicked: root.shift(1)
            }
        }

        // Month: grid and the chosen day
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.week
            spacing: Tokens.spacing.large

            MonthView {
                id: monthView

                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                screenState: root.screenState
                selected: root.selected
                onPicked: day => {
                    root.selected = day;
                    if (day.getMonth() !== monthView.month)
                        root.screenState.dashboardDate = new Date(day.getFullYear(), day.getMonth(), 1);
                }
            }

            StyledRect {
                Layout.fillHeight: true
                implicitWidth: 1
                color: Colours.palette.m3outlineVariant
                opacity: 0.5
            }

            DayAgenda {
                Layout.fillHeight: true
                Layout.preferredWidth: 290
                day: root.selected
                onAddRequested: root.openNew(root.selected, -1, "event", "")
                onCalendarsRequested: {
                    sources.reset();
                    sourcesSheet.open = true;
                }
                onEventPicked: e => root.openEvent(e)
                onTaskPicked: t => root.openTask(t)
            }
        }

        // Week: the timetable
        WeekView {
            id: weekView

            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.week
            weekStart: root.weekStart
            selected: root.selected
            onSlotPicked: (day, minutes) => root.openNew(day, minutes, "event", "")
            onEventPicked: e => root.openEvent(e)
            onTaskPicked: t => root.openTask(t)
            onDayPicked: day => {
                root.selected = day;
                Calendars.view = "month";
                root.screenState.dashboardDate = new Date(day.getFullYear(), day.getMonth(), 1);
            }
        }
    }

    // Week view: calendars button and "+" in the corner, where the agenda has them in month view.
    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.large
        visible: root.week
        spacing: Tokens.spacing.small
        z: 5

        IconButton {
            type: IconButton.Tonal
            isRound: true
            icon: "event_list"
            onClicked: {
                sources.reset();
                sourcesSheet.open = true;
            }
        }

        IconButton {
            type: IconButton.Filled
            isRound: true
            icon: "add"
            onClicked: root.openNew(root.selected, -1, "event", "")
        }
    }

    Sheet {
        id: newSheet

        title: newItem.editKind !== "" ? Tr.tr("Edit") : Tr.tr("New")
        onClosed: open = false

        NewItem {
            id: newItem

            Layout.fillWidth: true
            Layout.fillHeight: true
            onSaved: newSheet.open = false
        }
    }

    Sheet {
        id: detailsSheet

        title: details.event?.kind === "lesson" ? Tr.tr("Lesson") : details.event?.kind === "test" ? Tr.tr("Exam") : Tr.tr("Event")
        onClosed: open = false

        EventDetails {
            id: details

            Layout.fillWidth: true
            Layout.fillHeight: true
            onDone: detailsSheet.open = false
            onAddRequested: (kind, subject, start) => root.openNew(new Date(start), root.minutesOf(start), kind, subject)
            onEditRequested: e => {
                detailsSheet.open = false;
                newItem.openEvent(Calendars.localEvents.find(x => x.id === e.id) ?? e);
                newSheet.open = true;
            }
        }
    }

    Sheet {
        id: sourcesSheet

        title: Tr.tr("Calendars")
        onClosed: open = false

        CalendarSources {
            id: sources

            Layout.fillWidth: true
            Layout.fillHeight: true
            onImportRequested: (kind, name) => Calendars.requestImport(kind, name)
        }
    }
}
