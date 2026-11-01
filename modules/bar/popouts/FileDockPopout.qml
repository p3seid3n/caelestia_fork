pragma ComponentBehavior: Bound

import "../components"
import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// The whole file dock (opened by hovering the stack in the bar): drag any file into an app,
// tap to open it, the small cross removes the shortcut (the file stays where it is).
ColumnLayout {
    id: root

    readonly property int columns: 3
    readonly property real tile: 84

    spacing: Tokens.spacing.small
    implicitWidth: columns * tile + (columns - 1) * Tokens.spacing.small

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: "inventory_2"
            color: Colours.palette.m3primary
            fill: 1
        }

        StyledText {
            Layout.fillWidth: true
            text: Tr.tr("File dock")
            font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
            color: Colours.palette.m3onSurface
        }

        IconButton {
            type: IconButton.Text
            isRound: true
            icon: "clear_all"
            onClicked: FileDock.clear()
        }
    }

    StyledText {
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        Layout.bottomMargin: Tokens.spacing.extraSmall
        text: Tr.tr("Drag into any app · screenshots land here")
        font: Tokens.font.body.small
        color: Colours.palette.m3onSurfaceVariant
    }

    Flickable {
        Layout.fillWidth: true
        implicitHeight: Math.min(grid.implicitHeight, (root.tile + 22 + Tokens.spacing.small) * 3 - Tokens.spacing.small)
        contentHeight: grid.implicitHeight
        interactive: contentHeight > height + 1
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Grid {
            id: grid

            width: parent.width
            columns: root.columns
            spacing: Tokens.spacing.small

            move: Transition {
                Anim {
                    properties: "x,y"
                    type: Anim.FastSpatial
                }
            }

            add: Transition {
                Anim {
                    property: "scale"
                    from: 0.6
                    to: 1
                    type: Anim.FastSpatial
                }
            }

            Repeater {
                model: ScriptModel {
                    values: FileDock.items.map(i => i.path)
                }

                Item {
                    id: cell

                    required property string modelData

                    width: root.tile
                    height: root.tile + 22

                    DockThumb {
                        id: thumb

                        width: root.tile
                        height: root.tile
                        radius: Tokens.rounding.medium
                        path: cell.modelData
                        scale: dragging ? 0.92 : hover.hovered ? 1.03 : 1

                        Behavior on scale {
                            Anim {
                                type: Anim.FastSpatial
                            }
                        }

                        HoverHandler {
                            id: hover
                        }

                        TapHandler {
                            onTapped: Quickshell.execDetached(["xdg-open", cell.modelData])
                        }

                        // Remove the shortcut
                        StyledRect {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 4
                            implicitWidth: 22
                            implicitHeight: 22
                            radius: Tokens.rounding.full
                            color: Colours.palette.m3surfaceContainerHighest
                            opacity: hover.hovered && !thumb.dragging ? 1 : 0
                            visible: opacity > 0

                            Behavior on opacity {
                                Anim {
                                    type: Anim.FastEffects
                                }
                            }

                            StateLayer {
                                radius: Tokens.rounding.full
                                onClicked: FileDock.remove(cell.modelData)
                            }

                            MaterialIcon {
                                anchors.centerIn: parent
                                text: "close"
                                color: Colours.palette.m3onSurface
                                fontStyle: Tokens.font.icon.builders.small.size(14).build()
                            }
                        }
                    }

                    StyledText {
                        anchors.top: thumb.bottom
                        anchors.topMargin: 4
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideMiddle
                        text: FileDock.nameOf(cell.modelData)
                        font: Tokens.font.label.small
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }
        }
    }
}
