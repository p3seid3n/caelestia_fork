pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import M3Shapes
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

// The month as Caelestia's own dashboard calendar draws it (modules/dashboard/dash/Calendar.qml):
// month name in a pill between two arrows, weekday names, the grid, and today in a Sunny shape that
// recolours the number under it. The month slides exactly like there. Added on top: clicking a day
// chooses it (a ring marks it), lessons show as small dots in their subject's colours and a red
// mark sits on days with an exam.
StyledRect {
    id: root

    required property ScreenState screenState
    property date selected: new Date()

    property date currentDate: screenState.dashboardDate
    readonly property int currMonth: currentDate.getMonth()
    readonly property int currYear: currentDate.getFullYear()
    readonly property int nonAnimCurrMonth: screenState.dashboardDate.getMonth()
    readonly property int nonAnimCurrYear: screenState.dashboardDate.getFullYear()

    readonly property int animDirection: screenState.dashboardDate > currentDate ? -1 : 1
    property real animTranslate
    property real animOpacity: 1

    signal picked(day: date)

    function sameDay(a: date, b: date): bool {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    implicitHeight: inner.implicitHeight + inner.anchors.margins * 2
    radius: Tokens.rounding.extraLarge
    color: Colours.tPalette.m3surfaceContainer

    Anim {
        id: trOutAnim

        running: false
        target: root
        property: "animTranslate"
        to: root.Tokens.padding.extraLarge * root.animDirection
        type: Anim.FastSpatial
    }

    Behavior on currentDate {
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
        id: inner

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            IconButton {
                isRound: true
                icon: "chevron_left"
                type: IconButton.Text
                font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                padding: Tokens.padding.small
                onClicked: root.screenState.dashboardDate = new Date(root.nonAnimCurrYear, root.nonAnimCurrMonth - 1, 1)
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                implicitWidth: monthYear.implicitWidth + Tokens.padding.large * 2
                implicitHeight: monthYear.implicitHeight + Tokens.padding.extraSmall * 2

                StateLayer {
                    color: Colours.palette.m3primary
                    radius: pressed ? Tokens.rounding.small : height / 2
                    disabled: {
                        const now = new Date();
                        return root.nonAnimCurrMonth === now.getMonth() && root.nonAnimCurrYear === now.getFullYear() && root.sameDay(root.selected, now);
                    }
                    onClicked: {
                        root.screenState.dashboardDate = new Date();
                        root.picked(new Date());
                    }

                    Behavior on radius {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                StyledText {
                    id: monthYear

                    anchors.centerIn: parent
                    opacity: root.animOpacity
                    transform: Translate {
                        x: root.animTranslate
                    }
                    text: grid.title
                    color: Colours.palette.m3primary
                    font: Tokens.font.title.builders.small.capitalisation(Font.Capitalize).build()
                }
            }

            IconButton {
                isRound: true
                icon: "chevron_right"
                type: IconButton.Text
                font: Tokens.font.icon.builders.small.weight(Font.Bold).build()
                padding: Tokens.padding.small
                onClicked: root.screenState.dashboardDate = new Date(root.nonAnimCurrYear, root.nonAnimCurrMonth + 1, 1)
            }
        }

        DayOfWeekRow {
            Layout.fillWidth: true
            locale: grid.locale

            delegate: StyledText {
                required property var model

                horizontalAlignment: Text.AlignHCenter
                text: model.shortName
                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                color: (model.day === 0 || model.day === 6) ? Colours.palette.m3tertiary : Colours.palette.m3onSurface
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: grid.implicitHeight

            opacity: root.animOpacity
            transform: Translate {
                x: root.animTranslate
            }

            MonthGrid {
                id: grid

                anchors.fill: parent
                month: root.currMonth
                year: root.currYear
                spacing: 3
                locale: Qt.locale()

                onClicked: day => root.picked(day)

                delegate: Item {
                    id: dayItem

                    required property var model
                    readonly property bool inMonth: model.month === grid.month
                    readonly property bool chosen: root.sameDay(model.date, root.selected)
                    readonly property var dots: inMonth ? Calendars.dotsOn(model.date).slice(0, 5) : []
                    readonly property bool exam: inMonth && Calendars.hasExam(model.date)

                    implicitWidth: implicitHeight
                    implicitHeight: 40

                    // The chosen day (today has its shape already).
                    StyledRect {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -4
                        implicitWidth: 32
                        implicitHeight: 32
                        radius: Tokens.rounding.full
                        color: "transparent"
                        border.width: 2
                        border.color: Colours.palette.m3primary
                        opacity: dayItem.chosen && !dayItem.model.today ? 1 : 0

                        Behavior on opacity {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -4
                        horizontalAlignment: Text.AlignHCenter
                        text: grid.locale.toString(dayItem.model.day)
                        color: {
                            const dayOfWeek = dayItem.model.date.getDay();
                            if (dayOfWeek === 0 || dayOfWeek === 6)
                                return Colours.palette.m3tertiary;
                            return Colours.palette.m3onSurfaceVariant;
                        }
                        opacity: dayItem.model.today || dayItem.inMonth ? 1 : 0.4
                        font: Tokens.font.body.medium
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        spacing: 2

                        Repeater {
                            model: dayItem.dots

                            StyledRect {
                                required property color modelData

                                implicitWidth: 4
                                implicitHeight: 4
                                radius: Tokens.rounding.full
                                color: modelData
                            }
                        }
                    }

                    StyledRect {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 2
                        implicitWidth: 6
                        implicitHeight: 6
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3error
                        visible: dayItem.exam
                    }
                }
            }

            MaterialShape {
                id: todayIndicator

                readonly property Item todayItem: grid.contentItem.children.find(c => c.model?.today) ?? null
                property Item today

                onTodayItemChanged: {
                    if (todayItem)
                        today = todayItem;
                }

                x: today ? today.x + (today.width - implicitSize) / 2 : 0
                y: today ? today.y + (today.height - implicitSize) / 2 - 4 : 0

                implicitSize: 36
                shape: MaterialShape.Sunny

                clip: true
                color: Colours.palette.m3primary

                opacity: todayItem ? 1 : 0

                Colouriser {
                    x: -todayIndicator.x
                    y: -todayIndicator.y

                    implicitWidth: grid.width
                    implicitHeight: grid.height

                    source: grid
                    sourceColor: Colours.palette.m3onSurfaceVariant
                    colorizationColor: Colours.palette.m3onPrimary
                }
            }
        }
    }
}
