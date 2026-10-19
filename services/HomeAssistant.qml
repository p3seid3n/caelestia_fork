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
    // Entity ids the user chose to show, in display order.
    property list<string> selected: []

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

    // Values handed to the keyring helper processes (kept out of the command line).
    property string pendingValue

    function domainOf(entityId: string): string {
        return entityId.split(".")[0];
    }

    function isSensitive(entityId: string): bool {
        const e = byId[entityId];
        return sensitiveDomains.includes(domainOf(entityId)) || e?.attributes?.device_class === "garage" || e?.attributes?.device_class === "door";
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

    function setSelected(entityId: string, on: bool): void {
        const next = selected.filter(id => id !== entityId);
        if (on)
            next.push(entityId);
        selected = next;
        settingsSaveTimer.restart();
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
                const list = JSON.parse(body).map(e => ({
                            entity_id: e.entity_id,
                            state: e.state,
                            attributes: {
                                friendly_name: e.attributes?.friendly_name ?? e.entity_id,
                                unit_of_measurement: e.attributes?.unit_of_measurement ?? "",
                                device_class: e.attributes?.device_class ?? "",
                                brightness: e.attributes?.brightness ?? null
                            }
                        }));
                list.sort((a, b) => a.attributes.friendly_name.localeCompare(b.attributes.friendly_name));
                const map = {};
                for (const e of list)
                    map[e.entity_id] = e;
                entities = list;
                byId = map;
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
        id: settingsSaveTimer

        interval: 500
        onTriggered: settings.setText(JSON.stringify({
                selected: root.selected
            }))
    }

    FileView {
        id: settings

        printErrors: false
        path: `${Paths.state}/homeassistant.json`
        onLoaded: {
            try {
                root.selected = JSON.parse(text()).selected ?? [];
            } catch (error) {
                console.warn("HomeAssistant: could not parse settings:", error);
            }
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => setText(JSON.stringify({
                        selected: []
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
