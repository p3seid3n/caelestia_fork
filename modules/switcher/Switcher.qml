pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.effects
import qs.services
import qs.utils

// Super + Tab (services/WindowSwitcher.qml): a card in the middle of the focused screen with a
// still frame of every window on the workspace and its app icon, like Alt + Tab on Windows.
// Only exists while it is open (plus its closing fade). A quick Super + Tab that is let go
// within a moment switches without the card ever flashing up.
Scope {
    id: root

    property bool closing

    Connections {
        function onOpenChanged(): void {
            if (WindowSwitcher.open) {
                root.closing = false;
                closeTimer.stop();
            } else {
                root.closing = true;
                closeTimer.restart();
            }
        }

        target: WindowSwitcher
    }

    Timer {
        id: closeTimer

        interval: Tokens.anim.durations.expressiveDefaultEffects + 40
        onTriggered: root.closing = false
    }

    LazyLoader {
        active: WindowSwitcher.open || root.closing

        StyledWindow {
            id: win

            screen: Quickshell.screens.find(s => s.name === Hypr.focusedMonitor?.name) ?? Quickshell.screens[0]
            name: "window-switcher"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.keyboardFocus: WindowSwitcher.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: WindowSwitcher.open ? null : empty

            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Region {
                id: empty
            }

            Item {
                id: content

                // Appears after a short beat, so a quick Super + Tab doesn't flash the card.
                property bool revealed

                anchors.fill: parent
                focus: true

                Component.onCompleted: revealTimer.start()
                Keys.onPressed: event => {
                    const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
                    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Right || event.key === Qt.Key_Down)
                        shift ? WindowSwitcher.prev() : WindowSwitcher.next();
                    else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Left || event.key === Qt.Key_Up)
                        WindowSwitcher.prev();
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
                        WindowSwitcher.commit();
                    else if (event.key === Qt.Key_Escape)
                        WindowSwitcher.close();
                    else
                        return;
                    content.revealed = true;
                    event.accepted = true;
                }
                Keys.onReleased: event => {
                    if (event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R || event.key === Qt.Key_Meta) {
                        WindowSwitcher.commit();
                        event.accepted = true;
                    }
                }

                Timer {
                    id: revealTimer

                    interval: 90
                    onTriggered: content.revealed = true
                }

                // Clicking beside the card closes it.
                MouseArea {
                    anchors.fill: parent
                    onClicked: WindowSwitcher.close()
                }

                StyledRect {
                    id: card

                    readonly property real maxRow: win.width - 160
                    readonly property real previewHeight: 150
                    // Every card's width at full size; scaled down together when they don't fit.
                    readonly property var widths: WindowSwitcher.entries.map(t => {
                        const s = t?.lastIpcObject?.size;
                        const aspect = s && s[1] > 0 ? s[0] / s[1] : 16 / 10;
                        return Math.max(120, Math.min(300, previewHeight * aspect));
                    })
                    readonly property real naturalRow: widths.reduce((a, b) => a + b, 0) + Math.max(0, widths.length - 1) * Tokens.spacing.medium
                    readonly property real fit: naturalRow > maxRow ? maxRow / naturalRow : 1

                    anchors.centerIn: parent
                    implicitWidth: row.width + Tokens.padding.large * 2
                    implicitHeight: row.height + Tokens.padding.large * 2
                    radius: Tokens.rounding.extraLarge
                    color: Colours.tPalette.m3surfaceContainer

                    opacity: content.revealed && WindowSwitcher.open ? 1 : 0
                    scale: content.revealed && WindowSwitcher.open ? 1 : 0.94

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }

                    Behavior on scale {
                        Anim {
                            type: Anim.FastSpatial
                        }
                    }

                    Elevation {
                        anchors.fill: parent
                        z: -1
                        radius: card.radius
                        level: 3
                    }

                    // Swallows clicks on the card's own background.
                    MouseArea {
                        anchors.fill: parent
                    }

                    // The selection: one shape sliding from card to card.
                    StyledRect {
                        readonly property Item target: repeater.count > WindowSwitcher.index ? repeater.itemAt(WindowSwitcher.index) : null

                        x: row.x + (target?.x ?? 0) - Tokens.padding.small
                        y: row.y - Tokens.padding.small
                        width: (target?.width ?? 0) + Tokens.padding.small * 2
                        height: row.height + Tokens.padding.small * 2
                        visible: target !== null
                        radius: Tokens.rounding.large
                        color: Colours.palette.m3secondaryContainer

                        Behavior on x {
                            Anim {
                                type: Anim.FastSpatial
                            }
                        }

                        Behavior on width {
                            Anim {
                                type: Anim.FastSpatial
                            }
                        }
                    }

                    Row {
                        id: row

                        x: Tokens.padding.large
                        y: Tokens.padding.large
                        spacing: Tokens.spacing.medium

                        Repeater {
                            id: repeater

                            model: WindowSwitcher.entries

                            Entry {
                                fullWidth: card.widths[index] ?? 160
                                fit: card.fit
                                previewHeight: card.previewHeight
                            }
                        }
                    }
                }
            }
        }
    }

    component Entry: Item {
        id: entry

        required property var modelData
        required property int index
        required property real fullWidth
        required property real fit
        required property real previewHeight
        readonly property bool chosen: WindowSwitcher.index === index
        readonly property string appClass: modelData?.lastIpcObject?.class ?? ""

        width: fullWidth * fit
        height: header.height + Tokens.spacing.small + preview.height

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: WindowSwitcher.select(entry.index)
            onClicked: {
                WindowSwitcher.select(entry.index);
                WindowSwitcher.commit();
            }
        }

        // App icon and title
        Row {
            id: header

            width: parent.width
            spacing: Tokens.spacing.small

            IconImage {
                id: appIcon

                implicitSize: 20
                asynchronous: true
                source: Icons.getAppIcon(entry.appClass, "application-x-executable")
            }

            StyledText {
                width: parent.width - appIcon.width - parent.spacing
                anchors.verticalCenter: appIcon.verticalCenter
                text: entry.modelData?.title || entry.appClass
                elide: Text.ElideRight
                font: Tokens.font.label.medium
                color: entry.chosen ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
            }
        }

        ClippingRectangle {
            id: preview

            y: header.height + Tokens.spacing.small
            width: parent.width
            height: entry.previewHeight * entry.fit
            radius: Tokens.rounding.medium
            color: Colours.palette.m3surfaceContainerHighest

            // While the frame is taken: the app's icon.
            IconImage {
                anchors.centerIn: parent
                implicitSize: Math.min(parent.height * 0.4, 56)
                visible: !(shot.item?.hasContent ?? false)
                asynchronous: true
                source: appIcon.source
            }

            // One still frame per window, taken when the switcher opens.
            Loader {
                id: shot

                anchors.centerIn: parent
                active: entry.modelData?.wayland ?? false // qmllint disable missing-property

                sourceComponent: ScreencopyView {
                    captureSource: entry.modelData?.wayland ?? null // qmllint disable missing-property
                    live: false
                    constraintSize.width: preview.width
                    constraintSize.height: preview.height
                    Component.onCompleted: captureFrame()
                }
            }
        }

        // Ring round the chosen window's frame.
        StyledRect {
            x: preview.x - 2
            y: preview.y - 2
            width: preview.width + 4
            height: preview.height + 4
            radius: preview.radius + 2
            color: "transparent"
            border.width: 2
            border.color: Colours.palette.m3primary
            opacity: entry.chosen ? 1 : 0

            Behavior on opacity {
                Anim {
                    type: Anim.FastEffects
                }
            }
        }
    }
}
