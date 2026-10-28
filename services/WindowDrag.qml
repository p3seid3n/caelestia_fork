pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// Super + drag with a preview (Lua configs; see WindowLayout.runtimeLua and modules/windowdrag).
//
// Hyprland keeps doing the actual move, so the layout behaves exactly like a normal drag (tiled
// windows step out of the layout and the others close the gap). The Lua side reports the drag
// over socket2 ("custom>>kairosdrag:start|move|end,...") and the shell:
//   1. takes one still frame of the window, then hides the real window (opacity 0), so only a
//      small preview follows the cursor - nothing large is redrawn while dragging,
//   2. draws an outline where the window will land (the free half of the tiled window under the
//      cursor, or the floating window's new spot),
//   3. turns the bar's workspaces into drop targets once the preview comes close: they grow,
//      the one under the preview is inverted, and holding it there for a moment switches to that
//      workspace (the window comes along),
//   4. on release over a workspace the window moves there and you stay where you are (the
//      preview is sucked into the workspace); anywhere else the window lands where the outline was.
Singleton {
    id: root

    // "idle", "carry" (being dragged), "home" (dropped on the screen) or "genie" (dropped on a
    // workspace in the bar).
    property string phase: "idle"
    readonly property bool active: phase !== "idle"
    readonly property bool carrying: phase === "carry"

    property string address
    property bool floatingAtStart
    // Global logical coordinates, like Hyprland's.
    property rect startRect
    property point startCursor
    property point cursor
    property int startWs
    property HyprlandToplevel toplevel: null
    // The real window is hidden (after the preview frame was taken).
    property bool hidden

    // Workspace the preview is over, as a Hyprland workspace selector ("3", "empty" for a new one);
    // "" when not over one. Set by the overlay.
    property string hoverWs: ""
    // The workspace it was dropped on (for the drop animation).
    property string dropWs: ""
    // Where the drop animation goes (overlay coordinates of the cursor's screen).
    property point dropPoint
    // Screen the drag is on (the cursor's).
    readonly property ShellScreen screen: screenAt(cursor.x, cursor.y)
    // Kept while the drop animation plays, even if the cursor moves to another screen.
    property ShellScreen dropScreen: null

    // Bar workspace columns, by screen name (registered by bar/components/workspaces/Workspaces.qml).
    property var targets: ({})

    function register(screenName: string, item: Item): void {
        const next = Object.assign({}, targets);
        next[screenName] = item;
        targets = next;
    }

    function unregister(screenName: string, item: Item): void {
        if (targets[screenName] !== item)
            return;
        const next = Object.assign({}, targets);
        delete next[screenName];
        targets = next;
    }

    function screenAt(x: real, y: real): ShellScreen {
        for (const s of Quickshell.screens)
            if (x >= s.x && y >= s.y && x < s.x + s.width && y < s.y + s.height)
                return s;
        return Quickshell.screens[0] ?? null;
    }

    function norm(address: string): string {
        return String(address ?? "").toLowerCase().replace(/^0x/, "");
    }

    function activeWsOn(screen: ShellScreen): int {
        return Hypr.monitorFor(screen)?.activeWorkspace?.id ?? 0;
    }

    // Called by the overlay once the preview has its frame (or by the fallback timer).
    function hideReal(): void {
        if (!active || hidden || address === "")
            return;
        hidden = true;
        WindowLayout.luaEval(`pcall(KAIROS.hide, "${address}")`);
    }

    function finish(ws: string, x: var, y: var): void {
        const pos = x === undefined || x === null ? "nil, nil" : `${Math.round(x)}, ${Math.round(y)}`;
        WindowLayout.luaEval(`pcall(KAIROS.dragFinish, "${address}", "${ws}", ${pos})`);
        hidden = false;
    }

    function handle(data: string): void {
        const parts = data.slice("kairosdrag:".length).split(",");
        const kind = parts[0];
        const num = i => parseInt(parts[i]) || 0;

        if (kind === "start") {
            phaseTimer.stop();
            springTimer.stop();
            address = parts[1];
            floatingAtStart = parts[2] === "1";
            startRect = Qt.rect(num(3), num(4), num(5), num(6));
            startCursor = Qt.point(num(7), num(8));
            cursor = startCursor;
            startWs = num(9);
            const a = norm(address);
            toplevel = Hypr.toplevels.values.find(t => norm(t.address) === a) ?? null;
            hidden = false;
            hoverWs = "";
            dropScreen = null;
            phase = "carry";
            hideFallback.restart();
        } else if (kind === "move") {
            if (carrying)
                cursor = Qt.point(num(1), num(2));
        } else if (kind === "end") {
            if (!carrying)
                return;
            cursor = Qt.point(num(1), num(2));
            hideFallback.stop();
            springTimer.stop();
            dropScreen = screen;
            dropWs = hoverWs;
            const windowWs = num(3);
            const here = activeWsOn(dropScreen);

            if (hoverWs !== "" && hoverWs !== String(here)) {
                // Onto another workspace: it goes there, you stay. A floating window keeps the
                // spot it had before the drag.
                finish(hoverWs, floatingAtStart ? startRect.x : null, startRect.y);
                phase = "genie";
                phaseTimer.interval = 460;
            } else if (hoverWs !== "") {
                // Onto the workspace you are on (e.g. after holding it there to switch): a floating
                // window goes back to its old spot, and it is brought here if it was left behind.
                finish(windowWs !== here && here > 0 ? String(here) : "", floatingAtStart ? startRect.x : null, startRect.y);
                phase = "home";
                phaseTimer.interval = 260;
            } else {
                // Anywhere on the screen. If the workspace changed during the drag and Hyprland did
                // not take the window along, bring it to the one you are on now.
                const moved = here > 0 && windowWs !== here;
                const dx = cursor.x - startCursor.x;
                const dy = cursor.y - startCursor.y;
                if (moved)
                    finish(String(here), floatingAtStart ? startRect.x + dx : null, startRect.y + dy);
                else
                    finish("", null, null);
                phase = "home";
                phaseTimer.interval = 260;
            }
            hoverWs = "";
            phaseTimer.restart();
        }
    }

    onHoverWsChanged: {
        if (carrying && hoverWs !== "" && hoverWs !== "empty" && hoverWs !== String(activeWsOn(screen)))
            springTimer.restart();
        else
            springTimer.stop();
    }

    Connections {
        function onRawEvent(event: HyprlandEvent): void {
            if (event.name === "custom" && event.data.startsWith("kairosdrag:"))
                root.handle(event.data);
        }

        target: Hyprland
    }

    // Holding the preview over a workspace switches to it, like spring-loaded folders.
    Timer {
        id: springTimer

        interval: 650
        onTriggered: {
            if (root.carrying && root.hoverWs !== "" && root.hoverWs !== "empty")
                Hypr.focusWorkspace(root.hoverWs);
        }
    }

    // If the preview frame does not arrive quickly, hide the real window anyway.
    Timer {
        id: hideFallback

        interval: 180
        onTriggered: root.hideReal()
    }

    Timer {
        id: phaseTimer

        onTriggered: {
            root.phase = "idle";
            root.toplevel = null;
            root.dropScreen = null;
        }
    }
}
