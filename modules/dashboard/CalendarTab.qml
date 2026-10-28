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
//   Month - Caelestia's own month calendar on the left (dots per lesson, red mark on exam days),
//           the chosen day's itinerary on the right
//   Week  - the timetable; click an empty slot to add something at that time
// Calendars come from links (school timetable from portal.sbl.ch, Google, Outlook, ...) and
// imported .ics files (services/Calendars.qml); homework and exams typed in by hand are in
// services/Assignments.qml. Scroll to change month or week, middle-click for today.
//
// Month and week are both kept once built (the one not shown is built in the background), so
// switching is a shared-axis zoom: going to the week zooms in (the month grows and fades, the week
// grows into place), going back zooms out. Sheets are built when they first open.
CustomMouseArea {
    id: root

    required property ScreenState screenState

    // The day whose itinerary is shown, and whose week the week view shows.
    property date selected: new Date()
    readonly property bool week: Calendars.view === "week"
    // Read by Content.qml: keyboard focus while a sheet with text fields is open.
    readonly property bool wantsInput: newSheet.open || sourcesSheet.open
    readonly property int firstDay: Qt.locale().firstDayOfWeek % 7
    readonly property date weekStart: weekStartOf(selected)

    function weekStartOf(d: date): date {
        const offset = (d.getDay() - firstDay + 7) % 7;
        return new Date(d.getFullYear(), d.getMonth(), d.getDate() - offset);
    }

    function sameDay(a: date, b: date): bool {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
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

    function pick(day: date): void {
        selected = day;
        if (day.getMonth() !== screenState.dashboardDate.getMonth() || day.getFullYear() !== screenState.dashboardDate.getFullYear())
            screenState.dashboardDate = new Date(day.getFullYear(), day.getMonth(), 1);
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
        newSheet.open = true;
        const item = newLoader.item as NewItem;
        item.openNew(day, minutes, kind);
        if (subject !== "")
            item.subject = subject;
    }

    function openTask(t: var): void {
        newSheet.open = true;
        (newLoader.item as NewItem).openTask(t);
    }

    function openEvent(e: var): void {
        detailsSheet.open = true;
        (detailsLoader.item as EventDetails).event = e;
    }

    function openSources(): void {
        sourcesSheet.open = true;
        (sourcesLoader.item as CalendarSources).reset();
    }

    function onWheel(event: WheelEvent): void {
        shift(event.angleDelta.y > 0 ? -1 : 1);
    }

    implicitWidth: 840
    implicitHeight: 470 + Tokens.padding.large * 2

    acceptedButtons: Qt.MiddleButton
    onClicked: goToday()

    ViewLoader {
        shown: !root.week
        hiddenScale: 1.05
        asynchronous: root.week
        sourceComponent: monthLayout
    }

    ViewLoader {
        shown: root.week
        hiddenScale: 0.95
        asynchronous: !root.week
        sourceComponent: weekLayout
    }

    Component {
        id: monthLayout

        RowLayout {
            spacing: Tokens.spacing.large

            CaelestiaMonth {
                Layout.preferredWidth: 380
                Layout.alignment: Qt.AlignTop
                screenState: root.screenState
                selected: root.selected
                onPicked: day => root.pick(day)
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                // Long event titles must not push the calendar aside.
                Layout.preferredWidth: 1
                spacing: Tokens.spacing.small

                ViewSwitch {
                    Layout.alignment: Qt.AlignRight
                }

                DayAgenda {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    day: root.selected
                    onAddRequested: root.openNew(root.selected, -1, "event", "")
                    onCalendarsRequested: root.openSources()
                    onEventPicked: e => root.openEvent(e)
                    onTaskPicked: t => root.openTask(t)
                }
            }
        }
    }

    Component {
        id: weekLayout

        Item {
            ColumnLayout {
                anchors.fill: parent
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
                            opacity: weekView.animOpacity
                            transform: Translate {
                                x: weekView.animTranslate
                            }
                            text: {
                                const s = weekView.shownWeek;
                                const e = new Date(s.getFullYear(), s.getMonth(), s.getDate() + 6);
                                return Tr.tr("Week %1").arg(root.isoWeek(s)) + "  ·  " + s.toLocaleDateString(Qt.locale(), "d MMM") + " – " + e.toLocaleDateString(Qt.locale(), "d MMM");
                            }
                            font: Tokens.font.body.builders.large.size(24).weight(Font.DemiBold).build()
                            color: Colours.palette.m3onSurface
                        }
                    }

                    ViewSwitch {}

                    TextButton {
                        type: TextButton.Tonal
                        horizontalPadding: Tokens.padding.extraLarge
                        text: Tr.tr("Today")
                        disabled: root.sameDay(root.weekStart, root.weekStartOf(new Date()))
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

                WeekView {
                    id: weekView

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    weekStart: root.weekStart
                    selected: root.selected
                    onSlotPicked: (day, minutes) => root.openNew(day, minutes, "event", "")
                    onEventPicked: e => root.openEvent(e)
                    onTaskPicked: t => root.openTask(t)
                    onDayPicked: day => {
                        root.pick(day);
                        Calendars.view = "month";
                    }
                }
            }

            // Calendars and "+" in the corner, where the itinerary has them in month view.
            Row {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: Tokens.spacing.small
                z: 5

                IconButton {
                    type: IconButton.Tonal
                    isRound: true
                    icon: "event_list"
                    onClicked: root.openSources()
                }

                IconButton {
                    type: IconButton.Filled
                    isRound: true
                    icon: "add"
                    onClicked: root.openNew(root.selected, -1, "event", "")
                }
            }
        }
    }

    Sheet {
        id: newSheet

        title: (newLoader.item as NewItem)?.editKind ? Tr.tr("Edit") : Tr.tr("New")
        onClosed: open = false

        Loader {
            id: newLoader

            Layout.fillWidth: true
            Layout.fillHeight: true
            active: newSheet.open || newSheet.visible

            sourceComponent: NewItem {
                onSaved: newSheet.open = false
            }
        }
    }

    Sheet {
        id: detailsSheet

        readonly property var event: (detailsLoader.item as EventDetails)?.event ?? null

        title: event?.kind === "lesson" ? Tr.tr("Lesson") : event?.kind === "test" ? Tr.tr("Exam") : event?.kind === "message" ? Tr.tr("Notice") : Tr.tr("Event")
        onClosed: open = false

        Loader {
            id: detailsLoader

            Layout.fillWidth: true
            Layout.fillHeight: true
            active: detailsSheet.open || detailsSheet.visible

            sourceComponent: EventDetails {
                onDone: detailsSheet.open = false
                onAddRequested: (kind, subject, start) => root.openNew(new Date(start), root.minutesOf(start), kind, subject)
                onEditRequested: e => {
                    detailsSheet.open = false;
                    newSheet.open = true;
                    (newLoader.item as NewItem).openEvent(Calendars.localEvents.find(x => x.id === e.id) ?? e);
                }
            }
        }
    }

    Sheet {
        id: sourcesSheet

        title: Tr.tr("Calendars")
        onClosed: open = false

        Loader {
            id: sourcesLoader

            Layout.fillWidth: true
            Layout.fillHeight: true
            active: sourcesSheet.open || sourcesSheet.visible

            sourceComponent: CalendarSources {
                onImportRequested: (kind, name) => Calendars.requestImport(kind, name)
            }
        }
    }

    // One of the two views; the other one fades and zooms away.
    component ViewLoader: Loader {
        required property bool shown
        required property real hiddenScale

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        opacity: shown ? 1 : 0
        scale: shown ? 1 : hiddenScale
        visible: opacity > 0
        enabled: shown

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on scale {
            Anim {
                type: Anim.DefaultSpatial
            }
        }
    }

    // Month / week as one segmented button; the selection slides between the halves.
    component ViewSwitch: StyledRect {
        id: viewSwitch

        implicitWidth: monthSeg.implicitWidth + weekSeg.implicitWidth + Tokens.padding.extraSmall * 2
        implicitHeight: Math.max(monthSeg.implicitHeight, weekSeg.implicitHeight) + Tokens.padding.extraSmall * 2
        radius: Tokens.rounding.full
        color: Colours.tPalette.m3surfaceContainerHigh

        StyledRect {
            x: Tokens.padding.extraSmall + (root.week ? monthSeg.width : 0)
            y: Tokens.padding.extraSmall
            width: root.week ? weekSeg.width : monthSeg.width
            height: parent.height - Tokens.padding.extraSmall * 2
            radius: Tokens.rounding.full
            color: Colours.palette.m3secondaryContainer

            Behavior on x {
                Anim {
                    type: Anim.FastSpatial
                }
            }

            Behavior on width {
                Anim {
                    type: Anim.FastSpatial
                }
            }
        }

        Row {
            anchors.centerIn: parent

            Segment {
                id: monthSeg

                icon: "calendar_view_month"
                text: Tr.tr("Month")
                selected: !root.week
                onClicked: Calendars.view = "month"
            }

            Segment {
                id: weekSeg

                icon: "calendar_view_week"
                text: Tr.tr("Week")
                selected: root.week
                onClicked: Calendars.view = "week"
            }
        }
    }

    component Segment: Item {
        id: segment

        property string icon
        property string text
        property bool selected

        signal clicked

        implicitWidth: segRow.implicitWidth + Tokens.padding.large * 2
        implicitHeight: segRow.implicitHeight + Tokens.padding.small * 2

        StateLayer {
            radius: Tokens.rounding.full
            onClicked: segment.clicked()
        }

        Row {
            id: segRow

            anchors.centerIn: parent
            spacing: Tokens.spacing.small

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: segment.icon
                fill: segment.selected ? 1 : 0
                color: segment.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: segment.text
                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                color: segment.selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
            }
        }
    }
}
