pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Caelestia
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
    // Clicking a window behind an open special workspace (music, communication, ...) hides it.
    property bool dismissSpecial: true
    // Super + drag shrinks the window to a preview, shows where it lands and lets it be dropped on
    // a workspace in the bar (services/WindowDrag.qml, modules/windowdrag).
    property bool dragPreview: true
    // Once: windows left invisible by an earlier version of the drag preview get their opacity back.
    property bool opacityHealed
    readonly property bool healOpacity: loaded && !opacityHealed

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
        applyRuntime();
    }

    // Gap kept free around floating windows: the one to the screen edge, plus the border.
    function edgeGap(): int {
        const num = v => {
            const n = parseInt(String(v ?? "").trim().split(/\s+/)[0]);
            return isNaN(n) ? undefined : n;
        };
        const gap = customGaps ? gapsOut : (num(Hypr.options["general:gaps_out"]) ?? 10);
        const border = customGaps ? borderSize : (num(Hypr.options["general:border_size"]) ?? 2);
        return gap + border;
    }

    // Lua only: the handlers that live in Hyprland's Lua state (gone after a config reload, so they
    // are set up again from onConfigReloaded):
    //   - KAIROS.fit(w, centre): keeps a floating window inside the free part of its monitor, i.e.
    //     inside the shell's frame and bar (the monitor's reserved area), the edge gap and room for
    //     the title bar. Too large windows shrink, windows sticking out are moved back in; with
    //     `centre` they are centred in that area.
    //   - New windows in floating mode are fitted and centred; windows that land on a special
    //     workspace (music, communication, ...) stay tiled there, like in tiling mode.
    //   - Focusing a floating window (keyboard, launcher, taskbar) raises it above the others.
    //   - While a special workspace is open on top, clicking a window behind it hides the special
    //     workspace and brings that window forward, instead of the click doing nothing.
    //   - Super + drag (dragPreview): Hyprland still moves the window, but the shell is told where
    //     the drag starts, goes and ends (socket2 events "custom>>kairosdrag:..."), hides the real
    //     window while it is carried and shows a preview instead (services/WindowDrag.qml).
    function applyRuntime(): void {
        if (!available || !loaded || !lua)
            return;
        luaEval(runtimeLua());
        if (!opacityHealed) {
            opacityHealed = true;
            save();
        }
    }

    function runtimeLua(): string {
        return `KAIROS = KAIROS or {}
        KAIROS.floating = ${floating}
        KAIROS.dismiss = ${dismissSpecial}
        KAIROS.gap = ${edgeGap()}
        KAIROS.bar = ${floating && titleBars && hasTitleBarPlugin ? 32 : 0}
        KAIROS.special = function(w)
            local ws = w.workspace
            return ws == nil or ws.special
        end
        KAIROS.area = function(m)
            local s = m.scale or 1
            if s <= 0 then s = 1 end
            local mw, mh = m.width / s, m.height / s
            if m.transform ~= nil and m.transform % 2 == 1 then mw, mh = mh, mw end
            local r = m.reserved or {}
            local g = KAIROS.gap
            local x = m.x + (r.left or 0) + g
            local y = m.y + (r.top or 0) + g + KAIROS.bar
            local w = mw - (r.left or 0) - (r.right or 0) - 2 * g
            local h = mh - (r.top or 0) - (r.bottom or 0) - 2 * g - KAIROS.bar
            return x, y, w, h
        end
        KAIROS.fit = function(w, centre)
            if w == nil or not w.floating or w.fullscreen ~= 0 or w.pinned or KAIROS.special(w) then return end
            local m = w.monitor
            if m == nil then return end
            local ax, ay, aw, ah = KAIROS.area(m)
            if aw < 200 or ah < 150 then return end
            local cw, ch = w.size.x, w.size.y
            local nw, nh = math.min(cw, math.floor(aw)), math.min(ch, math.floor(ah))
            if nw < cw or nh < ch then
                hl.dispatch(hl.dsp.window.resize({ window = w, x = nw, y = nh, relative = false }))
            end
            local x, y = w.at.x, w.at.y
            local out = x < ax or y < ay or x + nw > ax + aw or y + nh > ay + ah
            if centre or out then
                local nx, ny = math.floor(ax + (aw - nw) / 2), math.floor(ay + (ah - nh) / 2)
                if not centre then
                    nx = math.floor(math.max(ax, math.min(x, ax + aw - nw)))
                    ny = math.floor(math.max(ay, math.min(y, ay + ah - nh)))
                end
                hl.dispatch(hl.dsp.window.move({ window = w, x = nx, y = ny, relative = false }))
            end
        end
        KAIROS.tagged = function(w)
            for _, t in ipairs(w.tags or {}) do
                if t == "kairosfloat" or t == "kairosfloat*" then return true end
            end
            return false
        end
        KAIROS.opened = function(w)
            if not KAIROS.floating or w == nil then return end
            if KAIROS.special(w) then
                if w.floating and KAIROS.tagged(w) then
                    hl.dispatch(hl.dsp.window.float({ window = w, action = "disable" }))
                end
                return
            end
            if KAIROS.tagged(w) then KAIROS.fit(w, true) end
        end
        KAIROS.focused = function(w)
            if KAIROS.floating and w ~= nil and w.floating and not KAIROS.special(w) then
                hl.dispatch(hl.dsp.window.alter_zorder({ window = w, mode = "top" }))
            end
        end
        KAIROS.inside = function(w, p)
            return p.x >= w.at.x and p.y >= w.at.y and p.x < w.at.x + w.size.x and p.y < w.at.y + w.size.y
        end
        KAIROS.clicked = function()
            if not KAIROS.dismiss then return end
            local m = hl.get_monitor_at_cursor()
            if m == nil then return end
            local sp = hl.get_active_special_workspace(m)
            if sp == nil then return end
            local p = hl.get_cursor_pos()
            if p == nil then return end
            for _, w in ipairs(sp:get_windows()) do
                if KAIROS.inside(w, p) then return end
            end
            local ws = m.active_workspace
            if ws == nil then return end
            local hit = nil
            for _, w in ipairs(ws:get_windows()) do
                if KAIROS.inside(w, p) and (hit == nil or (w.floating and not hit.floating)) then hit = w end
            end
            if hit == nil then return end
            hl.dispatch(hl.dsp.workspace.toggle_special((sp.name:gsub("^special:?", ""))))
            hl.dispatch(hl.dsp.focus({ window = hit }))
            KAIROS.focused(hit)
        end
        KAIROS.emit = function(s)
            hl.dispatch(hl.dsp.event("kairosdrag:" .. s))
        end
        KAIROS.under = function()
            local p = hl.get_cursor_pos()
            local m = hl.get_monitor_at_cursor()
            if p == nil or m == nil then return nil end
            local pools = {}
            local sp = hl.get_active_special_workspace(m)
            if sp ~= nil then pools[#pools + 1] = sp end
            if m.active_workspace ~= nil then pools[#pools + 1] = m.active_workspace end
            local a = hl.get_active_window()
            for _, ws in ipairs(pools) do
                local best = nil
                for _, w in ipairs(ws:get_windows()) do
                    if KAIROS.inside(w, p) then
                        if a ~= nil and w.address == a.address then return w end
                        if best == nil or (w.floating and not best.floating) then best = w end
                    end
                end
                if best ~= nil then return best end
            end
            return nil
        end
        KAIROS.hide = function(addr)
            KAIROS.hidden = addr
            hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity", value = "0", window = "address:" .. addr }))
        end
        KAIROS.show = function(addr)
            if KAIROS.hidden == addr then KAIROS.hidden = nil end
            hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity", value = "1", window = "address:" .. addr }))
        end
        KAIROS.dragStart = function(w)
            if w == nil or w.fullscreen ~= 0 then return end
            local p = hl.get_cursor_pos()
            if p == nil then return end
            local ws = w.workspace
            local x, y = math.floor(p.x), math.floor(p.y)
            KAIROS.drag = { on = true, addr = w.address, lx = x, ly = y, ticks = 0 }
            KAIROS.emit(string.format("start,%s,%d,%d,%d,%d,%d,%d,%d,%d", w.address, w.floating and 1 or 0,
                math.floor(w.at.x), math.floor(w.at.y), math.floor(w.size.x), math.floor(w.size.y), x, y,
                ws ~= nil and math.floor(ws.id) or 0))
            if KAIROS.dragTimer == nil then
                KAIROS.dragTimer = hl.timer(function() pcall(KAIROS.dragTick) end, { timeout = 16, type = "repeat" })
            else
                KAIROS.dragTimer:set_enabled(true)
            end
        end
        KAIROS.dragTick = function()
            local d = KAIROS.drag
            if d == nil or not d.on then
                if KAIROS.dragTimer ~= nil then KAIROS.dragTimer:set_enabled(false) end
                return
            end
            d.ticks = d.ticks + 1
            if d.ticks > 3750 then KAIROS.dragEnd() return end
            local p = hl.get_cursor_pos()
            if p == nil then return end
            local x, y = math.floor(p.x), math.floor(p.y)
            if x ~= d.lx or y ~= d.ly then
                d.lx, d.ly = x, y
                KAIROS.emit("move," .. x .. "," .. y)
            end
        end
        KAIROS.dragEnd = function()
            local d = KAIROS.drag
            if d == nil or not d.on then return end
            d.on = false
            if KAIROS.dragTimer ~= nil then KAIROS.dragTimer:set_enabled(false) end
            local p = hl.get_cursor_pos() or { x = d.lx, y = d.ly }
            local w = hl.get_window("address:" .. d.addr)
            local wsid = 0
            if w ~= nil and w.workspace ~= nil then wsid = math.floor(w.workspace.id) end
            KAIROS.emit(string.format("end,%d,%d,%d", math.floor(p.x), math.floor(p.y), wsid))
            local addr = d.addr
            hl.timer(function() if KAIROS.hidden == addr then pcall(KAIROS.show, addr) end end, { timeout = 1500, type = "oneshot" })
        end
        KAIROS.dragFinish = function(addr, ws, x, y)
            local sel = "address:" .. addr
            if x ~= nil then hl.dispatch(hl.dsp.window.move({ window = sel, x = x, y = y, relative = false })) end
            if ws ~= nil and ws ~= "" then hl.dispatch(hl.dsp.window.move({ window = sel, workspace = ws, follow = false })) end
            KAIROS.show(addr)
        end
        KAIROS.dragBind = KAIROS.dragBind or function()
            local before = nil
            if not (KAIROS.drag ~= nil and KAIROS.drag.on) then
                local ok, w = pcall(KAIROS.under)
                if ok then before = w end
            end
            local r = hl.dispatch(hl.dsp.window.drag())
            if KAIROS.drag ~= nil and KAIROS.drag.on then
                pcall(KAIROS.dragEnd)
            elseif before ~= nil then
                pcall(KAIROS.dragStart, before)
            end
            return r
        end
        KAIROS.dragWanted = ${dragPreview}
        if KAIROS.dragWanted and not KAIROS.dragBound then
            pcall(hl.unbind, "SUPER + mouse:272")
            pcall(hl.bind, "SUPER + mouse:272", KAIROS.dragBind, { mouse = true })
            KAIROS.dragBound = true
        elseif not KAIROS.dragWanted and KAIROS.dragBound then
            pcall(hl.unbind, "SUPER + mouse:272")
            pcall(hl.bind, "SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
            KAIROS.dragBound = false
        end
        if ${healOpacity} and KAIROS.healed == nil then
            KAIROS.healed = true
            for _, w in ipairs(hl.get_windows()) do
                pcall(hl.dispatch, hl.dsp.window.set_prop({ prop = "opacity", value = "1", window = w }))
            end
        end
        if KAIROS.hooked == nil then
            KAIROS.hooked = true
            pcall(hl.bind, "mouse:272", function()
                hl.timer(function() if KAIROS.drag ~= nil and KAIROS.drag.on then pcall(KAIROS.dragEnd) end end, { timeout = 80, type = "oneshot" })
            end, { release = true, non_consuming = true, ignore_mods = true })
            pcall(hl.on, "window.open", function(w) pcall(KAIROS.opened, w) end)
            pcall(hl.on, "window.active", function(w) pcall(KAIROS.focused, w) end)
            pcall(hl.bind, "mouse:272", function() pcall(KAIROS.clicked) end, { non_consuming = true })
        end`;
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
            // Windows on special workspaces (music, communication, ...) keep their tiled overlay.
            // The handlers go first in the same eval: separate messages are not guaranteed to
            // arrive in order.
            luaEval(runtimeLua() + `
            if KAIROS_FLOAT == nil then
                pcall(function() KAIROS_FLOAT = hl.window_rule({ name = "kairos-float", match = { class = ".*", modal = false, workspace = "s[false]" }, float = true, center = true, tag = "+kairosfloat" }) end)
            end
            if KAIROS_FLOAT ~= nil then KAIROS_FLOAT:set_enabled(true) end
            for _, w in ipairs(hl.get_windows()) do
                if not KAIROS.special(w) and not w.floating and w.fullscreen == 0 then
                    hl.dispatch(hl.dsp.window.tag({ tag = "+kairosfloat", window = w }))
                    hl.dispatch(hl.dsp.window.float({ window = w, action = "enable" }))
                    pcall(KAIROS.fit, w, true)
                elseif KAIROS.special(w) and w.floating and KAIROS.tagged(w) then
                    hl.dispatch(hl.dsp.window.float({ window = w, action = "disable" }))
                elseif w.floating and not w.pinned then
                    pcall(KAIROS.fit, w, false)
                end
            end`);
        } else {
            const msgs = [];
            const next = floated.slice();
            for (const t of Hypr.toplevels.values) {
                const ipc = t.lastIpcObject;
                if (!ipc?.address || ipc.floating || (ipc.fullscreen ?? 0) !== 0 || String(ipc.workspace?.name ?? "").startsWith("special"))
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

    // Moves floating windows back inside the free area, e.g. after the shell frame got thicker.
    function refit(): void {
        if (!available || !loaded || !lua || !floating)
            return;
        luaEval(runtimeLua() + `
        for _, w in ipairs(hl.get_windows()) do
            if w.floating then pcall(KAIROS.fit, w, false) end
        end`);
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

    // The frame and bar take part of the screen (Hyprland's reserved area); keep windows clear of it.
    Connections {
        function onThicknessChanged(): void {
            refitTimer.restart();
        }

        target: Config.border
        ignoreUnknownSignals: true
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
            const fields = event.data.split(",");
            // Apps on special workspaces (music, communication, ...) stay tiled there.
            if ((fields[1] ?? "").startsWith("special"))
                return;
            const address = "0x" + fields[0];
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
        id: refitTimer

        interval: 700
        onTriggered: root.refit()
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
                dismissSpecial: root.dismissSpecial,
                dragPreview: root.dragPreview,
                opacityHealed: root.opacityHealed,
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
                root.dismissSpecial = c.dismissSpecial !== false;
                root.dragPreview = c.dragPreview !== false;
                root.opacityHealed = c.opacityHealed === true;
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
