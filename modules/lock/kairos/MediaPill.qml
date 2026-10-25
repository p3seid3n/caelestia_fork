import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.components.images
import qs.services

// What is playing, with the cover and previous / play / next, for the awake lock screen.
StyledClippingRect {
    id: root

    implicitWidth: 400
    implicitHeight: 72
    radius: Tokens.rounding.full
    color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.85)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.small
        anchors.rightMargin: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        StyledClippingRect {
            implicitWidth: 56
            implicitHeight: 56
            radius: Tokens.rounding.full
            color: Colours.palette.m3primaryContainer

            MaterialIcon {
                anchors.centerIn: parent
                text: "music_note"
                color: Colours.palette.m3onPrimaryContainer
            }

            FadeImage {
                anchors.fill: parent
                source: Players.getArtUrl(Players.active)
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(112, 112)
                opacity: status === Image.Ready ? 1 : 0
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                animate: true
                elide: Text.ElideRight
                text: Players.active?.trackTitle || Tr.tr("Unknown title")
                font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
                color: Colours.palette.m3onSurface
            }

            StyledText {
                Layout.fillWidth: true
                animate: true
                elide: Text.ElideRight
                text: Players.active?.trackArtist || Tr.tr("Unknown artist")
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }
        }

        IconButton {
            type: IconButton.Text
            isRound: true
            icon: "skip_previous"
            disabled: !Players.active?.canGoPrevious
            onClicked: Players.active?.previous()
        }

        IconButton {
            isRound: true
            icon: Players.active?.isPlaying ? "pause" : "play_arrow"
            checked: Players.active?.isPlaying ?? false
            disabled: !Players.active?.canTogglePlaying
            onClicked: Players.active?.togglePlaying()
        }

        IconButton {
            type: IconButton.Text
            isRound: true
            icon: "skip_next"
            disabled: !Players.active?.canGoNext
            onClicked: Players.active?.next()
        }
    }
}
