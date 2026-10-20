pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components
import qs.components.containers

// KairosOS: greeter -> desktop hand-off.
// The greeter ends on pure black and starts Hyprland with KAIROS_FROM_GREETER=1.
// This covers every screen in black from the shell's first frame, gives the wallpaper
// and bar a moment to load, then fades the desktop in. A marker in $XDG_RUNTIME_DIR
// (cleared at logout) stops it from replaying when the shell is restarted.
// Needs a Hyprland layer rule so the cover appears without an open animation:
//   hl.layer_rule({ match = { namespace = "caelestia-handoff" }, no_anim = true })
Scope {
    id: root

    property bool active

    FileView {
        path: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/kairos-handoff`
        blockLoading: true
        printErrors: false

        onLoadFailed: {
            if (Quickshell.env("KAIROS_FROM_GREETER") === "1") {
                root.active = true;
                setText("done");
            }
        }
    }

    LazyLoader {
        active: root.active

        Variants {
            model: Quickshell.screens

            StyledWindow {
                id: win

                required property ShellScreen modelData

                screen: modelData
                name: "handoff"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                mask: Region {}

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                Rectangle {
                    id: cover

                    anchors.fill: parent
                    color: "black"
                }

                SequentialAnimation {
                    running: true

                    PauseAnimation {
                        duration: 700 // let the wallpaper and bar draw underneath
                    }
                    Anim {
                        target: cover
                        property: "opacity"
                        to: 0
                        type: Anim.EmphasizedExtraLarge
                    }
                    ScriptAction {
                        script: root.active = false
                    }
                }
            }
        }
    }
}
