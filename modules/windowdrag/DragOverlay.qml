pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.utils

// Drawn over everything on the screen being dragged on (part of the drawers window, which already
// covers the screen; it takes no input - Hyprland keeps the pointer for the drag).
//   - The window as a small preview beside the cursor. It collapses out of the real window when
//     the drag starts; the frame is taken once, so nothing large is redrawn while dragging.
//   - An outline and fill where the window will land: the half of the tiled window under the
//     cursor (the other half shows where that window moves to), or the floating window's new spot.
//   - The bar's workspaces as drop targets once the preview comes near: they grow like a dock,
//     the one under the preview is inverted, holding it there fills it and switches to it.
//   - Drops: onto a workspace the preview is sucked into it; elsewhere it grows into the outline.
Item {
    id: root

    required property ShellScreen screen

    readonly property ShellScreen dragScreen: WindowDrag.dropScreen ?? WindowDrag.screen
    readonly property bool mine: WindowDrag.active && dragScreen === screen
    readonly property bool carrying: mine && WindowDrag.carrying
    readonly property string phase: mine ? WindowDrag.phase : "idle"

    // Cursor in this item's coordinates.
    readonly property real cx: WindowDrag.cursor.x - screen.x
    readonly property real cy: WindowDrag.cursor.y - screen.y

    // The bar's workspace column on this screen and its right edge.
    readonly property Item column: WindowDrag.targets[screen.name] ?? null
    readonly property real barRight: {
        cx; // follow the cursor (the bar can move when the dashboard or a special workspace opens)
        return column ? column.mapToItem(root, column.width, 0).x : 0;
    }
    // 0 far from the bar's workspaces, 1 right on them.
    readonly property real nearness: carrying && column ? Math.max(0, Math.min(1, 1 - (cx - barRight) / 260)) : 0

    readonly property int gapsIn: num(Hypr.options["general:gaps_in"], 5)
    readonly property int windowRadius: num(Hypr.options["decoration:rounding"], Tokens.rounding.medium)
    readonly property real bubbleSize: Tokens.sizes.bar.innerWidth - Tokens.padding.small

    // Where the window will land and where the window it shares a slot with goes (width 0: none).
    readonly property var landing: computeLanding()
    property rect lastLanding

    // The window's size and the preview's size beside the cursor.
    readonly property rect startLocal: Qt.rect(WindowDrag.startRect.x - screen.x, WindowDrag.startRect.y - screen.y, WindowDrag.startRect.width, WindowDrag.startRect.height)
    readonly property real fit: Math.min(220 / Math.max(1, startLocal.width), 160 / Math.max(1, startLocal.height), 1)
    readonly property real thumbScale: 1 - 0.35 * nearness
    readonly property rect thumb: {
        const w = startLocal.width * fit * thumbScale;
        const h = startLocal.height * fit * thumbScale;
        let x = cx + 22;
        let y = cy + 18;
        if (x + w > width - 12)
            x = cx - 22 - w;
        if (y + h > height - 12)
            y = cy - 18 - h;
        return Qt.rect(x, y, w, h);
    }

    // Animation progress: collapse into the preview, grow into the outline, sucked into a workspace.
    property real collapse
    property real settle
    property real genie

    function num(v: var, d: int): int {
        const n = parseInt(String(v ?? "").trim().split(/\s+/)[0]);
        return isNaN(n) ? d : n;
    }

    function mix(a: real, b: real, t: real): real {
        return a + (b - a) * t;
    }

    function mixRect(a: rect, b: rect, t: real): rect {
        return Qt.rect(mix(a.x, b.x, t), mix(a.y, b.y, t), mix(a.width, b.width, t), mix(a.height, b.height, t));
    }

    function computeLanding(): var {
        const none = {
            rect: Qt.rect(0, 0, 0, 0),
            other: Qt.rect(0, 0, 0, 0)
        };
        if (!carrying || WindowDrag.hoverWs !== "")
            return none;

        const gx = WindowDrag.cursor.x;
        const gy = WindowDrag.cursor.y;

        // Floating: the window moves with the cursor.
        if (WindowDrag.floatingAtStart) {
            const r = WindowDrag.startRect;
            return {
                rect: Qt.rect(r.x + gx - WindowDrag.startCursor.x - screen.x, r.y + gy - WindowDrag.startCursor.y - screen.y, r.width, r.height),
                other: none.other
            };
        }

        // Tiled: Hyprland splits the tiled window under the cursor, on the cursor's side.
        const monitor = Hypr.monitorFor(screen);
        const me = WindowDrag.norm(WindowDrag.address);
        const tiled = (monitor?.activeWorkspace?.toplevels.values ?? []).map(t => t.lastIpcObject).filter(o => o?.at && o?.size && !o.floating && WindowDrag.norm(o.address) !== me);

        if (tiled.length === 0) {
            const res = monitor?.lastIpcObject?.reserved ?? [0, 0, 0, 0];
            const g = WindowLayout.edgeGap();
            return {
                rect: Qt.rect(res[0] + g, res[1] + g, width - res[0] - res[2] - g * 2, height - res[1] - res[3] - g * 2),
                other: none.other
            };
        }

        const hit = tiled.find(o => gx >= o.at[0] && gy >= o.at[1] && gx < o.at[0] + o.size[0] && gy < o.at[1] + o.size[1]);
        if (!hit)
            return none;

        const x = hit.at[0] - screen.x;
        const y = hit.at[1] - screen.y;
        const w = hit.size[0];
        const h = hit.size[1];
        const g = gapsIn * 2;
        if (w > h) {
            const half = (w - g) / 2;
            const left = gx - screen.x < x + w / 2;
            const a = Qt.rect(x, y, half, h);
            const b = Qt.rect(x + half + g, y, half, h);
            return {
                rect: left ? a : b,
                other: left ? b : a
            };
        }
        const half = (h - g) / 2;
        const top = gy - screen.y < y + h / 2;
        const a = Qt.rect(x, y, w, half);
        const b = Qt.rect(x, y + half + g, w, half);
        return {
            rect: top ? a : b,
            other: top ? b : a
        };
    }

    // Picks the workspace under the preview (the closest bubble the cursor is level with).
    function updateHover(): void {
        if (!carrying || nearness <= 0 || cx > barRight + 90) {
            if (mine && WindowDrag.carrying)
                WindowDrag.hoverWs = "";
            return;
        }
        let best = null;
        let bestDist = Infinity;
        const bubbles = [];
        for (let i = 0; i < bubbleRepeater.count; i++)
            bubbles.push(bubbleRepeater.itemAt(i));
        bubbles.push(newBubble);
        for (const b of bubbles) {
            if (!b || !b.visible)
                continue;
            const dist = Math.abs(cy - b.centre.y);
            if (dist < (bubbleSize * b.scale) / 2 + Tokens.spacing.small && dist < bestDist) {
                best = b;
                bestDist = dist;
            }
        }
        WindowDrag.hoverWs = best ? best.wsSel : "";
        if (best)
            WindowDrag.dropPoint = Qt.point(best.centre.x + bubbleSize * (best.scale - 1) / 2, best.centre.y);
    }

    anchors.fill: parent
    visible: mine

    onLandingChanged: {
        if (landing.rect.width > 0)
            lastLanding = landing.rect;
    }
    onCxChanged: updateHover()
    onCyChanged: updateHover()

    Connections {
        function onPhaseChanged(): void {
            const phase = WindowDrag.phase;
            if (phase === "carry") {
                settleAnim.stop();
                genieAnim.stop();
                root.settle = 0;
                root.genie = 0;
                collapseAnim.restart();
            } else if (phase === "home") {
                settleAnim.restart();
            } else if (phase === "genie") {
                genieAnim.restart();
            }
        }

        target: WindowDrag
    }

    Anim {
        id: collapseAnim

        target: root
        property: "collapse"
        from: 0
        to: 1
        type: Anim.Emphasized
    }

    Anim {
        id: settleAnim

        target: root
        property: "settle"
        from: 0
        to: 1
        type: Anim.StandardSmall
    }

    NumberAnimation {
        id: genieAnim

        target: root
        property: "genie"
        from: 0
        to: 1
        duration: 420
        easing.type: Easing.InCubic
    }

    // --- Landing outline -------------------------------------------------------------------
    Landing {
        target: root.landing.other
        fillOpacity: 0.06
        borderOpacity: 0.35
    }

    Landing {
        target: root.landing.rect
        fillOpacity: 0.16
        borderOpacity: 1
    }

    // --- Workspaces as drop targets ------------------------------------------------------------
    Repeater {
        id: bubbleRepeater

        model: {
            const items = root.column?.workspaces ?? [];
            return root.mine ? items.filter(i => i) : [];
        }

        Bubble {
            required property Item modelData

            wsSel: String(modelData.ws ?? "")
            label: wsSel
            centre: {
                root.cx;
                root.cy;
                return modelData.mapToItem(root, modelData.width / 2, root.bubbleSize / 2);
            }
        }
    }

    // A new, empty workspace under the last one.
    Bubble {
        id: newBubble

        readonly property Item last: bubbleRepeater.count > 0 ? bubbleRepeater.itemAt(bubbleRepeater.count - 1) : null

        visible: root.mine && last !== null
        wsSel: "empty"
        icon: "add"
        centre: last ? Qt.point(last.centre.x, last.centre.y + root.bubbleSize + Tokens.spacing.medium) : Qt.point(0, 0)
    }

    // --- The preview -----------------------------------------------------------------------------
    Item {
        id: preview

        readonly property rect carryRect: root.mixRect(root.startLocal, root.thumb, root.collapse)
        readonly property rect homeTarget: root.lastLanding.width > 0 ? root.lastLanding : Qt.rect(root.thumb.x - root.thumb.width * 0.1, root.thumb.y - root.thumb.height * 0.1, root.thumb.width * 1.2, root.thumb.height * 1.2)
        readonly property rect now: root.phase === "home" ? root.mixRect(root.thumb, homeTarget, root.settle) : carryRect
        // Genie: squeezed sideways first, then lengthwise, while it flies into the workspace.
        readonly property real squeezeX: 1 - 0.9 * Math.pow(root.genie, 0.6)
        readonly property real squeezeY: 1 - 0.9 * Math.pow(root.genie, 1.6)
        readonly property real flyX: root.mix(now.x + now.width / 2, WindowDrag.dropPoint.x, Math.pow(root.genie, 1.2))
        readonly property real flyY: root.mix(now.y + now.height / 2, WindowDrag.dropPoint.y, Math.pow(root.genie, 0.8))

        x: flyX - width / 2
        y: flyY - height / 2
        width: now.width * squeezeX
        height: now.height * squeezeY
        opacity: root.phase === "home" ? 1 - root.settle : 1 - Math.pow(root.genie, 3)
        visible: root.mine && width > 1 && height > 1

        Elevation {
            anchors.fill: parent
            radius: card.radius
            level: 4
            opacity: root.collapse
        }

        ClippingRectangle {
            id: card

            anchors.fill: parent
            radius: Math.min(root.windowRadius, Tokens.rounding.large)
            color: Colours.palette.m3surfaceContainerHigh

            MaterialIcon {
                anchors.centerIn: parent
                visible: !(shot.item?.hasContent ?? false)
                text: Icons.getAppCategoryIcon(WindowDrag.toplevel?.lastIpcObject.class ?? "", "select_window")
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.large
            }

            // One still frame, taken when the drag starts.
            Loader {
                id: shot

                active: root.mine && WindowDrag.toplevel !== null

                sourceComponent: ScreencopyView {
                    id: view

                    readonly property real capFit: Math.min(480 / Math.max(1, root.startLocal.width), 360 / Math.max(1, root.startLocal.height), 1)

                    captureSource: WindowDrag.toplevel?.wayland ?? null // qmllint disable unresolved-type
                    live: false
                    constraintSize.width: root.startLocal.width * capFit
                    constraintSize.height: root.startLocal.height * capFit

                    transform: Scale {
                        xScale: card.width / Math.max(1, view.width)
                        yScale: card.height / Math.max(1, view.height)
                    }

                    onHasContentChanged: {
                        if (hasContent)
                            WindowDrag.hideReal();
                    }
                    Component.onCompleted: captureFrame()
                }
            }
        }

        StyledRect {
            anchors.fill: parent
            radius: card.radius
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outline, 0.5)
        }
    }

    component Landing: StyledRect {
        required property rect target
        property real fillOpacity
        property real borderOpacity

        readonly property bool shown: target.width > 0

        x: shown ? target.x : x
        y: shown ? target.y : y
        width: shown ? target.width : width
        height: shown ? target.height : height
        opacity: shown ? 1 : 0
        radius: root.windowRadius
        color: Qt.alpha(Colours.palette.m3primary, fillOpacity)
        border.width: 2
        border.color: Qt.alpha(Colours.palette.m3primary, borderOpacity)

        Behavior on x {
            Anim {
                type: Anim.FastSpatial
            }
        }

        Behavior on y {
            Anim {
                type: Anim.FastSpatial
            }
        }

        Behavior on width {
            Anim {
                type: Anim.FastSpatial
            }
        }

        Behavior on height {
            Anim {
                type: Anim.FastSpatial
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    component Bubble: Item {
        id: bubble

        property string wsSel
        property string label
        property string icon
        property point centre

        readonly property bool hovered: wsSel !== "" && (WindowDrag.hoverWs === wsSel || (root.phase === "genie" && WindowDrag.dropWs === wsSel))
        readonly property bool current: wsSel === String(WindowDrag.activeWsOn(root.screen))
        // Dock-style magnification by how level the cursor is with this bubble.
        readonly property real level: Math.max(0, 1 - Math.abs(root.cy - centre.y) / 110)

        x: centre.x - width / 2
        y: centre.y - height / 2
        width: root.bubbleSize
        height: root.bubbleSize
        scale: 1 + 0.55 * level * root.nearness
        transformOrigin: Item.Left
        opacity: root.nearness > 0.02 || root.phase === "genie" ? 1 : 0

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        StyledRect {
            anchors.fill: parent
            radius: Tokens.rounding.full
            color: bubble.hovered ? Colours.palette.m3onSurface : bubble.current ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHighest
            border.width: bubble.current && !bubble.hovered ? 2 : 0
            border.color: Colours.palette.m3primary

            // Fills while held over another workspace: when full, that workspace opens.
            StyledRect {
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                radius: Tokens.rounding.full
                color: Qt.alpha(Colours.palette.m3surface, 0.3)
                scale: bubble.hovered && !bubble.current && bubble.wsSel !== "empty" ? 1 : 0

                Behavior on scale {
                    enabled: bubble.hovered

                    NumberAnimation {
                        duration: 650
                    }
                }
            }
        }

        StyledText {
            anchors.centerIn: parent
            visible: bubble.icon === ""
            text: bubble.label
            font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
            color: bubble.hovered ? Colours.palette.m3surface : bubble.current ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
        }

        MaterialIcon {
            anchors.centerIn: parent
            visible: bubble.icon !== ""
            text: bubble.icon
            color: bubble.hovered ? Colours.palette.m3surface : Colours.palette.m3onSurface
            fontStyle: Tokens.font.icon.medium
        }
    }
}
