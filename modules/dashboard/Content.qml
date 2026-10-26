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
    readonly property var dashboardTabs: DashboardLayout.visibleTabs.map(id => tabDefs[id]).filter(tab => tab && tab.enabled)

    // While customising, the sheet sets the height; the width never shrinks below the current tab's.
    readonly property real nonAnimWidth: (customizing ? Math.max(view.implicitWidth, sheet.implicitWidth) : view.implicitWidth) + viewWrapper.anchors.margins * 2
    readonly property real nonAnimHeight: tabs.implicitHeight + tabs.anchors.topMargin + (customizing ? sheet.implicitHeight : view.implicitHeight) + viewWrapper.anchors.margins * 2

    implicitWidth: nonAnimWidth
    implicitHeight: nonAnimHeight

    // Keep the selection valid when tabs are switched off.
    onDashboardTabsChanged: {
        if (screenState.dashboardTab >= dashboardTabs.length)
            screenState.dashboardTab = Math.max(0, dashboardTabs.length - 1);
    }

    // Picking a tab leaves the customise sheet.
    Connections {
        function onDashboardTabChanged(): void {
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
            // Bumped whenever the Repeater adds or removes a pane, so currentItem never stays
            // null when a pane arrives after the count changed.
            property int paneVersion
            readonly property Item currentItem: {
                repeater.count; // Trigger update on count change
                paneVersion;
                return repeater.itemAt(currentIndex);
            }

            anchors.fill: parent

            opacity: root.customizing ? 0 : 1
            enabled: !root.customizing
            flickableDirection: Flickable.HorizontalFlick

            implicitWidth: currentItem?.implicitWidth ?? 0
            implicitHeight: currentItem?.implicitHeight ?? 0

            contentX: currentItem?.x ?? 0
            contentWidth: row.implicitWidth
            contentHeight: row.implicitHeight

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

            RowLayout {
                id: row

                Repeater {
                    id: repeater

                    onItemAdded: view.paneVersion++
                    onItemRemoved: view.paneVersion++

                    model: ScriptModel {
                        values: root.dashboardTabs
                    }

                    delegate: Loader {
                        id: paneLoader

                        required property int index
                        required property var modelData
                        // Whether the pane is on screen (or being swiped in).
                        readonly property bool inView: {
                            if (index === view.currentIndex)
                                return true;
                            const vx = Math.floor(view.visibleArea.xPosition * view.contentWidth);
                            const vex = Math.floor(vx + view.visibleArea.widthRatio * view.contentWidth);
                            return (vx >= x && vx <= x + implicitWidth) || (vex >= x && vex <= x + implicitWidth);
                        }
                        // KairosOS: a tab built once stays built (switching back is instant); off
                        // screen it is fully transparent, which the renderer skips.
                        property bool built

                        Layout.alignment: Qt.AlignTop

                        sourceComponent: modelData.component
                        // Nothing is built before the binding below decides (a Loader starts
                        // active, which used to build every tab once at start).
                        active: false

                        opacity: inView ? 1 : 0
                        onLoaded: built = true
                        // Light tabs stay; tabs that keep working in the background (media
                        // visualiser, performance graphs) go when the dashboard closes, as before.
                        Component.onCompleted: active = Qt.binding(() => (built && (modelData.keepAlive ?? false)) || (inView && (root.screenState.dashboard || (modelData.keepAlive ?? false))))
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
