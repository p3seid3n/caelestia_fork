pragma ComponentBehavior: Bound

import "calendar"
import QtQuick
import QtQuick.Layouts
import M3Shapes
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// Dashboard "Calendar" tab: a big month (ISO week numbers where weeks start on Monday, dots for days
// with events) and a panel with the chosen day's agenda. Events come from the user's own list and from
// online calendars subscribed to by link (services/Calendars.qml).
// The shown month is shared with the small calendar of the Dashboard tab (screenState.dashboardDate).
CustomMouseArea {
    id: root

    required property ScreenState screenState

    // The day whose agenda is shown on the right.
    property date selected: new Date()

    readonly property int year: screenState.dashboardDate.getFullYear()
    readonly property int month: screenState.dashboardDate.getMonth()
    // 0 = Sunday ... 6 = Saturday, as Date.getDay(); `% 7` also covers a locale that reports Sunday as 7.
    readonly property int firstDay: Qt.locale().firstDayOfWeek % 7
    readonly property bool showWeeks: firstDay === 1
    readonly property bool onToday: {
        const now = new Date();
        return now.getFullYear() === year && now.getMonth() === month;
    }
    // Six full weeks, starting with the week the 1st falls in.
    readonly property var days: {
        const offset = (new Date(year, month, 1).getDay() - firstDay + 7) % 7;
        return Array.from({
            length: 42
        }, (_, i) => new Date(year, month, 1 - offset + i));
    }

    function shiftMonth(by: int): void {
        screenState.dashboardDate = new Date(year, month + by, 1);
    }

    function isoWeek(d: date): int {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
        const start = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
        return Math.ceil(((t - start) / 86400000 + 1) / 7);
    }

    function goToday(): void {
        screenState.dashboardDate = new Date();
        selected = new Date();
    }

    function sameDay(a: date, b: date): bool {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    function onWheel(event: WheelEvent): void {
        shiftMonth(event.angleDelta.y > 0 ? -1 : 1);
    }

    implicitWidth: 840
    // The sheets need some room however short the month is.
    implicitHeight: Math.max(layout.implicitHeight, 450) + Tokens.padding.large * 2

    acceptedButtons: Qt.MiddleButton
    onClicked: goToday()

    // Ask the drawer window for keyboard focus while a sheet with text fields is open.
    Binding {
        target: root.screenState
        property: "dashboardInput"
        value: eventSheet.open || sourcesSheet.open
        restoreMode: Binding.RestoreValue
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.large

        ColumnLayout {
            id: layout

            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: Tokens.spacing.small

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: Qt.locale().monthName(root.month) + " " + root.year
                    font: Tokens.font.body.builders.large.size(28).weight(Font.DemiBold).build()
                    color: Colours.palette.m3onSurface
                }

                TextButton {
                    type: TextButton.Tonal
                    horizontalPadding: Tokens.padding.extraLarge
                    text: Tr.tr("Today")
                    disabled: root.onToday && root.sameDay(root.selected, new Date())
                    onClicked: root.goToday()
                }

                IconButton {
                    type: IconButton.Text
                    isRound: true
                    icon: "chevron_left"
                    onClicked: root.shiftMonth(-1)
                }

                IconButton {
                    type: IconButton.Text
                    isRound: true
                    icon: "chevron_right"
                    onClicked: root.shiftMonth(1)
                }
            }

            // Weekday names
            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                Item {
                    visible: root.showWeeks
                    implicitWidth: 44
                }

                Repeater {
                    model: 7

                    StyledText {
                        required property int index
                        readonly property int dayOfWeek: (root.firstDay + index) % 7

                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        horizontalAlignment: Text.AlignHCenter
                        text: Qt.locale().dayName(dayOfWeek, Locale.ShortFormat)
                        font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                        color: dayOfWeek === 0 || dayOfWeek === 6 ? Colours.palette.m3tertiary : Colours.palette.m3onSurfaceVariant
                    }
                }
            }

            // Weeks
            Repeater {
                model: 6

                RowLayout {
                    id: week

                    required property int index

                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        visible: root.showWeeks
                        Layout.preferredWidth: 44
                        horizontalAlignment: Text.AlignHCenter
                        text: root.isoWeek(root.days[week.index * 7 + 3])
                        font: Tokens.font.body.small
                        color: Colours.palette.m3outline
                    }

                    Repeater {
                        model: 7

                        Item {
                            id: cell

                            required property int index
                            readonly property date day: root.days[week.index * 7 + index]
                            readonly property bool today: root.sameDay(day, new Date())
                            readonly property bool inMonth: day.getMonth() === root.month
                            readonly property bool weekend: day.getDay() === 0 || day.getDay() === 6
                            readonly property bool chosen: root.sameDay(day, root.selected)
                            readonly property var dots: Calendars.dotsOn(day)

                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 54

                            MaterialShape {
                                anchors.centerIn: parent
                                implicitSize: Math.min(cell.width, cell.height) - Tokens.padding.extraSmall
                                shape: MaterialShape.Sunny
                                color: Colours.palette.m3primary
                                opacity: cell.today ? 1 : 0

                                Behavior on opacity {
                                    Anim {
                                        type: Anim.DefaultEffects
                                    }
                                }
                            }

                            // The chosen day (today is already marked by its shape).
                            StyledRect {
                                anchors.centerIn: parent
                                implicitWidth: Math.min(cell.width, cell.height) - Tokens.padding.extraSmall
                                implicitHeight: implicitWidth
                                radius: Tokens.rounding.full
                                color: "transparent"
                                border.width: 2
                                border.color: Colours.palette.m3primary
                                opacity: cell.chosen && !cell.today ? 1 : 0

                                Behavior on opacity {
                                    Anim {
                                        type: Anim.DefaultEffects
                                    }
                                }
                            }

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: cell.dots.length > 0 ? -4 : 0
                                text: cell.day.getDate()
                                font: cell.today ? Tokens.font.body.builders.medium.weight(Font.DemiBold).build() : Tokens.font.body.medium
                                color: cell.today ? Colours.palette.m3onPrimary : cell.weekend ? Colours.palette.m3tertiary : Colours.palette.m3onSurface
                                opacity: cell.inMonth || cell.today ? 1 : 0.35
                            }

                            // One dot per calendar that has something on this day.
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: Tokens.padding.small
                                spacing: 3
                                opacity: cell.inMonth ? 1 : 0.4

                                Repeater {
                                    model: cell.dots

                                    StyledRect {
                                        required property string modelData

                                        implicitWidth: 5
                                        implicitHeight: 5
                                        radius: Tokens.rounding.full
                                        color: cell.today ? Colours.palette.m3onPrimary : Calendars.colourFor(modelData)
                                    }
                                }
                            }

                            // Choose the day; one of the neighbouring month also jumps to that month.
                            StateLayer {
                                radius: Tokens.rounding.large
                                onClicked: {
                                    root.selected = cell.day;
                                    if (!cell.inMonth)
                                        root.screenState.dashboardDate = new Date(cell.day.getFullYear(), cell.day.getMonth(), 1);
                                }
                            }
                        }
                    }
                }
            }
        }

    // Chosen day
    StyledRect {
        Layout.fillHeight: true
        implicitWidth: 1
        color: Colours.palette.m3outlineVariant
        opacity: 0.5
    }

    DayAgenda {
        Layout.fillHeight: true
        Layout.preferredWidth: 280
        day: root.selected
        onAddRequested: {
            newEvent.day = root.selected;
            newEvent.reset();
            eventSheet.open = true;
        }
        onCalendarsRequested: {
            sources.reset();
            sourcesSheet.open = true;
        }
    }
    }

    Sheet {
        id: eventSheet

        title: Tr.tr("New event")
        onClosed: open = false

        NewEvent {
            id: newEvent

            Layout.fillWidth: true
            Layout.fillHeight: true
            onSaved: eventSheet.open = false
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
        }
    }
}
