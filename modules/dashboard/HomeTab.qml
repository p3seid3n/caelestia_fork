import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// Dashboard "Home" tab: Home Assistant.
// Step 1: setup form + connection status. Entity picker and controls come next.
Item {
    id: root

    implicitWidth: 840
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2

    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.medium

        StyledText {
            text: Tr.tr("Home Assistant")
            font: Tokens.font.body.builders.large.size(28).weight(Font.DemiBold).build()
            color: Colours.palette.m3onSurface
        }

        // Setup form (shown until a working connection exists)
        ColumnLayout {
            Layout.fillWidth: true
            visible: !HomeAssistant.connected
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Tr.tr("Enter your Home Assistant address and a long-lived access token (Profile → Security in Home Assistant). They are stored in your system keyring, never in a config file.")
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }

            StyledTextField {
                id: urlField

                Layout.fillWidth: true
                placeholderText: Tr.tr("Address, e.g. http://homeassistant.local:8123")
                leadingIcon: "link"
                text: HomeAssistant.url
                enabled: HomeAssistant.status !== "connecting"
            }

            StyledTextField {
                id: tokenField

                Layout.fillWidth: true
                placeholderText: Tr.tr("Long-lived access token")
                leadingIcon: "key"
                echoMode: TextInput.Password
                enabled: HomeAssistant.status !== "connecting"

                onAccepted: HomeAssistant.connect(urlField.text, tokenField.text)
            }

            StyledText {
                Layout.fillWidth: true
                visible: HomeAssistant.status === "error"
                wrapMode: Text.WordWrap
                text: HomeAssistant.errorText
                font: Tokens.font.body.small
                color: Colours.palette.m3error
            }

            TextButton {
                Layout.alignment: Qt.AlignRight
                horizontalPadding: Tokens.padding.extraLarge
                type: TextButton.Filled
                text: HomeAssistant.status === "connecting" ? Tr.tr("Connecting...") : Tr.tr("Connect")
                disabled: HomeAssistant.status === "connecting"
                onClicked: HomeAssistant.connect(urlField.text, tokenField.text)
            }
        }

        // Connected view (placeholder until the entity picker exists)
        ColumnLayout {
            Layout.fillWidth: true
            visible: HomeAssistant.connected
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Tr.tr("Connected to %1").arg(HomeAssistant.url)
                font: Tokens.font.body.medium
                color: Colours.palette.m3primary
            }

            TextButton {
                Layout.alignment: Qt.AlignRight
                horizontalPadding: Tokens.padding.extraLarge
                type: TextButton.Tonal
                text: Tr.tr("Disconnect")
                onClicked: HomeAssistant.forget()
            }
        }
    }
}
