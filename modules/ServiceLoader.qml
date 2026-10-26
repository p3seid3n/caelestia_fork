import QtQuick
import Quickshell
import Caelestia.Config
import qs.services

Scope {
    Component.onCompleted: {
        // Force certain singletons to load on shell init instead of lazily

        IdleInhibitor;
        GameMode;
        Notifs;
        Players;
        Brightness;
        Weather.reload();

        // KairosOS: window and display settings are applied at start; the dashboard's data is
        // ready before it first opens.
        WindowLayout;
        Displays;
        NotifCentre;
        DashboardLayout;
        DashboardWidgets;
        Todos;
        Subjects;
        Assignments;
        Calendars;

        if (GlobalConfig.utilities.vpn.enabled)
            VPN;
    }
}
