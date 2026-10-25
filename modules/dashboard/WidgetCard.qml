import "widgets"
import QtQuick
import Caelestia.Config
import qs.components
import qs.services

// The card around one dashboard widget. Holding the background starts edit mode, like on iOS.
StyledRect {
    id: root

    property string widgetType
    property bool editing

    readonly property var kinds: ({
            clock: clockWidget,
            weather: weatherWidget,
            month: monthWidget,
            agenda: agendaWidget,
            todo: todoWidget,
            media: mediaWidget,
            resources: resourcesWidget
        })

    signal editRequested

    radius: Tokens.rounding.extraLarge
    color: Colours.tPalette.m3surfaceContainer

    MouseArea {
        anchors.fill: parent
        onPressAndHold: root.editRequested()
    }

    Loader {
        anchors.fill: parent
        enabled: !root.editing
        sourceComponent: root.kinds[root.widgetType] ?? null
    }

    Component {
        id: clockWidget

        ClockWidget {}
    }

    Component {
        id: weatherWidget

        WeatherWidget {}
    }

    Component {
        id: monthWidget

        MonthWidget {}
    }

    Component {
        id: agendaWidget

        AgendaWidget {}
    }

    Component {
        id: todoWidget

        TodoWidget {}
    }

    Component {
        id: mediaWidget

        MediaWidget {}
    }

    Component {
        id: resourcesWidget

        ResourcesWidget {}
    }
}
