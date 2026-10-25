import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// This month in miniature: today is filled in and days with events get a dot.
Item {
    id: root

    readonly property date now: Time.date
    readonly property int year: now.getFullYear()
    readonly property int month: now.getMonth()
    // 0 = Sunday ... 6 = Saturday, as Date.getDay().
    readonly property int firstDay: Qt.locale().firstDayOfWeek % 7
    readonly property var days: {
        const offset = (new Date(year, month, 1).getDay() - firstDay + 7) % 7;
        return Array.from({
            length: 42
        }, (_, i) => new Date(year, month, 1 - offset + i));
    }
    readonly property real cellWidth: (width - Tokens.padding.large * 2) / 7
    readonly property real cellHeight: (height - Tokens.padding.large * 2 - header.height - weekdays.height - Tokens.spacing.small * 2) / 6

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        StyledText {
            id: header

            Layout.fillWidth: true
            text: Qt.locale().monthName(root.month) + " " + root.year
            font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
            color: Colours.palette.m3primary
        }

        Row {
            id: weekdays

            Repeater {
                model: 7

                StyledText {
                    required property int index

                    width: root.cellWidth
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.locale().dayName((root.firstDay + index) % 7, Locale.NarrowFormat)
                    font: Tokens.font.body.small
                    color: Colours.palette.m3outline
                }
            }
        }

        Grid {
            columns: 7

            Repeater {
                model: root.days

                Item {
                    id: cell

                    required property date modelData
                    readonly property bool today: modelData.getFullYear() === root.now.getFullYear() && modelData.getMonth() === root.now.getMonth() && modelData.getDate() === root.now.getDate()
                    readonly property bool inMonth: modelData.getMonth() === root.month
                    readonly property var dots: Calendars.dotsOn(modelData)

                    width: root.cellWidth
                    height: root.cellHeight

                    StyledRect {
                        anchors.centerIn: parent
                        implicitWidth: Math.min(cell.width, cell.height) - 2
                        implicitHeight: implicitWidth
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary
                        visible: cell.today
                    }

                    StyledText {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: cell.dots.length > 0 && cell.height > 26 ? -2 : 0
                        text: cell.modelData.getDate()
                        font: Tokens.font.body.small
                        color: cell.today ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                        opacity: cell.inMonth ? 1 : 0.3
                    }

                    StyledRect {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        implicitWidth: 4
                        implicitHeight: 4
                        radius: Tokens.rounding.full
                        visible: cell.dots.length > 0 && cell.inMonth && cell.height > 26
                        color: cell.today ? Colours.palette.m3onPrimary : (cell.dots[0] ?? Colours.palette.m3primary)
                    }
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
