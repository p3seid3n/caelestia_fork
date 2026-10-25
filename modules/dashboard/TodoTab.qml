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

// Dashboard "To-do" tab: write a task down, tick it off.
// Open tasks first, finished ones under a "Completed" label.
Item {
    id: root

    required property ScreenState screenState
    // Read by Content.qml: the text field needs keyboard focus from the drawer window.
    readonly property bool wantsInput: true

    // Task ids; "#completed" is the label between the two groups. The model holds plain
    // strings so the list keeps its scroll position and animates when a task changes group.
    readonly property var rows: {
        const open = Todos.items.filter(i => !i.done).map(i => i.id);
        const done = Todos.items.filter(i => i.done).map(i => i.id);
        return done.length > 0 ? open.concat(["#completed"], done) : open;
    }

    function addTask(): void {
        Todos.add(taskField.text);
        taskField.text = "";
        taskField.forceActiveFocus();
    }

    implicitWidth: 840
    implicitHeight: 480

    Component.onCompleted: Qt.callLater(() => taskField.forceActiveFocus())

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: Tr.tr("To-do")
                    font: Tokens.font.body.builders.large.size(28).weight(Font.DemiBold).build()
                    color: Colours.palette.m3onSurface
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Todos.items.length === 0 ? Tr.tr("Nothing written down yet") : Todos.openCount === 0 ? Tr.tr("Everything is done") : Tr.trN("%n task left", "%n tasks left", Todos.openCount)
                    font: Tokens.font.body.medium
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            TextButton {
                visible: Todos.doneCount > 0
                type: TextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                text: Tr.tr("Clear completed")
                onClicked: Todos.clearDone()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledTextField {
                id: taskField

                Layout.fillWidth: true
                placeholderText: Tr.tr("Add a task")
                leadingIcon: "add"
                onAccepted: root.addTask()
            }

            IconButton {
                type: IconButton.Filled
                isRound: true
                icon: "arrow_upward"
                disabled: taskField.text.trim() === ""
                onClicked: root.addTask()
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledListView {
                id: list

                anchors.fill: parent
                clip: true
                spacing: Tokens.spacing.extraSmall
                boundsBehavior: Flickable.StopAtBounds
                model: ScriptModel {
                    values: root.rows
                }

                StyledScrollBar.vertical: StyledScrollBar {
                    flickable: list
                }

                displaced: Transition {
                    Anim {
                        property: "y"
                    }
                }

                delegate: Item {
                    id: row

                    required property string modelData
                    readonly property bool isLabel: modelData === "#completed"
                    readonly property var task: Todos.byId[modelData] ?? null
                    readonly property bool done: task?.done ?? false

                    width: list.width
                    implicitHeight: isLabel ? 36 : 52

                    StyledText {
                        anchors.left: parent.left
                        anchors.leftMargin: Tokens.padding.large
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Tokens.padding.small
                        visible: row.isLabel
                        text: Tr.tr("Completed")
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                    }

                    StyledRect {
                        anchors.fill: parent
                        visible: !row.isLabel
                        radius: Tokens.rounding.large
                        color: Colours.tPalette.m3surfaceContainer

                        // Tapping anywhere on the row ticks it.
                        StateLayer {
                            radius: parent.radius
                            onClicked: Todos.toggle(row.modelData)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.large
                            anchors.rightMargin: Tokens.padding.small
                            spacing: Tokens.spacing.medium

                            StyledRect {
                                implicitWidth: 24
                                implicitHeight: 24
                                radius: Tokens.rounding.full
                                color: row.done ? Colours.palette.m3primary : "transparent"
                                border.width: row.done ? 0 : 2
                                border.color: Colours.palette.m3outline

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: "check"
                                    color: Colours.palette.m3onPrimary
                                    fontStyle: Tokens.font.icon.small
                                    opacity: row.done ? 1 : 0

                                    Behavior on opacity {
                                        Anim {
                                            type: Anim.DefaultEffects
                                        }
                                    }
                                }
                            }

                            StyledText {
                                id: label

                                Layout.fillWidth: true
                                text: row.task?.text ?? ""
                                elide: Text.ElideRight
                                font: Tokens.font.body.medium
                                color: Colours.palette.m3onSurface
                                opacity: row.done ? 0.5 : 1

                                Behavior on opacity {
                                    Anim {
                                        type: Anim.DefaultEffects
                                    }
                                }

                                // Strike-through for finished tasks.
                                StyledRect {
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitWidth: Math.min(label.implicitWidth, label.width)
                                    implicitHeight: 1.5
                                    color: Colours.palette.m3onSurface
                                    visible: row.done
                                }
                            }

                            IconButton {
                                type: IconButton.Text
                                isRound: true
                                icon: "close"
                                inactiveOnColour: Colours.palette.m3onSurfaceVariant
                                onClicked: Todos.remove(row.modelData)
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                visible: Todos.items.length === 0
                spacing: Tokens.spacing.small

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "checklist"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.extraLarge
                    opacity: 0.6
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Tr.tr("Type a task above and press Enter")
                    font: Tokens.font.body.medium
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }
    }
}
