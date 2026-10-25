import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// A sheet that slides up over a dashboard tab, after the iOS bottom sheets: scrim, grabber, title and
// a close button. Whatever is placed inside fills the space under the title.
Item {
    id: root

    property bool open
    property string title
    readonly property real prog: open ? 1 : 0

    default property alias content: body.data

    signal closed

    anchors.fill: parent
    z: 20
    visible: sheetProg.value > 0

    // Animated copy of `prog`, so `visible` can wait for the slide to finish.
    QtObject {
        id: sheetProg

        property real value: root.prog

        Behavior on value {
            Anim {
                type: Anim.DefaultSpatial
            }
        }
    }

    // Scrim: tap outside to close.
    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.large
        color: Colours.palette.m3scrim
        opacity: 0.35 * sheetProg.value

        MouseArea {
            anchors.fill: parent
            enabled: root.open
            onClicked: root.closed()
        }
    }

    StyledRect {
        x: 0
        y: root.height - height * sheetProg.value
        width: root.width
        height: root.height - Tokens.padding.extraLarge
        topLeftRadius: Tokens.rounding.extraLarge
        topRightRadius: Tokens.rounding.extraLarge
        color: Colours.palette.m3surfaceContainerHigh

        // Keeps taps on the sheet itself from reaching the scrim.
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.small

            StyledRect {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 36
                implicitHeight: 4
                radius: Tokens.rounding.full
                color: Colours.palette.m3outlineVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    font: Tokens.font.body.builders.large.size(22).weight(Font.DemiBold).build()
                    color: Colours.palette.m3onSurface
                }

                IconButton {
                    type: IconButton.Tonal
                    isRound: true
                    icon: "close"
                    onClicked: root.closed()
                }
            }

            ColumnLayout {
                id: body

                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacing.small
            }
        }
    }
}
