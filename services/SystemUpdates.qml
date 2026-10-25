pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config

// Available updates for Settings → Updates: Arch repositories (checkupdates, from pacman-contrib,
// which never touches the real package database), the AUR (paru or yay), Flatpak, and this shell
// itself when it runs from a git checkout. Updating opens the terminal, where the package manager
// can ask for the password.
Singleton {
    id: root

    // [{source: "repo" | "aur" | "flatpak", name, from, to}]
    property var packages: []
    property bool checking
    property double lastCheck
    property string helper // "paru", "yay" or "" (pacman only)
    property bool hasCheckupdates
    property bool hasFlatpak

    // The shell's own checkout.
    property string shellBranch
    property string shellCommit
    property int shellBehind
    property bool shellIsGit

    readonly property int repoCount: packages.filter(p => p.source === "repo").length
    readonly property int aurCount: packages.filter(p => p.source === "aur").length
    readonly property int flatpakCount: packages.filter(p => p.source === "flatpak").length

    function check(): void {
        if (checking)
            return;
        checking = true;
        checker.running = true;
        shellCheck.running = true;
    }

    function runInTerminal(script: string): void {
        Quickshell.execDetached([...GlobalConfig.general.apps.terminal, `${Quickshell.shellDir}/assets/wrap_term_launch.sh`, "sh", "-c", script + "; echo; printf 'Done. Press Enter to close.'; read _"]);
    }

    function updateSystem(): void {
        const pm = helper !== "" ? `${helper} -Syu` : "sudo pacman -Syu";
        const flat = hasFlatpak ? "; flatpak update" : "";
        runInTerminal(pm + flat);
    }

    function updateShell(): void {
        runInTerminal(`git -C '${Quickshell.shellDir}' pull --ff-only && echo && echo 'Restart the shell to use the new version: caelestia shell -d'`);
    }

    Process {
        id: checker

        command: ["sh", "-c", `
            command -v checkupdates >/dev/null && { echo "has checkupdates"; checkupdates 2>/dev/null | sed 's/^/repo /'; }
            for h in paru yay; do
                if command -v "$h" >/dev/null; then echo "helper $h"; "$h" -Qua 2>/dev/null | sed 's/^/aur /'; break; fi
            done
            command -v flatpak >/dev/null && { echo "has flatpak"; flatpak remote-ls --updates --columns=application,version 2>/dev/null | sed 's/^/flatpak /'; }
            true`]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                let helperName = "";
                let checkupdates = false;
                let flatpak = false;
                for (const line of text.split("\n")) {
                    const t = line.trim();
                    if (t === "has checkupdates") {
                        checkupdates = true;
                    } else if (t === "has flatpak") {
                        flatpak = true;
                    } else if (t.startsWith("helper ")) {
                        helperName = t.slice(7);
                    } else if (t.startsWith("repo ") || t.startsWith("aur ")) {
                        // "name 1.0-1 -> 1.1-1"
                        const parts = t.split(/\s+/);
                        if (parts.length >= 5)
                            out.push({
                                source: parts[0],
                                name: parts[1],
                                from: parts[2],
                                to: parts[4]
                            });
                    } else if (t.startsWith("flatpak ")) {
                        const parts = t.split(/\s+/);
                        if (parts.length >= 2)
                            out.push({
                                source: "flatpak",
                                name: parts[1],
                                from: "",
                                to: parts[2] ?? ""
                            });
                    }
                }
                root.packages = out.sort((a, b) => a.source.localeCompare(b.source) || a.name.localeCompare(b.name));
                root.helper = helperName;
                root.hasCheckupdates = checkupdates;
                root.hasFlatpak = flatpak;
                root.lastCheck = Date.now();
                root.checking = false;
            }
        }
    }

    Process {
        id: shellCheck

        command: ["sh", "-c", `
            cd '${Quickshell.shellDir}' 2>/dev/null && git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
            echo "branch $(git rev-parse --abbrev-ref HEAD)"
            echo "commit $(git rev-parse --short HEAD)"
            timeout 20 git fetch --quiet 2>/dev/null
            echo "behind $(git rev-list --count HEAD..@{u} 2>/dev/null || echo 0)"`]
        stdout: StdioCollector {
            onStreamFinished: {
                let isGit = false;
                for (const line of text.split("\n")) {
                    const [key, ...rest] = line.trim().split(" ");
                    const value = rest.join(" ");
                    if (key === "branch") {
                        isGit = true;
                        root.shellBranch = value;
                    } else if (key === "commit") {
                        root.shellCommit = value;
                    } else if (key === "behind") {
                        root.shellBehind = parseInt(value) || 0;
                    }
                }
                root.shellIsGit = isGit;
            }
        }
    }
}
