pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config

// Hyprland plugins for Settings → Plugins, managed with hyprpm (Hyprland's plugin manager): the
// repositories and plugins it knows, whether each is enabled, and which are loaded right now.
// Building plugins needs Hyprland's headers (hyprpm update), so installing and updating run in the
// terminal where hyprpm can ask for the password.
Singleton {
    id: root

    property bool hasHyprpm
    property bool busy
    property string error
    // [{repo, author, plugins: [{name, enabled, failed}]}]
    property var repos: []
    // Names of the plugins Hyprland has loaded.
    property var loaded: []

    readonly property bool hasHyprbars: repos.some(r => r.plugins.some(p => p.name === "hyprbars"))
    readonly property bool hyprbarsLoaded: loaded.some(n => n.toLowerCase().includes("hyprbars"))

    function refresh(): void {
        busy = true;
        lister.running = true;
        loadedLister.running = true;
    }

    function setEnabled(name: string, on: bool): void {
        busy = true;
        toggler.command = ["sh", "-c", `hyprpm ${on ? "enable" : "disable"} '${name.replace(/'/g, "")}' && hyprpm reload -n`];
        toggler.running = true;
    }

    function runInTerminal(script: string): void {
        Quickshell.execDetached([...Config.general.apps.terminal, `${Quickshell.shellDir}/assets/wrap_term_launch.sh`, "sh", "-c", script + "; echo; printf 'Done. Press Enter to close.'; read _"]);
    }

    // Title bars for floating windows: the official plugin repository, then hyprbars.
    function installTitleBars(): void {
        runInTerminal("hyprpm update && (hyprpm list | grep -q 'hyprland-plugins' || hyprpm add https://github.com/hyprwm/hyprland-plugins) && hyprpm enable hyprbars && hyprpm reload -n");
    }

    function addRepository(url: string): void {
        const clean = url.trim().replace(/'/g, "");
        if (clean !== "")
            runInTerminal(`hyprpm add '${clean}' && hyprpm reload -n`);
    }

    function updateAll(): void {
        runInTerminal("hyprpm update && hyprpm reload -n");
    }

    Component.onCompleted: refresh()

    Process {
        id: lister

        command: ["sh", "-c", "command -v hyprpm >/dev/null || { echo '__NO_HYPRPM__'; exit 0; }; hyprpm list 2>&1"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false;
                // hyprpm colours its output; drop the escape sequences first.
                const clean = text.replace(/\x1b\[[0-9;]*m/g, "");
                if (clean.includes("__NO_HYPRPM__")) {
                    root.hasHyprpm = false;
                    root.repos = [];
                    return;
                }
                root.hasHyprpm = true;
                const repos = [];
                let current = null;
                let plugin = null;
                for (const line of clean.split("\n")) {
                    const repo = /Repository\s+(\S+)\s+\(by\s+(.*)\):/.exec(line);
                    if (repo) {
                        current = {
                            repo: repo[1],
                            author: repo[2],
                            plugins: []
                        };
                        repos.push(current);
                        continue;
                    }
                    // "└─ enabled: true", "└─ enabled: Plugin failed to build"
                    const state = /enabled:\s*(.*)$/.exec(line);
                    if (state && plugin) {
                        plugin.enabled = state[1].trim().startsWith("true");
                        plugin.failed = state[1].includes("failed");
                        continue;
                    }
                    // "│ Plugin hyprbars"
                    const p = /│\s*Plugin\s+(\S+)/.exec(line);
                    if (p && current) {
                        plugin = {
                            name: p[1],
                            enabled: false,
                            failed: false
                        };
                        current.plugins.push(plugin);
                    }
                }
                root.repos = repos;
                root.error = repos.length === 0 && /error|headers/i.test(clean) ? clean.trim().split("\n").slice(-1)[0] : "";
            }
        }
    }

    Process {
        id: loadedLister

        command: ["hyprctl", "-j", "plugin", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const list = JSON.parse(text);
                    root.loaded = Array.isArray(list) ? list.map(p => String(p.name ?? "")) : [];
                } catch (error) {
                    root.loaded = [];
                }
            }
        }
    }

    Process {
        id: toggler

        stdout: StdioCollector {
            onStreamFinished: root.refresh()
        }
    }
}
