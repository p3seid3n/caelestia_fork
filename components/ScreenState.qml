import Quickshell

PersistentProperties {
    required property ShellScreen modelData

    // Drawer visibilities
    property bool bar
    property bool osd
    property bool session
    property bool launcher
    property bool dashboard
    property bool utilities
    property bool sidebar
    // KairosOS: notification centre in the top right corner
    property bool notifCentre

    // Dashboard state
    property int dashboardTab
    property date dashboardDate: new Date()
    // KairosOS: a dashboard tab with text fields (Home) needs keyboard focus
    property bool dashboardInput
}
