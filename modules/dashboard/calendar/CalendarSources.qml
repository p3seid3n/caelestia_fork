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

// Content of the "Calendars" sheet. Two pages:
//   Calendars - subscribe by link (school timetable, Google, Outlook, ...) or import an .ics file,
//               switch calendars on or off, change their colour, remove them
//   Subjects  - the subjects found in the timetable: rename, recolour, hide their lessons
ColumnLayout {
    id: root

    property string page: "calendars"
    property bool adding
    property string kind: "school"
    property string error
    property string renaming

    signal importRequested(kind: string, name: string)

    function reset(): void {
        adding = false;
        error = "";
        renaming = "";
        nameField.text = "";
        linkField.text = "";
    }

    function ago(ms: double): string {
        const minutes = Math.round((Date.now() - ms) / 60000);
        if (minutes < 1)
            return Tr.tr("just now");
        if (minutes < 60)
            return Tr.tr("%1 min ago").arg(minutes);
        return Tr.tr("%1 h ago").arg(Math.round(minutes / 60));
    }

    spacing: Tokens.spacing.small

    // Pages
    RowLayout {
        Layout.fillWidth: true
        visible: !root.adding
        spacing: Tokens.spacing.extraSmall

        IconTextButton {
            type: IconTextButton.Tonal
            checked: root.page === "calendars"
            icon: "calendar_month"
            text: Tr.tr("Calendars")
            onClicked: root.page = "calendars"
        }

        IconTextButton {
            type: IconTextButton.Tonal
            checked: root.page === "subjects"
            icon: "school"
            text: Tr.tr("Subjects")
            onClicked: root.page = "subjects"
        }

        Item {
            Layout.fillWidth: true
        }

        StyledText {
            visible: root.page === "calendars"
            elide: Text.ElideRight
            text: Calendars.status === "syncing" ? Tr.tr("Syncing...") : Calendars.status === "error" ? Calendars.statusText : Calendars.lastSync > 0 ? Tr.tr("Synced %1").arg(root.ago(Calendars.lastSync)) : ""
            font: Tokens.font.body.small
            color: Calendars.status === "error" ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
        }

        IconButton {
            visible: root.page === "calendars" && Calendars.sources.length > 0
            type: IconButton.Text
            isRound: true
            icon: "sync"
            disabled: Calendars.status === "syncing"
            onClicked: Calendars.refresh()
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: Calendars.keyringError !== "" && !root.adding
        wrapMode: Text.WordWrap
        text: Calendars.keyringError
        font: Tokens.font.body.small
        color: Colours.palette.m3error
    }

    // ---- Calendars page
    StyledListView {
        id: calList

        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.page === "calendars" && !root.adding
        clip: true
        spacing: Tokens.spacing.extraSmall
        boundsBehavior: Flickable.StopAtBounds
        model: ScriptModel {
            values: [Calendars.localId].concat(Calendars.sources.map(s => s.id))
        }

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: calList
        }

        delegate: StyledRect {
            id: calRow

            required property string modelData
            readonly property bool isLocal: modelData === Calendars.localId
            readonly property var source: Calendars.sourceOf(modelData)
            readonly property string problem: Calendars.errors[modelData] ?? ""

            width: calList.width
            implicitHeight: 56
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.large
                anchors.rightMargin: Tokens.padding.medium
                spacing: Tokens.spacing.medium

                // Colour; tap for the next one.
                StyledRect {
                    implicitWidth: 32
                    implicitHeight: 32
                    radius: Tokens.rounding.full
                    color: Qt.alpha(Calendars.colourOf(calRow.modelData), 0.25)

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: calRow.isLocal ? "person" : calRow.source?.kind === "school" ? "school" : calRow.source?.file ? "upload_file" : "link"
                        color: Calendars.colourOf(calRow.modelData)
                        fontStyle: Tokens.font.icon.small
                    }

                    StateLayer {
                        radius: parent.radius
                        disabled: calRow.isLocal
                        onClicked: Calendars.setColour(calRow.modelData, Calendars.nextColour(Calendars.colourKeyOf(calRow.modelData)))
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: Calendars.nameOf(calRow.modelData)
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: {
                            if (calRow.isLocal)
                                return Tr.tr("Stored on this computer");
                            if (calRow.problem !== "")
                                return calRow.problem;
                            const what = calRow.source?.kind === "school" ? Tr.tr("School timetable") : "";
                            const where = calRow.source?.file ? Tr.tr("Imported file") : Calendars.hostOf(calRow.modelData);
                            return [what, where].filter(x => x !== "").join(" · ");
                        }
                        font: Tokens.font.body.small
                        color: calRow.problem !== "" ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    }
                }

                IconButton {
                    visible: !calRow.isLocal
                    type: IconButton.Text
                    isRound: true
                    icon: "delete"
                    inactiveOnColour: Colours.palette.m3error
                    onClicked: Calendars.removeSource(calRow.modelData)
                }

                StyledSwitch {
                    id: calToggle

                    onToggled: Calendars.setVisible(calRow.modelData, checked)

                    // A plain `checked:` binding is lost after the first click.
                    Binding {
                        target: calToggle
                        property: "checked"
                        value: Calendars.isVisible(calRow.modelData)
                    }
                }
            }
        }
    }

    IconTextButton {
        Layout.alignment: Qt.AlignHCenter
        visible: root.page === "calendars" && !root.adding
        type: IconTextButton.Filled
        horizontalPadding: Tokens.padding.extraLarge
        icon: "add"
        text: Tr.tr("Add calendar")
        onClicked: root.adding = true
    }

    // ---- Add form
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.adding
        spacing: Tokens.spacing.small

        RowLayout {
            spacing: Tokens.spacing.extraSmall

            IconTextButton {
                type: IconTextButton.Tonal
                checked: root.kind === "school"
                icon: "school"
                text: Tr.tr("School timetable")
                onClicked: root.kind = "school"
            }

            IconTextButton {
                type: IconTextButton.Tonal
                checked: root.kind === "other"
                icon: "link"
                text: Tr.tr("Google, Outlook, other")
                onClicked: root.kind = "other"
            }
        }

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root.kind === "school" ? Tr.tr("Paste the iCal subscription link from portal.sbl.ch (schulNetz), or import the exported .ics file. Lessons are matched to subjects, and exams are found from their name or from the second entry in a lesson's slot.") : Tr.tr("Google Calendar: Settings → your calendar → Integrate calendar → Secret address in iCal format. Outlook: Settings → Calendar → Shared calendars → Publish a calendar → ICS link. Links are kept in your system keyring and refreshed every 15 minutes; .ics files are imported once.")
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
        }

        StyledTextField {
            id: linkField

            Layout.fillWidth: true
            placeholderText: root.kind === "school" ? Tr.tr("https://portal.sbl.ch/... iCal link") : Tr.tr("https:// or webcal:// link")
            leadingIcon: "link"
            onAccepted: addButton.clicked()
        }

        StyledTextField {
            id: nameField

            Layout.fillWidth: true
            placeholderText: root.kind === "school" ? Tr.tr("Name (optional), e.g. Stundenplan") : Tr.tr("Name (optional), e.g. Work")
            leadingIcon: "label"
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.error !== ""
            wrapMode: Text.WordWrap
            text: root.error
            font: Tokens.font.body.small
            color: Colours.palette.m3error
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            TextButton {
                type: TextButton.Text
                text: Tr.tr("Back")
                onClicked: root.reset()
            }

            Item {
                Layout.fillWidth: true
            }

            IconTextButton {
                type: IconTextButton.Tonal
                icon: "upload_file"
                text: Tr.tr("Import .ics file")
                onClicked: root.importRequested(root.kind, nameField.text)
            }

            TextButton {
                id: addButton

                type: TextButton.Filled
                horizontalPadding: Tokens.padding.extraLarge
                text: Tr.tr("Subscribe")
                onClicked: {
                    root.error = Calendars.addSource(nameField.text, linkField.text, root.kind);
                    if (root.error === "")
                        root.reset();
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }

    // ---- Subjects page
    StyledListView {
        id: subjectList

        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.page === "subjects" && !root.adding
        clip: true
        spacing: Tokens.spacing.extraSmall
        boundsBehavior: Flickable.StopAtBounds
        model: ScriptModel {
            values: Subjects.list.map(s => s.id)
        }

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: subjectList
        }

        delegate: StyledRect {
            id: subjectRow

            required property string modelData
            readonly property var subject: Subjects.subjects[modelData] ?? null

            width: subjectList.width
            implicitHeight: 52
            radius: Tokens.rounding.large
            color: Colours.tPalette.m3surfaceContainer

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.large
                anchors.rightMargin: Tokens.padding.medium
                spacing: Tokens.spacing.medium

                // Colour; tap for the next hue.
                StyledRect {
                    implicitWidth: 32
                    implicitHeight: 32
                    radius: Tokens.rounding.full
                    color: Subjects.containerOf(subjectRow.modelData)

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: subjectRow.subject?.icon ?? "school"
                        color: Subjects.onContainerOf(subjectRow.modelData)
                        fontStyle: Tokens.font.icon.small
                    }

                    StateLayer {
                        radius: parent.radius
                        onClicked: Subjects.nextColour(subjectRow.modelData)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.renaming !== subjectRow.modelData
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: subjectRow.subject?.name ?? ""
                        font: Tokens.font.body.medium
                        color: Colours.palette.m3onSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: (subjectRow.subject?.codes ?? []).join(" · ") + (subjectRow.subject?.teacher ? " · " + subjectRow.subject.teacher : "")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }

                StyledTextField {
                    id: renameField

                    Layout.fillWidth: true
                    visible: root.renaming === subjectRow.modelData
                    text: subjectRow.subject?.name ?? ""
                    onAccepted: {
                        Subjects.rename(subjectRow.modelData, text);
                        root.renaming = "";
                    }
                    onVisibleChanged: {
                        if (visible)
                            forceActiveFocus();
                    }
                }

                IconButton {
                    type: IconButton.Text
                    isRound: true
                    icon: root.renaming === subjectRow.modelData ? "check" : "edit"
                    onClicked: {
                        if (root.renaming === subjectRow.modelData) {
                            Subjects.rename(subjectRow.modelData, renameField.text);
                            root.renaming = "";
                        } else {
                            root.renaming = subjectRow.modelData;
                        }
                    }
                }

                StyledSwitch {
                    id: subjectToggle

                    onToggled: Subjects.setHidden(subjectRow.modelData, !checked)

                    Binding {
                        target: subjectToggle
                        property: "checked"
                        value: !(subjectRow.subject?.hidden ?? false)
                    }
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.page === "subjects" && !root.adding && Subjects.list.length === 0
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
        text: Tr.tr("Subjects appear here once a school timetable is added.")
        font: Tokens.font.body.medium
        color: Colours.palette.m3onSurfaceVariant
    }
}
