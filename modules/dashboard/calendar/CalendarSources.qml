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

// Content of the "Calendars" sheet: switch calendars on or off, subscribe to online calendars by link.
ColumnLayout {
    id: root

    property bool adding
    property string error

    function reset(): void {
        adding = false;
        error = "";
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

    // List of calendars
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: !root.adding
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: Calendars.status === "syncing" ? Tr.tr("Syncing...") : Calendars.status === "error" ? Calendars.statusText : Calendars.lastSync > 0 ? Tr.tr("Last synced %1").arg(root.ago(Calendars.lastSync)) : Tr.tr("Online calendars are read-only.")
                font: Tokens.font.body.small
                color: Calendars.status === "error" ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
            }

            TextButton {
                type: TextButton.Text
                visible: Calendars.sources.length > 0
                disabled: Calendars.status === "syncing"
                text: Tr.tr("Sync now")
                onClicked: Calendars.refresh()
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: Calendars.keyringError !== ""
            wrapMode: Text.WordWrap
            text: Calendars.keyringError
            font: Tokens.font.body.small
            color: Colours.palette.m3error
        }

        StyledListView {
            id: list

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Tokens.spacing.extraSmall
            boundsBehavior: Flickable.StopAtBounds
            model: ScriptModel {
                values: [Calendars.localId].concat(Calendars.sources.map(s => s.id))
            }

            StyledScrollBar.vertical: StyledScrollBar {
                flickable: list
            }

            delegate: StyledRect {
                id: row

                required property string modelData
                readonly property bool isLocal: modelData === Calendars.localId
                readonly property string problem: Calendars.errors[modelData] ?? ""

                width: list.width
                implicitHeight: 56
                radius: Tokens.rounding.large
                color: Colours.tPalette.m3surfaceContainer

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.large
                    anchors.rightMargin: Tokens.padding.medium
                    spacing: Tokens.spacing.medium

                    // Colour dot; tap to pick the next colour.
                    StyledRect {
                        implicitWidth: 20
                        implicitHeight: 20
                        radius: Tokens.rounding.full
                        color: Calendars.colourOf(row.modelData)

                        StateLayer {
                            radius: parent.radius
                            disabled: row.isLocal
                            onClicked: Calendars.setColour(row.modelData, Calendars.nextColour(Calendars.colourKeyOf(row.modelData)))
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: Calendars.nameOf(row.modelData)
                            font: Tokens.font.body.medium
                            color: Colours.palette.m3onSurface
                        }

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: row.isLocal ? Tr.tr("Stored on this computer") : row.problem !== "" ? row.problem : Calendars.hostOf(row.modelData)
                            font: Tokens.font.body.small
                            color: row.problem !== "" ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                        }
                    }

                    IconButton {
                        visible: !row.isLocal
                        type: IconButton.Text
                        isRound: true
                        icon: "delete"
                        inactiveOnColour: Colours.palette.m3error
                        onClicked: Calendars.removeSource(row.modelData)
                    }

                    StyledSwitch {
                        id: toggle

                        onToggled: Calendars.setVisible(row.modelData, checked)

                        // A plain `checked:` binding is lost after the first click.
                        Binding {
                            target: toggle
                            property: "checked"
                            value: Calendars.isVisible(row.modelData)
                        }
                    }
                }
            }
        }

        IconTextButton {
            Layout.alignment: Qt.AlignHCenter
            type: IconTextButton.Filled
            horizontalPadding: Tokens.padding.extraLarge
            icon: "add_link"
            text: Tr.tr("Add online calendar")
            onClicked: root.adding = true
        }
    }

    // Add form
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.adding
        spacing: Tokens.spacing.small

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: Tr.tr("Paste the private iCal link of a calendar. Google Calendar: Settings → your calendar → Integrate calendar → Secret address in iCal format. Outlook: Settings → Calendar → Shared calendars → Publish a calendar → ICS link. Anyone with the link can read that calendar, so it is kept in your system keyring.")
            font: Tokens.font.body.small
            color: Colours.palette.m3onSurfaceVariant
        }

        StyledTextField {
            id: nameField

            Layout.fillWidth: true
            placeholderText: Tr.tr("Name, e.g. Work")
            leadingIcon: "label"
        }

        StyledTextField {
            id: linkField

            Layout.fillWidth: true
            placeholderText: Tr.tr("https:// or webcal:// link")
            leadingIcon: "link"
            onAccepted: addButton.clicked()
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
            Layout.alignment: Qt.AlignRight
            spacing: Tokens.spacing.small

            TextButton {
                type: TextButton.Text
                text: Tr.tr("Back")
                onClicked: root.reset()
            }

            TextButton {
                id: addButton

                type: TextButton.Filled
                horizontalPadding: Tokens.padding.extraLarge
                text: Tr.tr("Add")
                onClicked: {
                    root.error = Calendars.addSource(nameField.text, linkField.text, "");
                    if (root.error === "")
                        root.reset();
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }
}
