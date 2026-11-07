pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.filedialog
import qs.services

Item {
    id: root

    required property ScreenState screenState
    required property FileDialog facePicker

    property bool customizing

    // Everything the dashboard can show. DashboardLayout decides which of these appear and in what order;
    // the old config flags can still switch off the tabs that have one.
    readonly property var tabDefs: ({
            calendar: {
                component: calendarComponent,
                keepAlive: true,
                iconName: "calendar_month",
                text: Tr.tr("Calendar"),
                enabled: true
            },
            todo: {
                component: todoComponent,
                keepAlive: true,
                iconName: "checklist",
                text: Tr.tr("To-do"),
                enabled: true
            },
            home: {
                component: homeComponent,
                keepAlive: true,
                iconName: "home",
                text: Tr.tr("Home"),
                enabled: true
            },
            dashboard: {
                component: boardComponent,
                keepAlive: true,
                iconName: "dashboard",
                text: Tr.tr("Dashboard"),
                enabled: Config.dashboard.showDashboard
            },
            classic: {
                component: dashComponent,
                iconName: "dashboard_customize",
                text: Tr.tr("Classic dashboard"),
                enabled: Config.dashboard.showDashboard
            },
            media: {
                component: mediaComponent,
                iconName: "queue_music",
                text: Tr.tr("Media"),
                enabled: Config.dashboard.showMedia
            },
            performance: {
                component: performanceComponent,
                iconName: "speed",
                text: Tr.tr("Performance"),
                enabled: Config.dashboard.showPerformance
            },
            weather: {
                component: weatherComponent,
                iconName: "cloud",
                text: Tr.tr("Weather"),
                enabled: Config.dashboard.showWeather
            }
        })
    // The shown tabs' ids, in order, and their definitions (for the tab bar).
    readonly property var tabIds: DashboardLayout.visibleTabs.filter(id => tabDefs[id]?.enabled ?? false)
    readonly property var dashboardTabs: tabIds.map(id => tabDefs[id])
    // Every tab there is; each has one pane for good, which only moves when the order changes.
    readonly property var allIds: ["calendar", "todo", "home", "dashboard", "classic", "media", "performance", "weather"]
    // The tab that was on screen, so it stays selected when tabs are added, removed or moved.
    property string currentId
    property bool remapping
    // Size of the last pane that was built: a tab that is still loading takes it, so the
    // dashboard doesn't shrink to nothing and grow back while it loads.
    property real lastPaneW: 600
    property real lastPaneH: 400

    // While customising, the sheet sets the height; the width never shrinks below the current tab's.
    readonly property real nonAnimWidth: (customizing ? Math.max(view.implicitWidth, sheet.implicitWidth) : view.implicitWidth) + viewWrapper.anchors.margins * 2
    readonly property real nonAnimHeight: tabs.implicitHeight + tabs.anchors.topMargin + (customizing ? sheet.implicitHeight : view.implicitHeight) + viewWrapper.anchors.margins * 2

    // Where the pane in `slot` starts: the widths of the panes before it.
    function paneX(slot: int): real {
        let x = 0;
        for (let i = 0; i < repeater.count; i++) {
            const p = repeater.itemAt(i);
            if (p && p.slot >= 0 && p.slot < slot)
                x += p.implicitWidth;
        }
        return x;
    }

    function paneAt(slot: int): Item {
        for (let i = 0; i < repeater.count; i++) {
            const p = repeater.itemAt(i);
            if (p && p.slot === slot)
                return p;
        }
        return null;
    }

    implicitWidth: nonAnimWidth
    implicitHeight: nonAnimHeight

    // Tabs switched on, off or moved: the tab on screen stays selected (or the nearest one).
    onTabIdsChanged: {
        const at = tabIds.indexOf(currentId);
        const next = at >= 0 ? at : Math.max(0, Math.min(screenState.dashboardTab, tabIds.length - 1));
        if (next !== screenState.dashboardTab) {
            remapping = true;
            screenState.dashboardTab = next;
            remapping = false;
        }
        currentId = tabIds[screenState.dashboardTab] ?? "";
    }
    Component.onCompleted: currentId = tabIds[screenState.dashboardTab] ?? ""

    // Picking a tab leaves the customise sheet.
    Connections {
        function onDashboardTabChanged(): void {
            if (root.remapping)
                return;
            // The tab bar also follows a moved tab; that is not picking another tab.
            const id = root.tabIds[root.screenState.dashboardTab] ?? "";
            if (id === root.currentId)
                return;
            root.currentId = id;
            root.customizing = false;
        }

        target: root.screenState
    }

    Tabs {
        id: tabs

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: CUtils.clamp(anchors.margins - Config.border.thickness, 0, anchors.margins)
        anchors.margins: Tokens.padding.large

        nonAnimWidth: root.nonAnimWidth - anchors.margins * 2
        screenState: root.screenState
        tabs: root.dashboardTabs
        onCustomizeRequested: root.customizing = !root.customizing
    }

    // The only place that sets dashboardInput: the tab on screen decides (`wantsInput` on its root).
    // Tabs used to set it themselves with RestoreValue Bindings, but a tab unloading after the next
    // one had loaded restored its stale value and took the keyboard away again.
    Binding {
        target: root.screenState
        property: "dashboardInput"
        value: (view.currentItem as Loader)?.item?.wantsInput ?? false
    }

    ClippingRectangle {
        id: viewWrapper

        anchors.top: tabs.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.padding.large

        radius: Tokens.rounding.large
        color: "transparent"

        Flickable {
            id: view

            readonly property int currentIndex: root.screenState.dashboardTab
            readonly property Item currentItem: {
                repeater.count;
                root.tabIds;
                return root.paneAt(currentIndex);
            }
            readonly property bool currentReady: !!(currentItem as Loader)?.item

            anchors.fill: parent

            opacity: root.customizing ? 0 : 1
            enabled: !root.customizing
            flickableDirection: Flickable.HorizontalFlick

            // A tab that is still loading keeps the last size, so the dashboard doesn't shrink
            // to nothing and grow back.
            implicitWidth: currentReady ? currentItem.implicitWidth : root.lastPaneW
            implicitHeight: currentReady ? currentItem.implicitHeight : root.lastPaneH

            contentX: currentItem?.x ?? 0
            contentWidth: row.width
            contentHeight: row.height

            onContentXChanged: {
                if (!moving || !currentItem)
                    return;

                const x = contentX - currentItem.x;
                if (x > currentItem.implicitWidth / 2)
                    root.screenState.dashboardTab = Math.min(root.screenState.dashboardTab + 1, tabs.count - 1);
                else if (x < -currentItem.implicitWidth / 2)
                    root.screenState.dashboardTab = Math.max(root.screenState.dashboardTab - 1, 0);
            }

            onDragEnded: {
                if (!currentItem)
                    return;

                const x = contentX - currentItem.x;
                if (x > currentItem.implicitWidth / 10)
                    root.screenState.dashboardTab = Math.min(root.screenState.dashboardTab + 1, tabs.count - 1);
                else if (x < -currentItem.implicitWidth / 10)
                    root.screenState.dashboardTab = Math.max(root.screenState.dashboardTab - 1, 0);
                else
                    contentX = Qt.binding(() => currentItem?.x ?? 0);
            }

            // One pane per tab, placed side by side in the tab bar's order (hidden tabs take no
            // room). The panes never get swapped between tabs, so a tab that is switched on or moved
            // keeps (or gets) its own content.
            Item {
                id: row

                width: root.paneX(root.tabIds.length)
                height: {
                    let h = 0;
                    for (let i = 0; i < repeater.count; i++)
                        h = Math.max(h, repeater.itemAt(i)?.implicitHeight ?? 0);
                    return h;
                }

                Repeater {
                    id: repeater

                    model: root.allIds

                    delegate: Loader {
                        id: paneLoader

                        required property string modelData
                        readonly property var def: root.tabDefs[modelData]
                        // Position in the tab bar; -1 while the tab is hidden.
                        readonly property int slot: root.tabIds.indexOf(modelData)
                        // Whether any of the pane is inside the visible area right now.
                        readonly property bool onScreen: {
                            if (slot < 0)
                                return false;
                            if (slot === view.currentIndex)
                                return true;
                            const vx = Math.floor(view.visibleArea.xPosition * view.contentWidth);
                            const vex = Math.floor(vx + view.visibleArea.widthRatio * view.contentWidth);
                            return (vx >= x && vx <= x + implicitWidth) || (vex >= x && vex <= x + implicitWidth);
                        }
                        // Whether the pane should be built: the selected tab, or one being swiped
                        // in by hand. Tabs the slide only passes over (Home -> Performance passes
                        // Media) are not built: that used to build and drop the media tab, with its
                        // audio visualiser, on the way, which stalled the slide and glitched audio.
                        readonly property bool inView: slot >= 0 && (slot === view.currentIndex || (onScreen && (view.dragging || view.flicking)))
                        // KairosOS: a tab built once stays built (switching back is instant); off
                        // screen it is fully transparent, which the renderer skips.
                        property bool built

                        x: slot >= 0 ? root.paneX(slot) : 0
                        visible: slot >= 0
                        sourceComponent: def?.component ?? null
                        // Built in the background, so the tab bar and the slide never wait for it.
                        asynchronous: true
                        // Nothing is built before the binding below decides (a Loader starts
                        // active, which used to build every tab once at start).
                        active: false

                        opacity: onScreen ? 1 : 0
                        onImplicitWidthChanged: {
                            if (item && implicitWidth > 0)
                                root.lastPaneW = implicitWidth;
                        }
                        onImplicitHeightChanged: {
                            if (item && implicitHeight > 0)
                                root.lastPaneH = implicitHeight;
                        }
                        onLoaded: built = true
                        // Light tabs stay; tabs that keep working in the background (media
                        // visualiser, performance graphs) go when the dashboard closes, as before.
                        // A hidden tab is let go.
                        Component.onCompleted: active = Qt.binding(() => slot >= 0 && ((built && (def?.keepAlive ?? false)) || (inView && (root.screenState.dashboard || (def?.keepAlive ?? false)))))
                    }
                }
            }

            Component {
                id: calendarComponent

                CalendarTab {
                    screenState: root.screenState
                }
            }

            Component {
                id: todoComponent

                TodoTab {
                    screenState: root.screenState
                }
            }

            Component {
                id: boardComponent

                DashboardBoard {}
            }

            Component {
                id: dashComponent

                Dash {
                    screenState: root.screenState
                    facePicker: root.facePicker
                }
            }

            Component {
                id: mediaComponent

                Media {
                    screenState: root.screenState
                }
            }

            Component {
                id: performanceComponent

                Performance {}
            }

            Component {
                id: weatherComponent

                WeatherTab {}
            }

            Component {
                id: homeComponent

                HomeTab {
                    screenState: root.screenState
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Behavior on contentX {
                Anim {}
            }
        }

        CustomizeSheet {
            id: sheet

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top

            opacity: root.customizing ? 1 : 0
            visible: opacity > 0
            onDone: root.customizing = false

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }
    }

    Behavior on implicitWidth {
        Anim {}
    }

    Behavior on implicitHeight {
        Anim {}
    }
}
