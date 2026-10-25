pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

// iOS home screen-style grid of dashboard widgets (same behaviour as the Home tab's TileGrid).
// Widgets are packed densely (first free spot, left to right, top to bottom) on an
// 8-column grid. In edit mode they wiggle and can be dragged to reorder, resized
// with the corner handle (within the limits of their type) and removed with the badge.
Item {
    id: root

    property bool editing
    // Widget being dragged right now ("" when none); the ghost shows where it will land.
    property string dragId

    readonly property int columns: DashboardWidgets.columns
    readonly property real gap: Tokens.spacing.small
    readonly property real cell: (width - gap * (columns - 1)) / columns
    readonly property var packed: pack(DashboardWidgets.widgets)

    signal editRequested

    function pack(widgets: var): var {
        const taken = [];
        const pos = {};
        let rows = 0;
        const free = (r, c, w, h) => {
            for (let rr = r; rr < r + h; rr++)
                for (let cc = c; cc < c + w; cc++)
                    if (taken[rr]?.[cc])
                        return false;
            return true;
        };
        for (const t of widgets) {
            const w = Math.min(t.w, columns);
            const h = t.h;
            let placed = false;
            for (let r = 0; !placed; r++) {
                for (let c = 0; c + w <= columns && !placed; c++) {
                    if (free(r, c, w, h)) {
                        for (let rr = r; rr < r + h; rr++) {
                            taken[rr] = taken[rr] ?? [];
                            for (let cc = c; cc < c + w; cc++)
                                taken[rr][cc] = true;
                        }
                        pos[t.id] = {
                            col: c,
                            row: r,
                            w,
                            h
                        };
                        rows = Math.max(rows, r + h);
                        placed = true;
                    }
                }
            }
        }
        return {
            pos,
            rows
        };
    }

    function span(n: int): real {
        return n * cell + (n - 1) * gap;
    }

    implicitHeight: packed.rows > 0 ? packed.rows * (cell + gap) - gap : 0

    Behavior on implicitHeight {
        Anim {}
    }

    // Landing spot of the dragged widget.
    StyledRect {
        readonly property var p: root.packed.pos[root.dragId] ?? null

        x: p ? p.col * (root.cell + root.gap) : 0
        y: p ? p.row * (root.cell + root.gap) : 0
        width: p ? root.span(p.w) : 0
        height: p ? root.span(p.h) : 0
        visible: p !== null
        radius: Tokens.rounding.extraLarge
        color: Qt.alpha(Colours.palette.m3primary, 0.12)
        border.width: 2
        border.color: Qt.alpha(Colours.palette.m3primary, 0.45)

        Behavior on x {
            Anim {}
        }

        Behavior on y {
            Anim {}
        }

        Behavior on width {
            Anim {}
        }

        Behavior on height {
            Anim {}
        }
    }

    Repeater {
        // Sorted ids: the model only changes when widgets are added or removed, so
        // delegates survive reordering and can animate to their new place.
        model: ScriptModel {
            values: DashboardWidgets.widgets.map(t => t.id).sort()
        }

        Item {
            id: slot

            required property string modelData
            readonly property var p: root.packed.pos[modelData] ?? ({
                    col: 0,
                    row: 0,
                    w: 1,
                    h: 1
                })
            readonly property int widgetIndex: DashboardWidgets.widgets.findIndex(t => t.id === modelData)

            property bool dragging
            property point dragPos

            onDraggingChanged: {
                if (dragging)
                    root.dragId = modelData;
                else if (root.dragId === modelData)
                    root.dragId = "";
            }

            x: dragging ? dragPos.x : p.col * (root.cell + root.gap)
            y: dragging ? dragPos.y : p.row * (root.cell + root.gap)
            width: root.span(p.w)
            height: root.span(p.h)
            z: dragging ? 10 : 0

            Behavior on x {
                enabled: !slot.dragging

                Anim {}
            }
            Behavior on y {
                enabled: !slot.dragging

                Anim {}
            }
            Behavior on width {
                Anim {}
            }
            Behavior on height {
                Anim {}
            }

            WidgetCard {
                id: card

                anchors.fill: parent
                widgetType: DashboardWidgets.byId[slot.modelData]?.type ?? ""
                editing: root.editing
                scale: slot.dragging ? 1.05 : 1

                onEditRequested: root.editRequested()

                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                // Wiggle while editing.
                SequentialAnimation on rotation {
                    running: root.editing && !slot.dragging
                    loops: Animation.Infinite
                    alwaysRunToEnd: true

                    NumberAnimation {
                        to: -0.7
                        duration: 110 + (slot.modelData.length % 5) * 12
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        to: 0.7
                        duration: 130 + (slot.modelData.length % 3) * 15
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        to: 0
                        duration: 90
                        easing.type: Easing.InOutSine
                    }
                }
            }

            // Drag to reorder (edit mode only).
            MouseArea {
                id: dragArea

                property point start
                property point startPos

                anchors.fill: parent
                visible: root.editing
                preventStealing: true
                cursorShape: slot.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                onPressed: e => {
                    start = mapToItem(root, e.x, e.y);
                    startPos = Qt.point(slot.x, slot.y);
                }
                onPositionChanged: e => {
                    const pt = mapToItem(root, e.x, e.y);
                    const dx = pt.x - start.x;
                    const dy = pt.y - start.y;
                    if (!slot.dragging && Math.abs(dx) + Math.abs(dy) < 6)
                        return;
                    slot.dragPos = Qt.point(startPos.x + dx, startPos.y + dy);
                    slot.dragging = true;

                    if (cooldown.running)
                        return;
                    // Drop target: the widget under the dragged widget's centre.
                    const cx = slot.dragPos.x + slot.width / 2;
                    const cy = slot.dragPos.y + slot.height / 2;
                    const widgets = DashboardWidgets.widgets;
                    for (let j = 0; j < widgets.length; j++) {
                        if (widgets[j].id === slot.modelData)
                            continue;
                        const q = root.packed.pos[widgets[j].id];
                        if (!q)
                            continue;
                        const qx = q.col * (root.cell + root.gap);
                        const qy = q.row * (root.cell + root.gap);
                        if (cx >= qx && cx <= qx + root.span(q.w) && cy >= qy && cy <= qy + root.span(q.h)) {
                            DashboardWidgets.move(slot.widgetIndex, j);
                            cooldown.restart();
                            break;
                        }
                    }
                }
                onReleased: slot.dragging = false
                onCanceled: slot.dragging = false
            }

            Timer {
                id: cooldown

                interval: 280
            }

            // Remove badge
            StyledRect {
                x: -width / 3
                y: -height / 3
                implicitWidth: 26
                implicitHeight: 26
                radius: Tokens.rounding.full
                color: Colours.palette.m3surfaceContainerHighest
                border.width: 1
                border.color: Colours.palette.m3outlineVariant
                visible: scale > 0
                scale: root.editing && !slot.dragging ? 1 : 0

                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "remove"
                    color: Colours.palette.m3onSurface
                }

                StateLayer {
                    radius: Tokens.rounding.full
                    onClicked: DashboardWidgets.remove(slot.modelData)
                }
            }

            // Resize handle: a corner arc like iOS. Drag it, the size snaps to the grid.
            Item {
                id: handle

                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 8
                implicitWidth: 20
                implicitHeight: 20
                visible: scale > 0
                scale: root.editing && !slot.dragging ? 1 : 0

                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        startX: handle.width - 2
                        startY: 2
                        strokeWidth: 3
                        strokeColor: Colours.palette.m3onSurface
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap

                        PathArc {
                            x: 2
                            y: handle.height - 2
                            radiusX: handle.width - 4
                            radiusY: handle.height - 4
                            direction: PathArc.Clockwise
                        }
                    }
                }

                MouseArea {
                    property point start
                    property real startW
                    property real startH

                    anchors.fill: parent
                    anchors.margins: -8
                    preventStealing: true
                    cursorShape: Qt.SizeFDiagCursor

                    onPressed: e => {
                        start = mapToItem(root, e.x, e.y);
                        startW = slot.width;
                        startH = slot.height;
                    }
                    onPositionChanged: e => {
                        const pt = mapToItem(root, e.x, e.y);
                        const w = Math.round((startW + pt.x - start.x + root.gap) / (root.cell + root.gap));
                        const h = Math.round((startH + pt.y - start.y + root.gap) / (root.cell + root.gap));
                        if (w !== slot.p.w || h !== slot.p.h)
                            DashboardWidgets.resize(slot.modelData, w, h);
                    }
                }
            }
        }
    }
}
