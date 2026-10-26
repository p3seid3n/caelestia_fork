pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.filedialog
import qs.services
import qs.utils

Item {
    id: root

    required property ScreenState screenState
    readonly property FileDialog facePicker: FileDialog {
        title: Tr.tr("Select a profile picture")
        filterLabel: Tr.tr("Image files")
        filters: Images.validImageExtensions
        onAccepted: path => {
            if (CUtils.copyFile(Qt.resolvedUrl(path), Qt.resolvedUrl(`${Paths.home}/.face`)))
                // TRANSLATORS: %1 = a file path
                Quickshell.execDetached(["notify-send", "-a", "caelestia-shell", "-u", "low", "-h", `STRING:image-path:${path}`, Tr.tr("Profile picture changed"), Tr.tr("Profile picture changed to %1").arg(Paths.shortenHome(path))]);
            else
                // TRANSLATORS: %1 = a file path
                Quickshell.execDetached(["notify-send", "-a", "caelestia-shell", "-u", "critical", Tr.tr("Unable to change profile picture"), Tr.tr("Failed to change profile picture to %1").arg(Paths.shortenHome(path))]);
        }
    }

    // .ics import for the Calendar tab. It lives here, not in the tab, so it survives the drawer
    // closing while the dialog has the pointer.
    readonly property FileDialog icsPicker: FileDialog {
        title: Tr.tr("Import a calendar")
        filterLabel: Tr.tr("Calendar files")
        filters: ["ics", "ical", "icalendar", "ifb"]
        onAccepted: path => {
            const id = Calendars.newId();
            if (CUtils.copyFile(Qt.resolvedUrl(path), Qt.resolvedUrl(Calendars.fileFor(id))))
                Calendars.addFile(id, Calendars.importName, Calendars.importKind);
            else
                // TRANSLATORS: %1 = a file path
                Quickshell.execDetached(["notify-send", "-a", "caelestia-shell", "-u", "critical", Tr.tr("Unable to import calendar"), Tr.tr("Could not copy %1").arg(Paths.shortenHome(path))]);
        }
    }

    readonly property real nonAnimHeight: (content.item as Content)?.nonAnimHeight ?? 0
    readonly property bool shouldBeActive: screenState.dashboard && Config.dashboard.enabled
    property real offsetScale: shouldBeActive ? 0 : 1

    visible: offsetScale < 1
    anchors.topMargin: (-implicitHeight - 5) * offsetScale
    implicitHeight: content.implicitHeight
    implicitWidth: content.implicitWidth || 854 // Hard coded fallback for first open
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {}
    }

    Connections {
        function onImportRequested(): void {
            root.icsPicker.open();
        }

        target: Calendars
    }

    Loader {
        id: content

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom

        // KairosOS: built once in the background at shell start and kept, so opening the
        // dashboard only slides it in instead of building every tab again each time.
        active: Config.dashboard.enabled
        asynchronous: true

        sourceComponent: Content {
            screenState: root.screenState
            facePicker: root.facePicker
        }
    }
}
