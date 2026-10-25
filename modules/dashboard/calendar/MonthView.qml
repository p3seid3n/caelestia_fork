pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import M3Shapes
import Caelestia.Config
import qs.components
import qs.services

// The month grid of the Calendar tab. Changing month animates exactly like Caelestia's small
// dashboard calendar: the grid slides out to one side while fading, then slides in from the other.
// Under each day: one dot per lesson in its subject's colour (and per other calendar); a red mark
// in the corner when an exam is due.
Item {
    id: root

    required property ScreenState screenState
    property date selected: new Date()

    // The month on screen; it follows screenState.dashboardDate through the animation below.
    property date shownDate: screenState.dashboardDate
    readonly property int year: shownDate.getFullYear()
    readonly property int month: shownDate.getMonth()
    readonly property int animDirection: screenState.dashboardDate > shownDate ? -1 : 1
    property real animTranslate
    property real animOpacity: 1

    // 0 = Sunday ... 6 = Saturday, as Date.getDay(); `% 7` also covers a locale that reports Sunday as 7.
    readonly property int firstDay: Qt.locale().firstDayOfWeek % 7
    readonly property bool showWeeks: firstDay === 1
    // Six full weeks, starting with the week the 1st falls in.
    readonly property var days: {
        const offset = (new Date(year, month, 1).getDay() - firstDay + 7) % 7;
        return Array.from({
            length: 42
        }, (_, i) => new Date(year, month, 1 - offset + i));
    }

    signal picked(day: date)

    function isoWeek(d: date): int {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
        const start = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
        return Math.ceil(((t - start) / 86400000 + 1) / 7);
    }

    function sameDay(a: date, b: date): bool {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    implicitHeight: layout.implicitHeight

    Anim {
        id: trOutAnim

        running: false
        target: root
        property: "animTranslate"
        to: root.Tokens.padding.extraLarge * root.animDirection
        type: Anim.FastSpatial
    }

    Behavior on shownDate {
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
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacing.extraSmall

        // Weekday names
        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            Item {
                visible: root.showWeeks
                implicitWidth: 30
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

        // Weeks; this part slides when the month changes.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            opacity: root.animOpacity
            transform: Translate {
                x: root.animTranslate
            }

            Repeater {
                model: 6

                RowLayout {
                    id: week

                    required property int index

                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        visible: root.showWeeks
                        Layout.preferredWidth: 30
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
                            readonly property bool chosen: root.sameDay(day, root.selected)
                            readonly property bool inMonth: day.getMonth() === root.month
                            readonly property bool weekend: day.getDay() === 0 || day.getDay() === 6
                            readonly property var dots: Calendars.dotsOn(day)
                            readonly property bool exam: Calendars.hasExam(day)

                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 56

                            MaterialShape {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -4
                                implicitSize: Math.min(cell.width, cell.height) - Tokens.padding.small
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
                                anchors.verticalCenterOffset: -4
                                implicitWidth: Math.min(cell.width, cell.height) - Tokens.padding.small
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
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -4
                                text: cell.day.getDate()
                                font: cell.today ? Tokens.font.body.builders.medium.weight(Font.DemiBold).build() : Tokens.font.body.medium
                                color: cell.today ? Colours.palette.m3onPrimary : cell.weekend ? Colours.palette.m3tertiary : Colours.palette.m3onSurface
                                opacity: cell.inMonth || cell.today ? 1 : 0.35
                            }

                            // Exam due
                            StyledRect {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.topMargin: Tokens.padding.extraSmall
                                anchors.rightMargin: Tokens.padding.small
                                implicitWidth: 7
                                implicitHeight: 7
                                radius: Tokens.rounding.full
                                color: Colours.palette.m3error
                                visible: cell.exam
                                opacity: cell.inMonth ? 1 : 0.4
                            }

                            // One dot per lesson / calendar
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: Tokens.padding.extraSmall
                                spacing: 2
                                opacity: cell.inMonth ? 1 : 0.4

                                Repeater {
                                    model: cell.dots

                                    StyledRect {
                                        required property color modelData

                                        implicitWidth: 4
                                        implicitHeight: 4
                                        radius: Tokens.rounding.full
                                        color: modelData
                                    }
                                }
                            }

                            StateLayer {
                                radius: Tokens.rounding.large
                                onClicked: root.picked(cell.day)
                            }
                        }
                    }
                }
            }
        }
    }
}
