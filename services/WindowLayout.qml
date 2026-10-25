pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Caelestia.Config
import Caelestia.I18n
import qs.utils

// How windows behave, changed live from the shell (settings app, utilities popup, IPC):
//
//   - Tiling (Hyprland's own layout) or floating (Windows / macOS style): in floating mode every
//     window floats, opens centred, snaps to screen edges and other windows, can be resized from
//     its edges, and gets a Material You title bar with close / maximise / minimise when the
//     hyprbars plugin is installed (see the Plugins page). Going back to tiling tiles exactly the
//     windows that floating mode floated (they carry the tag "kairosfloat"); windows that were
//     floating before stay floating.
//   - Gaps between windows, gap to the screen edge, window border width and corner rounding.
//
// These are runtime overrides on top of the Hyprland config: they are kept in
// ~/.local/state/caelestia/windows.json and applied again on shell start and after every Hyprland
// config reload. Works with Lua configs (hyprctl eval) and with hyprlang (keyword / dispatch).
// Bind a key with: caelestia shell windowMode toggle   (or: qs ipc call windowMode toggle)
Singleton {
    id: root

    readonly property bool available: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") !== ""
    readonly property bool lua: Hypr.usingLua

    // "tiling" or "floating"
    property string mode: "tiling"
    readonly property bool floating: mode === "floating"
    property bool titleBars: true
    property bool buttonsLeft: false
    property bool snap: true
    property bool resizeOnEdges: true

    // Gaps and borders; only applied while `customGaps` is on, otherwise the Hyprland config rules.
    property bool customGaps: false
    property int gapsIn: 5
    property int gapsOut: 10
    property int borderSize: 2
    property int rounding: 10

    property bool loaded
    // The "floating" quick toggle was added to the utilities popup once; never again after that,
    // so removing it in the settings sticks.
    property bool toggleOffered
    // Whether the hyprbars plugin is loaded in Hyprland (for the settings page).
    readonly property bool hasTitleBarPlugin: HyprPlugins.hyprbarsLoaded
    // hyprlang only: windows floated by floating mode, by address.
    property var floated: []

    function setMode(next: string): void {
        if (next !== "tiling" && next !== "floating")
            return;
        if (next === mode)
            return;
        mode = next;
        save();
        if (floating) {
            applyFloating();
            Toaster.toast(Tr.tr("Floating windows"), Tr.tr("Windows float, open centred and snap to edges"), "select_window");
        } else {
            leaveFloating();
            Toaster.toast(Tr.tr("Tiling windows"), Tr.tr("Windows are tiled by Hyprland again"), "grid_view");
        }
    }

    function toggle(): void {
        setMode(floating ? "tiling" : "floating");
    }

    function setOption(key: string, value: var): void {
        if (root[key] === value)
            return;
        root[key] = value;
        save();
        applyTimer.restart();
    }

    // Takes the values Hyprland uses right now as the starting point for custom gaps.
    function adoptCurrent(): void {
        const o = Hypr.options;
        const num = v => {
            const n = parseInt(String(v ?? "").split(" ")[0]);
            return isNaN(n) ? undefined : n;
        };
        gapsIn = num(o["general:gaps_in"]) ?? gapsIn;
        gapsOut = num(o["general:gaps_out"]) ?? gapsOut;
        borderSize = num(o["general:border_size"]) ?? borderSize;
        rounding = num(o["decoration:rounding"]) ?? rounding;
    }

    function setCustomGaps(on: bool): void {
        if (on === customGaps)
            return;
        if (on)
            adoptCurrent();
        customGaps = on;
        save();
        if (on)
            applyTimer.restart();
        else
            reloadHyprland();
    }

    function hex(c: color): string {
        const h = v => {
            const s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16);
            return s.length < 2 ? "0" + s : s;
        };
        return h(c.r) + h(c.g) + h(c.b);
    }

    function luaEval(code: string): void {
        Hypr.extras.message("eval " + code.replace(/\s*\n\s*/g, " "));
    }

    // Everything except entering/leaving floating mode's window handling.
    function applyOptions(): void {
        if (!available || !loaded)
            return;
        const opts = {};
        if (customGaps) {
            opts["general:gaps_in"] = gapsIn;
            opts["general:gaps_out"] = gapsOut;
            opts["general:border_size"] = borderSize;
            opts["decoration:rounding"] = rounding;
        }
        if (floating) {
            opts["general:snap:enabled"] = snap;
            opts["general:snap:respect_gaps"] = true;
            opts["general:resize_on_border"] = resizeOnEdges;
        }
        if (Object.keys(opts).length > 0)
            Hypr.extras.applyOptions(opts);
        applyTitleBars();
    }

    function applyTitleBars(): void {
        if (!available || !loaded || !lua)
            return;
        const p = Colours.palette;
        const on = floating && titleBars;
        const font = Tokens.font.body.medium.family;
        // Buttons are added once per Hyprland config (they cannot be removed again), right to left.
        luaEval(`if hl.plugin ~= nil and hl.plugin.hyprbars ~= nil then
            pcall(hl.config, { plugin = { hyprbars = {
                enabled = ${on},
                bar_height = 32,
                bar_color = "rgba(${hex(p.m3surfaceContainer)}f2)",
                ["col.text"] = "rgb(${hex(p.m3onSurface)})",
                bar_text_font = "${font.replace(/"/g, "")}",
                bar_text_size = 11,
                bar_text_weight = "medium",
                bar_text_align = "${buttonsLeft ? "center" : "left"}",
                bar_buttons_alignment = "${buttonsLeft ? "left" : "right"}",
                bar_padding = 14,
                bar_button_padding = 8,
                bar_blur = true,
                bar_part_of_window = true,
                bar_precedence_over_border = true,
                icon_on_hover = ${buttonsLeft},
                inactive_button_color = "rgb(${hex(p.m3outlineVariant)})",
                on_double_click = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']]
            } } })
            if KAIROS_BARS == nil then
                hl.plugin.hyprbars.add_button({ bg_color = "rgb(${hex(p.m3error)})", fg_color = "rgb(${hex(p.m3onError)})", size = 14, icon = "×", action = [[hyprctl dispatch 'hl.dsp.window.close()']] })
                hl.plugin.hyprbars.add_button({ bg_color = "rgb(${hex(p.m3tertiary)})", fg_color = "rgb(${hex(p.m3onTertiary)})", size = 14, icon = "+", action = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']] })
                hl.plugin.hyprbars.add_button({ bg_color = "rgb(${hex(p.m3secondary)})", fg_color = "rgb(${hex(p.m3onSecondary)})", size = 14, icon = "−", action = [[hyprctl dispatch 'hl.dsp.window.move({ workspace = "special:minimized" })']] })
                KAIROS_BARS = true
            end
        end
        if hl.window_rule ~= nil and KAIROS_NOBAR == nil then
            pcall(function() KAIROS_NOBAR = hl.window_rule({ name = "kairos-nobar-tiled", match = { float = false }, ["hyprbars:no_bar"] = true }) end)
        end`);
    }

    function applyFloating(): void {
        if (!available || !loaded)
            return;
        applyOptions();
        if (lua) {
            luaEval(`if KAIROS_FLOAT == nil then
                pcall(function() KAIROS_FLOAT = hl.window_rule({ name = "kairos-float", match = { class = ".*", modal = false }, float = true, center = true, tag = "+kairosfloat" }) end)
            end
            if KAIROS_FLOAT ~= nil then KAIROS_FLOAT:set_enabled(true) end
            for _, w in ipairs(hl.get_windows()) do
                if not w.floating and w.fullscreen == 0 then
                    hl.dispatch(hl.dsp.window.tag({ tag = "+kairosfloat", window = w }))
                    hl.dispatch(hl.dsp.window.float({ window = w, action = "enable" }))
                    hl.dispatch(hl.dsp.window.center({ window = w }))
                end
            end`);
        } else {
            const msgs = [];
            const next = floated.slice();
            for (const t of Hypr.toplevels.values) {
                const ipc = t.lastIpcObject;
                if (!ipc?.address || ipc.floating || (ipc.fullscreen ?? 0) !== 0)
                    continue;
                msgs.push(`dispatch setfloating address:${ipc.address}`);
                next.push(ipc.address);
            }
            floated = next;
            if (msgs.length > 0)
                Hypr.extras.batchMessage(msgs);
        }
    }

    function leaveFloating(): void {
        if (!available || !loaded)
            return;
        if (lua) {
            luaEval(`for _, w in ipairs(hl.get_windows({ tag = "kairosfloat" })) do
                if w.floating then
                    hl.dispatch(hl.dsp.window.float({ window = w, action = "disable" }))
                end
                hl.dispatch(hl.dsp.window.tag({ tag = "-kairosfloat", window = w }))
            end
            if KAIROS_FLOAT ~= nil then KAIROS_FLOAT:set_enabled(false) end`);
        } else {
            const msgs = floated.map(a => `dispatch settiled address:${a}`);
            floated = [];
            if (msgs.length > 0)
                Hypr.extras.batchMessage(msgs);
        }
        // Snapping, edge resizing and title bars go back to what the Hyprland config says;
        // custom gaps are applied again after the reload.
        reloadTimer.restart();
    }

    function reloadHyprland(): void {
        Hypr.extras.message("reload");
    }

    function save(): void {
        saveTimer.restart();
    }

    function offerQuickToggle(): void {
        if (toggleOffered)
            return;
        toggleOffered = true;
        save();
        const list = GlobalConfig.utilities.quickToggles;
        for (let i = 0; i < list.count; i++)
            if (list.at(i).id === "floating")
                return;
        list.insert({
            id: "floating",
            enabled: true
        });
    }

    // Title bar colours follow the wallpaper.
    Connections {
        function onPaletteChanged(): void {
            if (root.floating && root.titleBars)
                colourTimer.restart();
        }

        target: Colours
        ignoreUnknownSignals: true
    }

    Connections {
        function onConfigReloaded(): void {
            // A reload drops the Lua state (rules, buttons) and runtime options.
            if (root.floating)
                root.applyFloating();
            else
                root.applyOptions();
            HyprPlugins.refresh();
        }

        target: Hypr
    }

    // Title bars as soon as hyprbars is installed and loaded.
    Connections {
        function onHyprbarsLoadedChanged(): void {
            if (HyprPlugins.hyprbarsLoaded)
                root.applyTitleBars();
        }

        target: HyprPlugins
    }

    // hyprlang: new windows float while floating mode is on.
    Connections {
        function onRawEvent(event: HyprlandEvent): void {
            if (root.lua || !root.floating || event.name !== "openwindow")
                return;
            const address = "0x" + event.data.split(",")[0];
            root.floated = root.floated.concat([address]);
            Hypr.extras.message(`dispatch setfloating address:${address}`);
        }

        target: Hyprland
    }

    Timer {
        id: applyTimer

        interval: 120
        onTriggered: root.applyOptions()
    }

    Timer {
        id: colourTimer

        interval: 600
        onTriggered: root.applyTitleBars()
    }

    Timer {
        id: reloadTimer

        interval: 150
        onTriggered: root.reloadHyprland()
    }

    Timer {
        id: saveTimer

        interval: 400
        onTriggered: file.setText(JSON.stringify({
                mode: root.mode,
                titleBars: root.titleBars,
                buttonsLeft: root.buttonsLeft,
                snap: root.snap,
                resizeOnEdges: root.resizeOnEdges,
                customGaps: root.customGaps,
                gapsIn: root.gapsIn,
                gapsOut: root.gapsOut,
                borderSize: root.borderSize,
                rounding: root.rounding,
                toggleOffered: root.toggleOffered
            }))
    }

    FileView {
        id: file

        printErrors: false
        path: `${Paths.state}/windows.json`
        onLoaded: {
            try {
                const c = JSON.parse(text());
                const int = (v, lo, hi, d) => typeof v === "number" ? Math.max(lo, Math.min(hi, Math.round(v))) : d;
                root.mode = c.mode === "floating" ? "floating" : "tiling";
                root.titleBars = c.titleBars !== false;
                root.buttonsLeft = c.buttonsLeft === true;
                root.snap = c.snap !== false;
                root.resizeOnEdges = c.resizeOnEdges !== false;
                root.customGaps = c.customGaps === true;
                root.gapsIn = int(c.gapsIn, 0, 60, root.gapsIn);
                root.gapsOut = int(c.gapsOut, 0, 80, root.gapsOut);
                root.borderSize = int(c.borderSize, 0, 12, root.borderSize);
                root.rounding = int(c.rounding, 0, 40, root.rounding);
                root.toggleOffered = c.toggleOffered === true;
            } catch (error) {
                console.warn("WindowLayout: could not parse windows.json:", error);
            }
            root.loaded = true;
            startTimer.restart();
        }
        onLoadFailed: err => {
            root.loaded = true;
            if (err === FileViewError.FileNotFound)
                root.save();
        }
    }

    // Give Hyprland's IPC a moment after the shell starts.
    Timer {
        id: startTimer

        interval: 800
        onTriggered: {
            if (root.floating)
                root.applyFloating();
            else
                root.applyOptions();
            HyprPlugins.refresh();
            root.offerQuickToggle();
        }
    }

    IpcHandler {
        function toggle(): void {
            root.toggle();
        }

        function setMode(mode: string): void {
            root.setMode(mode);
        }

        function getMode(): string {
            return root.mode;
        }

        target: "windowMode"
    }
}
