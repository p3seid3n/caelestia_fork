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

// Side panel of the Calendar tab: what is planned on the chosen day, then what is coming up.
ColumnLayout {
    id: root

    property date day: new Date()

    readonly property bool isToday: {
        const now = new Date();
        return now.getFullYear() === day.getFullYear() && now.getMonth() === day.getMonth() && now.getDate() === day.getDate();
    }
    readonly property var dayEvents: Calendars.eventsOn(day)
    readonly property var coming: {
        const here = new Set(dayEvents.map(e => e.id));
        return Calendars.upcoming(12).filter(e => !here.has(e.id)).slice(0, 5);
    }
    // Plain strings keep the list in place when events refresh: "d:<id>" planned that day,
    // "n:" nothing planned, "h:" heading of the upcoming part, "u:<id>" upcoming.
    readonly property var rows: {
        const out = dayEvents.map(e => "d:" + e.id);
        if (out.length === 0)
            out.push("n:");
        if (coming.length > 0) {
            out.push("h:");
            for (const e of coming)
                out.push("u:" + e.id);
        }
        return out;
    }

    signal addRequested
    signal calendarsRequested

    function clock(ms: double): string {
        return Qt.formatTime(new Date(ms), Qt.locale().timeFormat(Locale.ShortFormat));
    }

    function whenText(e: var, withDate: bool): string {
        const date = withDate ? new Date(e.start).toLocaleDateString(Qt.locale(), "ddd d MMM") + " · " : "";
        if (e.allDay)
            return date + Tr.tr("All day");
        return date + clock(e.start) + (e.end > e.start ? " – " + clock(e.end) : "");
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
            readonly property string kind: modelData.charAt(0)
            readonly property var event: Calendars.byId[modelData.slice(2)] ?? null

            width: list.width
            implicitHeight: kind === "n" ? 44 : kind === "h" ? 36 : 54

            StyledText {
                anchors.fill: parent
                visible: row.kind === "n"
                verticalAlignment: Text.AlignVCenter
                text: Tr.tr("Nothing planned")
                font: Tokens.font.body.medium
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                anchors.fill: parent
                anchors.topMargin: Tokens.padding.small
                visible: row.kind === "h"
                verticalAlignment: Text.AlignVCenter
                text: Tr.tr("Coming up")
                font: Tokens.font.body.builders.small.weight(Font.Medium).build()
                color: Colours.palette.m3primary
            }

            StyledRect {
                anchors.fill: parent
                visible: (row.kind === "d" || row.kind === "u") && row.event !== null
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainer

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.rightMargin: Tokens.padding.small
                    spacing: Tokens.spacing.medium

                    StyledRect {
                        Layout.fillHeight: true
                        Layout.topMargin: Tokens.padding.small
                        Layout.bottomMargin: Tokens.padding.small
                        implicitWidth: 4
                        radius: Tokens.rounding.full
                        color: row.event ? Calendars.colourOf(row.event.cal) : "transparent"
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: row.event?.title ?? ""
                            font: Tokens.font.body.medium
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: row.event ? root.whenText(row.event, row.kind === "u") + (row.event.location !== "" ? " · " + row.event.location : "") : ""
                            font: Tokens.font.body.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }

                    IconButton {
                        visible: row.event?.cal === Calendars.localId
                        type: IconButton.Text
                        isRound: true
                        icon: "delete"
                        inactiveOnColour: Colours.palette.m3error
                        onClicked: Calendars.removeEvent(row.event.id)
                    }
                }
            }
        }
    }
}
