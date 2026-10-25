import QtQuick
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services

// One quiet line under the clock, also in the AoD state: how many notifications are waiting and
// what is playing. Like the always-on displays of phones.
Row {
    id: root

    required property real pointSize
    required property color colour
    property real boldness

    readonly property int notifCount: Notifs.notClosed.length
    readonly property bool playing: LockStyle.showMedia && (Players.active?.isPlaying ?? false)

    spacing: pointSize * 0.06
    visible: notifCount > 0 || playing
    opacity: 0.55 + 0.45 * boldness

    Row {
        visible: root.notifCount > 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.pointSize * 0.02

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: "notifications"
            fill: 1
            color: root.colour
            fontStyle: Tokens.font.icon.builders.medium.size(Math.round(root.pointSize * 0.1)).build()
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.notifCount
            color: root.colour
            font: Tokens.font.title.builders.medium.size(Math.round(root.pointSize * 0.09)).weight(Font.Medium).build()
        }
    }

    StyledText {
        visible: root.notifCount > 0 && root.playing
        anchors.verticalCenter: parent.verticalCenter
        text: "·"
        color: root.colour
        font: Tokens.font.title.builders.medium.size(Math.round(root.pointSize * 0.09)).build()
    }

    Row {
        visible: root.playing
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.pointSize * 0.02

        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: "music_note"
            color: root.colour
            fontStyle: Tokens.font.icon.builders.medium.size(Math.round(root.pointSize * 0.1)).build()
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.pointSize * 3.2)
            elide: Text.ElideRight
            text: [Players.active?.trackTitle, Players.active?.trackArtist].filter(x => x).join(" – ") || Tr.tr("Playing")
            color: root.colour
            font: Tokens.font.title.builders.medium.size(Math.round(root.pointSize * 0.09)).weight(Font.Medium).build()
        }
    }
}
