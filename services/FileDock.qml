pragma Singleton

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.utils

// The bar's file dock (like OxygenOS's): quick access to files for dragging them into apps.
// It only keeps shortcuts (paths), never copies; a file that is moved or deleted drops out.
//   - New screenshots show up by themselves: the usual screenshot folders are watched (Qt's file
//     watcher, nothing polls) and the screen picker reports its own captures.
//   - Anything dropped on the bar is added.
// Newest first, at most `limit` items; kept across restarts in ~/.local/state/caelestia.
Singleton {
    id: root

    readonly property int limit: 24
    // [{ path, kind: "screenshot" | "file", added }]
    property var items: []
    // A drag out of the dock is under way (the popout stays open for it).
    property bool dragging
    // A file drag from another app is over the bar.
    property bool dropHover
    // Screenshot folders; files that appear there after the shell started are added.
    readonly property list<string> watched: [`${Paths.pictures}/Screenshots`, Paths.pictures, `${Paths.home}/Desktop`]
    readonly property double startedAt: Date.now()

    // The dock's "+" asks for a file (the bar owns the picker, so it outlives the popout).
    signal pickRequested

    function isImage(path: string): bool {
        return /\.(png|jpe?g|webp|gif|bmp|avif|jxl|svg)$/i.test(path);
    }

    function nameOf(path: string): string {
        return String(path).replace(/\/+$/, "").split("/").pop();
    }

    function iconFor(path: string): string {
        const p = String(path).toLowerCase();
        if (isImage(p))
            return "image";
        if (/\.pdf$/.test(p))
            return "picture_as_pdf";
        if (/\.(mp4|mkv|webm|mov|avi)$/.test(p))
            return "movie";
        if (/\.(mp3|flac|ogg|opus|wav|m4a)$/.test(p))
            return "audio_file";
        if (/\.(zip|tar|gz|xz|zst|7z|rar)$/.test(p))
            return "folder_zip";
        if (/\.(docx?|odt|rtf|txt|md)$/.test(p))
            return "description";
        if (/\.(xlsx?|ods|csv)$/.test(p))
            return "table_chart";
        if (/\.(pptx?|odp)$/.test(p))
            return "slideshow";
        if (/\.(blend|fbx|obj|glb|gltf|usd[az]?)$/.test(p))
            return "deployed_code";
        if (!/\.[a-z0-9]{1,5}$/.test(p))
            return "folder";
        return "draft";
    }

    function urlFor(path: string): string {
        return "file://" + String(path).split("/").map(s => encodeURIComponent(s)).join("/");
    }

    function add(path: string, kind: string): void {
        path = String(path ?? "").replace(/^file:\/\//, "");
        try {
            path = decodeURIComponent(path);
        } catch (e) {}
        if (!path.startsWith("/"))
            return;
        let rest = items.filter(i => i.path !== path);
        // A capture from the screen picker that was then saved (swappy): keep only the saved file.
        if (kind === "screenshot" && !path.startsWith("/tmp/"))
            rest = rest.filter(i => !(i.path.startsWith("/tmp/caelestia-picker-") && Date.now() - i.added < 120000));
        rest.unshift({
            path,
            kind: kind || "file",
            added: Date.now()
        });
        items = rest.slice(0, limit);
        save();
    }

    function addUrls(urls: var): void {
        for (const u of Array.from(urls ?? []).reverse())
            add(String(u), "file");
    }

    // Local files in a drag or drop: its URLs, or (some apps only send text) file paths in its text.
    function filesIn(event: var): var {
        const urls = Array.from(event.urls ?? []).map(u => String(u)).filter(u => u.startsWith("file://"));
        if (urls.length > 0)
            return urls;
        const text = String(event.text ?? event.getDataAsString?.("text/uri-list") ?? "");
        return text.split(/\r?\n/).map(l => l.trim()).filter(l => l.startsWith("file://") || l.startsWith("/"));
    }

    // DropArea.onEntered: takes drags that carry files (not a drag out of the dock itself).
    function enter(drag: var): void {
        const files = drag.hasUrls || drag.hasText || (drag.formats ?? []).includes("text/uri-list");
        if (!files || dragging) {
            drag.accepted = false;
            return;
        }
        dropHover = true;
        drag.accept(Qt.CopyAction);
    }

    // DropArea.onDropped
    function drop(event: var): void {
        dropHover = false;
        if (dragging)
            return;
        const files = filesIn(event);
        if (files.length === 0)
            return;
        addUrls(files);
        event.accept(Qt.CopyAction);
    }

    function remove(path: string): void {
        items = items.filter(i => i.path !== path);
        save();
    }

    function clear(): void {
        items = [];
        save();
    }

    function save(): void {
        saveTimer.restart();
    }

    // Drops shortcuts whose file is gone.
    function prune(): void {
        if (items.length > 0 && !pruneProc.running) {
            pruneProc.command = ["sh", "-c", "for f; do [ -e \"$f\" ] && printf '%s\\n' \"$f\"; done; exit 0", "sh"].concat(items.map(i => i.path));
            pruneProc.running = true;
        }
    }

    Process {
        id: pruneProc

        stdout: StdioCollector {
            onStreamFinished: {
                const alive = new Set(text.split("\n").filter(l => l));
                const next = root.items.filter(i => alive.has(i.path));
                if (next.length !== root.items.length) {
                    root.items = next;
                    root.save();
                }
            }
        }
    }

    Timer {
        id: saveTimer

        interval: 300
        onTriggered: file.setText(JSON.stringify(root.items))
    }

    FileView {
        id: file

        printErrors: false
        path: `${Paths.state}/filedock.json`
        onLoaded: {
            try {
                const list = JSON.parse(text());
                if (Array.isArray(list))
                    root.items = list.filter(i => typeof i?.path === "string").slice(0, root.limit);
            } catch (e) {}
            root.prune();
        }
    }

    Instantiator {
        model: root.watched

        FolderListModel {
            id: folder

            required property string modelData
            // Paths seen at the first scan; only files after that are new.
            property var known: null
            // A screenshot is written in pieces: give it a moment before it is shown.
            readonly property Timer scanTimer: Timer {
                interval: 350
                onTriggered: folder.scan()
            }

            function scan(): void {
                if (status !== FolderListModel.Ready)
                    return;
                if (known === null) {
                    const seen = new Set();
                    for (let i = 0; i < count; i++)
                        seen.add(get(i, "filePath"));
                    known = seen;
                    return;
                }
                const fresh = [];
                for (let i = 0; i < count; i++) {
                    const p = get(i, "filePath");
                    if (known.has(p))
                        continue;
                    known.add(p);
                    const modified = get(i, "fileModified");
                    if (!modified || modified.getTime() >= root.startedAt - 5000)
                        fresh.push(p);
                }
                // The model is sorted newest first; add oldest first so the newest ends on top.
                for (const p of fresh.reverse())
                    root.add(p, "screenshot");
            }

            folder: root.urlFor(modelData)
            nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
            showDirs: false
            showHidden: false
            sortField: FolderListModel.Time
            onStatusChanged: scan()
            onCountChanged: scanTimer.restart()
        }
    }
}
