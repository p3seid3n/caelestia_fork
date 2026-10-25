import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Material 3 time input: an hour box and a minute box. Scroll over a box, use the arrow keys or
// type digits to change it; minutes move in steps of five when scrolled.
RowLayout {
    id: root

    // Minutes after midnight. Bind it and update it from edited(), which reports the new value.
    property int minutes: 9 * 60
    property string label

    signal edited(value: int)

    function setMinutes(value: int): void {
        const next = ((value % 1440) + 1440) % 1440;
        if (next !== minutes)
            edited(next);
    }

    spacing: Tokens.spacing.extraSmall

    StyledText {
        Layout.rightMargin: Tokens.spacing.small
        visible: root.label !== ""
        text: root.label
        font: Tokens.font.body.medium
        color: Colours.palette.m3onSurfaceVariant
    }

    Box {
        value: Math.floor(root.minutes / 60)
        max: 23
        step: 1
        onModified: v => root.setMinutes(v * 60 + root.minutes % 60)
    }

    StyledText {
        text: ":"
        font: Tokens.font.body.builders.large.size(26).weight(Font.DemiBold).build()
        color: Colours.palette.m3onSurface
    }

    Box {
        value: root.minutes % 60
        max: 59
        step: 5
        onModified: v => root.setMinutes(Math.floor(root.minutes / 60) * 60 + v)
    }

    component Box: StyledRect {
        id: box

        required property int value
        required property int max
        required property int step
        property string typed

        signal modified(v: int)

        function nudge(by: int): void {
            // Scrolling snaps to the step, so 09:07 scrolls to 09:10.
            const snapped = by > 0 ? Math.floor(value / step) * step + step : Math.ceil(value / step) * step - step;
            modified(((snapped % (max + 1)) + max + 1) % (max + 1));
        }

        implicitWidth: 64
        implicitHeight: 52
        radius: Tokens.rounding.small
        color: activeFocus ? Colours.palette.m3primaryContainer : Colours.tPalette.m3surfaceContainerHighest
        border.width: activeFocus ? 2 : 0
        border.color: Colours.palette.m3primary
        activeFocusOnTab: true

        onActiveFocusChanged: typed = ""

        Keys.onUpPressed: nudge(1)
        Keys.onDownPressed: nudge(-1)
        Keys.onPressed: event => {
            if (event.text.length === 1 && event.text >= "0" && event.text <= "9") {
                typed = (typed + event.text).slice(-2);
                modified(Math.min(max, parseInt(typed)));
                event.accepted = true;
            }
        }

        Behavior on color {
            CAnim {}
        }

        StyledText {
            anchors.centerIn: parent
            text: (box.value < 10 ? "0" : "") + box.value
            font: Tokens.font.body.builders.large.size(26).weight(Font.DemiBold).build()
            color: box.activeFocus ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor
            onClicked: box.forceActiveFocus()
            onWheel: wheel => box.nudge(wheel.angleDelta.y > 0 ? 1 : -1)
        }
    }
}
