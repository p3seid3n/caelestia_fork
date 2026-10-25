pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

// The to-do list of the dashboard "To-do" tab: plain checkable items.
// Kept in ~/.local/state/caelestia/todos.json.
Singleton {
    id: root

    // [{ id, text, done }] in the order they were added.
    property var items: []

    // id -> item, rebuilt whenever the list changes.
    readonly property var byId: {
        const map = {};
        for (const i of items)
            map[i.id] = i;
        return map;
    }
    readonly property int openCount: items.filter(i => !i.done).length
    readonly property int doneCount: items.length - openCount

    function add(text: string): void {
        const t = text.trim();
        if (t === "")
            return;
        setItems(items.concat([
            {
                id: Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
                text: t,
                done: false
            }
        ]));
    }

    function toggle(id: string): void {
        setItems(items.map(i => i.id === id ? {
                id: i.id,
                text: i.text,
                done: !i.done
            } : i));
    }

    function remove(id: string): void {
        setItems(items.filter(i => i.id !== id));
    }

    function clearDone(): void {
        setItems(items.filter(i => !i.done));
    }

    function setItems(next: var): void {
        items = next;
        saveTimer.restart();
    }

    Timer {
        id: saveTimer

        interval: 400
        onTriggered: file.setText(JSON.stringify({
                items: root.items
            }))
    }

    FileView {
        id: file

        printErrors: false
        path: `${Paths.state}/todos.json`
        onLoaded: {
            try {
                const c = JSON.parse(text());
                if (Array.isArray(c.items))
                    root.items = c.items.filter(i => typeof i.id === "string" && typeof i.text === "string").map(i => ({
                                id: i.id,
                                text: i.text,
                                done: i.done === true
                            }));
            } catch (error) {
                console.warn("Todos: could not parse list:", error);
            }
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                Qt.callLater(() => setText(JSON.stringify({
                        items: []
                    })));
        }
    }
}
