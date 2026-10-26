pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.I18n
import qs.utils

// Home Assistant connection for the dashboard "Home" tab.
//
// Credentials are typed into the panel by the user and stored in the system
// keyring through `secret-tool` (package: libsecret). Nothing secret is ever
// written to the config or the repository. The list of devices shown in the
// panel (entity ids only) is kept in ~/.local/state/caelestia/homeassistant.json.
Singleton {
    id: root

    // "loading" | "unconfigured" | "connecting" | "connected" | "error"
    property string status: "loading"
    property string errorText
    property string url
    property string token

    readonly property bool connected: status === "connected"

    // All entities from /api/states (trimmed), sorted by name.
    property list<var> entities: []
    // entity_id -> entity, rebuilt on every refresh.
    property var byId: ({})
    // Tiles the user placed, in display order: [{ id, w, h }].
    // w: 1-8 grid columns, h: 1-3 grid rows. The grid packs them densely.
    readonly property int columns: 8
    property var tiles: []
    readonly property list<string> selected: tiles.map(t => t.id)
    // Which default tile shapes have been applied to saved tiles (see arrange()).
    property int shapesVersion: 1

    // Doors, locks and alarms: hidden in the editor unless explicitly shown, and need a confirmation tap.
    readonly property list<string> sensitiveDomains: ["cover", "lock", "alarm_control_panel", "valve", "siren"]
    // Domains that flip on/off with the generic toggle service.
    readonly property list<string> toggleDomains: ["light", "switch", "fan", "input_boolean", "automation", "media_player", "humidifier", "siren"]
    // Domains that are "run" instead of toggled.
    readonly property var runServices: ({
            scene: "turn_on",
            script: "turn_on",
            button: "press",
            input_button: "press"
        })

    // Which gallery category an entity type belongs to. Anything not listed ends up in "other".
    readonly property var categoryByDomain: ({
            light: "light",
            switch: "switch",
            input_boolean: "switch",
            climate: "climate",
            fan: "climate",
            humidifier: "climate",
            cover: "cover",
            valve: "cover",
            media_player: "media",
            scene: "scene",
            script: "scene",
            automation: "automation",
            button: "automation",
            input_button: "automation",
            sensor: "sensor",
            binary_sensor: "sensor",
            person: "person",
            lock: "security",
            alarm_control_panel: "security",
            siren: "security"
        })

    // Values handed to the keyring helper processes (kept out of the command line).
    property string pendingValue

    function domainOf(entityId: string): string {
        return entityId.split(".")[0];
    }

    function isSensitive(entityId: string): bool {
        const e = byId[entityId];
        const dc = e?.attributes?.device_class ?? "";
        // Blinds and shades are harmless; garage doors, doors and gates are not.
        if (domainOf(entityId) === "cover")
            return ["garage", "door", "gate"].includes(dc);
        return sensitiveDomains.includes(domainOf(entityId)) || dc === "garage" || dc === "door";
    }

    function isActionable(entityId: string): bool {
        const d = domainOf(entityId);
        return toggleDomains.includes(d) || d in runServices || d === "cover" || d === "lock";
    }

    function isOn(entityId: string): bool {
        const s = byId[entityId]?.state;
        return s === "on" || s === "open" || s === "opening" || s === "unlocked" || s === "playing" || s === "home";
    }

    function isSelected(entityId: string): bool {
        return selected.includes(entityId);
    }

    // Gallery category of an entity. Doors, locks and alarms are kept in their own one because the gallery hides it by default.
    function categoryOf(entityId: string): string {
        if (isSensitive(entityId))
            return "security";
        return categoryByDomain[domainOf(entityId)] ?? "other";
    }

    // Material Symbols icon for an entity; `on` picks the open/closed style where there is one.
    function iconOf(entityId: string, on: bool): string {
        const dc = byId[entityId]?.attributes?.device_class ?? "";
        switch (domainOf(entityId)) {
        case "light":
            return "lightbulb";
        case "switch":
        case "input_boolean":
            return "toggle_on";
        case "fan":
            return "mode_fan";
        case "climate":
            return "thermostat";
        case "media_player":
            return "speaker";
        case "scene":
            return "palette";
        case "script":
            return "play_arrow";
        case "automation":
            return "smart_toy";
        case "button":
        case "input_button":
            return "radio_button_checked";
        case "lock":
            return on ? "lock_open" : "lock";
        case "cover":
            return dc === "garage" ? "garage" : dc === "door" || dc === "gate" ? "door_front" : "blinds";
        case "person":
            return "person";
        case "binary_sensor":
            if (dc === "door" || dc === "garage_door" || dc === "window")
                return dc === "window" ? "window" : "door_front";
            if (dc === "motion" || dc === "occupancy" || dc === "presence")
                return on ? "directions_run" : "accessibility_new";
            return "sensors";
        case "sensor":
            if (dc === "temperature")
                return "thermostat";
            if (dc === "humidity")
                return "humidity_percentage";
            if (dc === "battery")
                return "battery_full";
            if (dc === "power" || dc === "energy")
                return "bolt";
            return "sensors";
        default:
            return "home";
        }
    }

    function setSelected(entityId: string, on: bool): void {
        const next = tiles.filter(t => t.id !== entityId);
        if (on) {
            const shape = shapeFor(entityId);
            next.push({
                id: entityId,
                w: shape.w,
                h: shape.h
            });
        }
        setTiles(next);
    }

    // The tile shape that fits what a device does (cells of the 8-column grid). The shape follows
    // the control: the axis a slider moves along is the tile's long side, and how much space a tile
    // gets follows how much it has to show.
    //   1×2 tall      dimmable lights, blinds  - vertical slider; up is brighter / more open,
    //                                            like the blind itself moves
    //   4×1 wide      fan speed                - horizontal slider, a dial turned flat
    //   1×1 square    plain switches, people   - one tap, nothing to adjust; the whole tile is
    //                                            the button
    //   2×1 pill      scenes, scripts, sensors - a name and a word or a value to read; doors and
    //                 locks                      locks need the room for "Tap again to confirm"
    //   2×2 square    thermostats, humidifiers - target value with − / + and the mode
    //   4×2 card      media players            - title, artist, playback and volume
    function shapeFor(entityId: string): var {
        const d = domainOf(entityId);
        const f = features(entityId);
        const shape = (w, h) => ({
                w,
                h
            });
        if (f.media)
            return shape(4, 2);
        if (f.climate || d === "humidifier")
            return shape(2, 2);
        if (f.brightness || (f.position && !isSensitive(entityId)))
            return shape(1, 2);
        if (f.fanSpeed)
            return shape(4, 1);
        if (d === "person")
            return shape(1, 1);
        if (d === "sensor" || d === "binary_sensor" || d in runServices || isSensitive(entityId))
            return shape(2, 1);
        if (toggleDomains.includes(d))
            return shape(1, 1);
        return shape(2, 1);
    }

    // Gives every tile its default shape. With `reorder`, bigger tiles go first so the grid packs
    // without holes: rich cards on top, quick toggles filling in underneath (same-sized tiles keep
    // their order).
    function arrange(reorder: bool): void {
        const next = tiles.map((t, i) => {
            const shape = byId[t.id] ? shapeFor(t.id) : {
                w: t.w,
                h: t.h
            };
            return {
                id: t.id,
                w: shape.w,
                h: shape.h,
                i
            };
        });
        if (reorder)
            next.sort((a, b) => (b.w * b.h - a.w * a.h) || (b.h - a.h) || (a.i - b.i));
        setTiles(next.map(t => ({
                    id: t.id,
                    w: t.w,
                    h: t.h
                })));
    }

    function setTiles(next: var): void {
        tiles = next;
        settingsSaveTimer.restart();
    }

    function resizeTile(entityId: string, w: int, h: int): void {
        setTiles(tiles.map(t => t.id === entityId ? {
                id: t.id,
                w: Math.max(1, Math.min(columns, w)),
                h: Math.max(1, Math.min(3, h))
            } : t));
    }

    function moveTile(from: int, to: int): void {
        if (from === to || from < 0 || to < 0 || from >= tiles.length || to >= tiles.length)
            return;
        const next = tiles.slice();
        const [t] = next.splice(from, 1);
        next.splice(to, 0, t);
        setTiles(next);
    }

    // What a device can do, from its attributes. Used to pick tile controls.
    function features(entityId: string): var {
        const e = byId[entityId];
        const a = e?.attributes ?? {};
        const d = domainOf(entityId);
        const modes = a.supported_color_modes ?? [];
        const colourModes = ["hs", "xy", "rgb", "rgbw", "rgbww"];
        return {
            brightness: d === "light" && modes.some(m => m !== "onoff"),
            colour: d === "light" && modes.some(m => colourModes.includes(m)),
            colourTemp: d === "light" && modes.includes("color_temp"),
            position: d === "cover" && a.current_position !== undefined,
            tilt: d === "cover" && a.current_tilt_position !== undefined,
            climate: d === "climate",
            media: d === "media_player",
            volume: d === "media_player" && a.volume_level !== undefined,
            fanSpeed: d === "fan" && a.percentage !== undefined,
            value: d === "sensor" || d === "binary_sensor" || d === "person"
        };
    }

    // Generic service call with an optional optimistic state/attribute patch.
    function call(domain: string, service: string, data: var, patch: var): void {
        if (patch && byId[data.entity_id]) {
            const copy = Object.assign({}, byId[data.entity_id]);
            if (patch.state !== undefined)
                copy.state = patch.state;
            copy.attributes = Object.assign({}, copy.attributes, patch.attributes ?? {});
            const map = Object.assign({}, byId);
            map[data.entity_id] = copy;
            byId = map;
        }
        request("POST", url, token, `/api/services/${domain}/${service}`, data, () => refreshSoon.restart());
    }

    // For sliders: only the latest value is sent, at most every 250 ms.
    property var pendingCall: null

    function callThrottled(domain: string, service: string, data: var, patch: var): void {
        if (!throttle.running) {
            call(domain, service, data, patch);
            throttle.start();
        } else {
            pendingCall = {
                domain,
                service,
                data,
                patch
            };
        }
    }

    // Perform the natural action for an entity (toggle, run, open/close, lock/unlock).
    function activate(entityId: string): void {
        const d = domainOf(entityId);
        let service;
        if (toggleDomains.includes(d))
            service = "toggle";
        else if (d in runServices)
            service = runServices[d];
        else if (d === "cover")
            service = isOn(entityId) ? "close_cover" : "open_cover";
        else if (d === "lock")
            service = isOn(entityId) ? "lock" : "unlock";
        else
            return;

        // Optimistic UI: flip the state immediately, then confirm with a refresh.
        if (service === "toggle" && byId[entityId]) {
            const copy = Object.assign({}, byId[entityId]);
            copy.state = isOn(entityId) ? "off" : "on";
            const map = Object.assign({}, byId);
            map[entityId] = copy;
            byId = map;
        }

        request("POST", url, token, `/api/services/${d}/${service}`, {
            entity_id: entityId
        }, () => refreshSoon.restart());
    }

    function normaliseUrl(input: string): string {
        let u = input.trim();
        if (u === "")
            return "";
        if (!/^https?:\/\//i.test(u))
            u = "http://" + u;
        return u.replace(/\/+$/, "");
    }

    // Test the credentials first; only a working pair is saved to the keyring.
    function connect(rawUrl: string, rawToken: string): void {
        const u = normaliseUrl(rawUrl);
        const t = rawToken.trim();
        if (u === "" || t === "") {
            status = "error";
            errorText = Tr.tr("Enter both the address and the token.");
            return;
        }

        status = "connecting";
        errorText = "";

        request("GET", u, t, "/api/", null, (code, body) => {
            if (code === 200) {
                url = u;
                token = t;
                status = "connected";
                save();
                refresh();
            } else if (code === 401) {
                status = "error";
                errorText = Tr.tr("The token was rejected (401). Create a new long-lived token.");
            } else if (code === 0) {
                status = "error";
                errorText = Tr.tr("Could not reach Home Assistant. Check the address and that it is online.");
            } else {
                status = "error";
                errorText = Tr.tr("Unexpected answer from Home Assistant (HTTP %1).").arg(code);
            }
        });
    }

    function refresh(): void {
        if (!connected)
            return;

        request("GET", url, token, "/api/states", null, (code, body) => {
            if (code !== 200)
                return;
            try {
                const list = JSON.parse(body).map(e => {
                    const a = Object.assign({}, e.attributes ?? {});
                    a.friendly_name = a.friendly_name ?? e.entity_id;
                    a.unit_of_measurement = a.unit_of_measurement ?? "";
                    a.device_class = a.device_class ?? "";
                    a.brightness = a.brightness ?? null;
                    delete a.entity_picture; // can carry access tokens, never needed here
                    return {
                        entity_id: e.entity_id,
                        state: e.state,
                        last_changed: e.last_changed,
                        attributes: a
                    };
                });
                list.sort((a, b) => a.attributes.friendly_name.localeCompare(b.attributes.friendly_name));
                const map = {};
                for (const e of list)
                    map[e.entity_id] = e;
                entities = list;
                byId = map;
                // Tiles from before the shapes existed were all 2×1: shape them once.
                if (root.shapesVersion < 1) {
                    if (root.tiles.length > 0 && root.tiles.every(t => t.w === 2 && t.h === 1))
                        root.arrange(true);
                    root.shapesVersion = 1;
                    settingsSaveTimer.restart();
                }
            } catch (error) {
                console.warn("HomeAssistant: could not parse states:", error);
            }
        });
    }

    // Remove the stored credentials and return to the setup form.
    function forget(): void {
        clearUrl.running = true;
        clearToken.running = true;
        url = "";
        token = "";
        entities = [];
        byId = {};
        status = "unconfigured";
        errorText = "";
    }

    // Small XHR wrapper. callback(httpStatus, responseText); status 0 means "no connection".
    function request(method: string, baseUrl: string, bearer: string, path: string, body: var, callback: var): void {
        const xhr = new XMLHttpRequest();
        xhr.open(method, baseUrl + path);
        xhr.setRequestHeader("Authorization", "Bearer " + bearer);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.timeout = 8000;
        xhr.onreadystatechange = () => {
            if (xhr.readyState === XMLHttpRequest.DONE)
                callback(xhr.status, xhr.responseText);
        };
        xhr.ontimeout = () => callback(0, "");
        xhr.send(body === null ? undefined : JSON.stringify(body));
    }

    function save(): void {
        pendingValue = url;
        saveUrl.running = true;
    }

    // Load saved credentials on shell start, then verify them.
    Component.onCompleted: lookupUrl.running = true

    // Keep states fresh while connected.
    Timer {
        running: root.connected
        repeat: true
        interval: 10000
        onTriggered: root.refresh()
    }

    Timer {
        id: refreshSoon

        interval: 400
        onTriggered: root.refresh()
    }

    Timer {
        id: throttle

        interval: 250
        onTriggered: {
            // Send the latest value that arrived while waiting.
            if (root.pendingCall) {
                const c = root.pendingCall;
                root.pendingCall = null;
                root.call(c.domain, c.service, c.data, c.patch);
                start();
            }
        }
    }

    Timer {
        id: settingsSaveTimer

        interval: 500
        onTriggered: settings.setText(JSON.stringify({
                tiles: root.tiles,
                shapes: root.shapesVersion
            }))
    }

    FileView {
        id: settings

        printErrors: false
        path: `${Paths.state}/homeassistant.json`
        onLoaded: {
            try {
                const c = JSON.parse(text());
                root.shapesVersion = typeof c.shapes === "number" ? c.shapes : 0;
                if (c.tiles)
                    root.tiles = c.tiles;
                else if (c.selected) // older format: plain list of ids
                    root.tiles = c.selected.map(id => ({
                                id,
                                w: 2,
                                h: 1
                            }));
            } catch (error) {
                console.warn("HomeAssistant: could not parse settings:", error);
            }
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => setText(JSON.stringify({
                        tiles: [],
                        shapes: 1
                    })));
        }
    }

    Process {
        id: lookupUrl

        command: ["secret-tool", "lookup", "service", "kairos-homeassistant", "account", "url"]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = text.trim();
                if (value === "")
                    root.status = "unconfigured";
                else {
                    root.url = value;
                    lookupToken.running = true;
                }
            }
        }
    }

    Process {
        id: lookupToken

        command: ["secret-tool", "lookup", "service", "kairos-homeassistant", "account", "token"]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = text.trim();
                if (value === "")
                    root.status = "unconfigured";
                else
                    root.connect(root.url, value);
            }
        }
    }

    Process {
        id: saveUrl

        command: ["sh", "-c", "printf %s \"$KAIROS_HA_VALUE\" | secret-tool store --label='KairosOS Home Assistant URL' service kairos-homeassistant account url"]
        environment: ({
                KAIROS_HA_VALUE: root.pendingValue
            })
        onExited: {
            root.pendingValue = root.token;
            saveToken.running = true;
        }
    }

    Process {
        id: saveToken

        command: ["sh", "-c", "printf %s \"$KAIROS_HA_VALUE\" | secret-tool store --label='KairosOS Home Assistant token' service kairos-homeassistant account token"]
        environment: ({
                KAIROS_HA_VALUE: root.pendingValue
            })
        onExited: root.pendingValue = ""
    }

    Process {
        id: clearUrl

        command: ["secret-tool", "clear", "service", "kairos-homeassistant", "account", "url"]
    }

    Process {
        id: clearToken

        command: ["secret-tool", "clear", "service", "kairos-homeassistant", "account", "token"]
    }
}
