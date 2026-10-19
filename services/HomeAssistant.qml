pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.I18n

// Home Assistant connection for the dashboard "Home" tab.
//
// Credentials are typed into the panel by the user and stored in the system
// keyring through `secret-tool` (package: libsecret). Nothing secret is ever
// written to the config or the repository.
Singleton {
    id: root

    // "loading" | "unconfigured" | "connecting" | "connected" | "error"
    property string status: "loading"
    property string errorText
    property string url
    property string token

    readonly property bool connected: status === "connected"

    // Values handed to the keyring helper processes (kept out of the command line).
    property string pendingValue

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

    // Remove the stored credentials and return to the setup form.
    function forget(): void {
        clearUrl.running = true;
        clearToken.running = true;
        url = "";
        token = "";
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
