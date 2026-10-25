import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services

// The next events from all calendars, as many as fit.
Item {
    id: root

    readonly property real rowHeight: 40
    readonly property int fit: Math.max(1, Math.floor((height - Tokens.padding.large * 2 - header.height - layout.spacing) / (rowHeight + layout.spacing)))
    readonly property var shown: Calendars.upcoming(fit)

    function dayLabel(ms: double): string {
        const day = new Date(ms);
        const now = new Date();
        const days = Math.round((new Date(day.getFullYear(), day.getMonth(), day.getDate()) - new Date(now.getFullYear(), now.getMonth(), now.getDate())) / 86400000);
        if (days <= 0)
            return Tr.tr("Today");
        if (days === 1)
            return Tr.tr("Tomorrow");
        return day.toLocaleDateString(Qt.locale(), "ddd d MMM");
    }

    function whenText(e: var): string {
        const label = dayLabel(Math.max(e.start, Date.now()));
        return e.allDay ? label : label + " · " + Qt.formatTime(new Date(e.start), Qt.locale().timeFormat(Locale.ShortFormat));
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        RowLayout {
            id: header

            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "event_upcoming"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.small
            }

            StyledText {
                Layout.fillWidth: true
                text: Tr.tr("Agenda")
                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                color: Colours.palette.m3primary
            }
        }

        Repeater {
            model: root.shown

            RowLayout {
                id: row

                required property var modelData

                Layout.fillWidth: true
                Layout.preferredHeight: root.rowHeight
                spacing: Tokens.spacing.medium

                StyledRect {
                    Layout.fillHeight: true
                    Layout.topMargin: Tokens.padding.small
                    Layout.bottomMargin: Tokens.padding.small
                    implicitWidth: 4
                    radius: Tokens.rounding.full
                    color: Calendars.colourOf(row.modelData.cal)
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: row.modelData.title
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.whenText(row.modelData)
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.shown.length === 0
            text: Tr.tr("Nothing coming up")
            font: Tokens.font.body.medium
            color: Colours.palette.m3onSurfaceVariant
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
