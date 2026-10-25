import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.services

// What is playing, with previous / play / next.
Item {
    id: root

    readonly property bool compact: height < 130

    RowLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.large

        StyledRect {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: root.compact ? 48 : 72
            implicitHeight: implicitWidth
            radius: Tokens.rounding.large
            color: Colours.palette.m3primaryContainer

            MaterialIcon {
                anchors.centerIn: parent
                text: Players.active?.isPlaying ? "graphic_eq" : "music_note"
                fill: 1
                color: Colours.palette.m3onPrimaryContainer
                fontStyle: Tokens.font.icon.large
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Tokens.spacing.extraSmall

            StyledText {
                Layout.fillWidth: true
                animate: true
                elide: Text.ElideRight
                text: Players.active ? (Players.active.trackTitle || Tr.tr("Unknown title")) : Tr.tr("Nothing playing")
                font: Tokens.font.title.small
                color: Colours.palette.m3onSurface
            }

            StyledText {
                Layout.fillWidth: true
                visible: Players.active !== null
                animate: true
                elide: Text.ElideRight
                text: Players.active?.trackArtist || Tr.tr("Unknown artist")
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }

            RowLayout {
                spacing: Tokens.spacing.extraSmall

                IconButton {
                    type: IconButton.Tonal
                    icon: "skip_previous"
                    isRound: true
                    disabled: !Players.active?.canGoPrevious
                    onClicked: Players.active?.previous()
                }

                IconButton {
                    icon: Players.active?.isPlaying ? "pause" : "play_arrow"
                    isRound: true
                    checked: Players.active?.isPlaying ?? false
                    disabled: !Players.active?.canTogglePlaying
                    onClicked: Players.active?.togglePlaying()
                }

                IconButton {
                    type: IconButton.Tonal
                    icon: "skip_next"
                    isRound: true
                    disabled: !Players.active?.canGoNext
                    onClicked: Players.active?.next()
                }
            }
        }
    }
}
