import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// Content of the "New event" sheet: a title, an optional place and a time (or all day) on the given day.
ColumnLayout {
    id: root

    property date day: new Date()
    property bool allDay
    property string error

    signal saved

    // "9:30" or "09:30" -> minutes after midnight, or -1.
    function minutesOf(text: string): int {
        const m = /^\s*(\d{1,2})[:.](\d{2})\s*$/.exec(text);
        if (!m)
            return -1;
        const h = parseInt(m[1]);
        const min = parseInt(m[2]);
        return h > 23 || min > 59 ? -1 : h * 60 + min;
    }

    function reset(): void {
        allDay = false;
        error = "";
        titleField.text = "";
        placeField.text = "";
        // The next full hour is a sensible default.
        const next = new Date().getHours() + 1;
        const from = Math.min(next, 22);
        startField.text = (from < 10 ? "0" : "") + from + ":00";
        endField.text = (from + 1 < 10 ? "0" : "") + (from + 1) + ":00";
        titleField.forceActiveFocus();
    }

    function save(): void {
        const y = day.getFullYear(), mo = day.getMonth(), d = day.getDate();
        let start, end;
        if (allDay) {
            start = new Date(y, mo, d).getTime();
            end = new Date(y, mo, d + 1).getTime();
        } else {
            const from = minutesOf(startField.text);
            let to = minutesOf(endField.text);
            if (from < 0 || to < 0) {
                error = Tr.tr("Times look like 09:30.");
                return;
            }
            if (to <= from)
                to = Math.min(from + 60, 24 * 60);
            start = new Date(y, mo, d, 0, from).getTime();
            end = new Date(y, mo, d, 0, to).getTime();
        }
        Calendars.addEvent(titleField.text, placeField.text, allDay, start, end);
        saved();
    }

    spacing: Tokens.spacing.small

    StyledText {
        Layout.fillWidth: true
        text: root.day.toLocaleDateString(Qt.locale(), Locale.LongFormat)
        font: Tokens.font.body.medium
        color: Colours.palette.m3onSurfaceVariant
    }

    StyledTextField {
        id: titleField

        Layout.fillWidth: true
        placeholderText: Tr.tr("Title")
        leadingIcon: "edit_calendar"
        onAccepted: root.save()
    }

    StyledTextField {
        id: placeField

        Layout.fillWidth: true
        placeholderText: Tr.tr("Place (optional)")
        leadingIcon: "location_on"
        onAccepted: root.save()
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        StyledText {
            Layout.fillWidth: true
            text: Tr.tr("All day")
            font: Tokens.font.body.medium
            color: Colours.palette.m3onSurface
        }

        StyledSwitch {
            id: allDaySwitch

            onToggled: root.allDay = checked

            Binding {
                target: allDaySwitch
                property: "checked"
                value: root.allDay
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: !root.allDay
        spacing: Tokens.spacing.small

        StyledTextField {
            id: startField

            Layout.fillWidth: true
            Layout.preferredWidth: 1
            placeholderText: Tr.tr("From")
            leadingIcon: "schedule"
            onAccepted: endField.forceActiveFocus()
        }

        StyledTextField {
            id: endField

            Layout.fillWidth: true
            Layout.preferredWidth: 1
            placeholderText: Tr.tr("To")
            leadingIcon: "update"
            onAccepted: root.save()
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.error !== ""
        text: root.error
        font: Tokens.font.body.small
        color: Colours.palette.m3error
    }

    TextButton {
        Layout.alignment: Qt.AlignRight
        type: TextButton.Filled
        horizontalPadding: Tokens.padding.extraLarge
        text: Tr.tr("Add event")
        onClicked: root.save()
    }

    Item {
        Layout.fillHeight: true
    }
}
