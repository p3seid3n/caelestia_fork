import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    property string placeQuery
    property var placeResults: []

    // Temperature units (there must be one for each value of the TemperatureUnit enum)
    readonly property list<MenuItem> tempItems: [
        MenuItem {
            text: Tr.tr("Auto")
            value: TemperatureUnit.Auto
        },
        MenuItem {
            text: Tr.tr("°C")
            value: TemperatureUnit.Celsius
        },
        MenuItem {
            text: Tr.tr("°F")
            value: TemperatureUnit.Fahrenheit
        },
        MenuItem {
            text: Tr.tr("K")
            value: TemperatureUnit.Kelvin
        }
    ]

    // Data size units (there must be one for each value of the DataUnit enum)
    readonly property list<MenuItem> dataItems: [
        MenuItem {
            text: Tr.tr("Binary (KiB, MiB)")
            value: DataUnit.Binary
        },
        MenuItem {
            text: Tr.tr("Decimal (KB, MB)")
            value: DataUnit.Decimal
        }
    ]

    // Clock formats (there must be one for each value of the ClockFormat enum)
    readonly property list<MenuItem> clockItems: [
        MenuItem {
            text: Tr.tr("Auto")
            value: ClockFormat.Auto
        },
        MenuItem {
            text: Tr.tr("12-hour")
            value: ClockFormat.TwelveHour
        },
        MenuItem {
            text: Tr.tr("24-hour")
            value: ClockFormat.TwentyFourHour
        }
    ]

    // Places for the weather location (Open-Meteo geocoding, as the weather service uses).
    function searchPlace(query: string): void {
        const q = query.trim();
        if (q.length < 2) {
            placeResults = [];
            return;
        }
        const lang = Qt.locale().name.split("_")[0] || "en";
        Requests.get(`https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(q)}&count=5&language=${lang}&format=json`, text => {
            if (q !== placeQuery.trim())
                return;
            try {
                placeResults = JSON.parse(text).results ?? [];
            } catch (error) {
                placeResults = [];
            }
        });
    }

    title: Tr.tr("Language & region")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Language
        SectionHeader {
            first: true
            text: Tr.tr("Language")
        }

        SelectRow {
            first: true
            last: true
            label: Tr.tr("UI language")
            subtext: Tr.tr("The language used in the shell UI")
            active: menuItems.find(i => i.modelData === Tr.language) ?? autoLang
            onSelected: item => {
                Tr.language = item.modelData ?? ""; // qmllint disable missing-property
            }

            menuItems: [autoLang, ...langItems.instances]

            MenuItem {
                id: autoLang

                text: Tr.tr("Auto")
            }

            Variants {
                id: langItems

                model: Tr.supportedLanguages

                MenuItem {
                    required property string modelData

                    text: {
                        const locale = Qt.locale(modelData);
                        return locale.name === "C" ? modelData : locale.nativeLanguageName || locale.name;
                    }
                }
            }
        }

        // Weather
        SectionHeader {
            text: Tr.tr("Weather")
        }

        // Location: search a place, or let the shell find it from the IP address.
        TextFieldRow {
            id: placeField

            first: true
            label: Tr.tr("Location")
            subtext: GlobalConfig.services.weatherLocation ? Tr.tr("Weather for %1").arg(Weather.city || GlobalConfig.services.weatherLocation) : Tr.tr("Found automatically (%1)").arg(Weather.city || Tr.tr("locating..."))
            placeholderText: Tr.tr("Search a city")
            onValueEdited: value => {
                root.placeQuery = value;
                placeTimer.restart();
            }
        }

        Repeater {
            model: root.placeResults

            RowButton {
                required property var modelData

                icon: "location_on"
                text: modelData.name
                subtext: [modelData.admin1, modelData.country].filter(x => x).join(", ")
                onClicked: {
                    GlobalConfig.services.weatherLocation = `${modelData.latitude},${modelData.longitude}`;
                    root.placeResults = [];
                    placeField.field.text = "";
                    Weather.reload();
                }
            }
        }

        RowButton {
            last: true
            icon: "my_location"
            text: Tr.tr("Find my location automatically")
            subtext: Tr.tr("From your internet connection, refreshed every 15 minutes")
            disabled: !GlobalConfig.services.weatherLocation
            onClicked: {
                GlobalConfig.services.weatherLocation = "";
                Weather.reload();
            }
        }

        Timer {
            id: placeTimer

            interval: 350
            onTriggered: root.searchPlace(root.placeQuery)
        }

        // Units
        SectionHeader {
            text: Tr.tr("Units")
        }

        SelectRow {
            first: true
            label: Tr.tr("Temperature")
            subtext: Tr.tr("Units for weather temperatures")
            menuItems: root.tempItems
            active: root.tempItems.find(i => i.value === GlobalConfig.services.weatherUnits)
            onSelected: item => GlobalConfig.services.weatherUnits = item.value
        }

        SelectRow {
            label: Tr.tr("System temperatures")
            subtext: Tr.tr("Units for CPU and GPU temperatures")
            menuItems: root.tempItems
            active: root.tempItems.find(i => i.value === GlobalConfig.services.sensorUnits)
            onSelected: item => GlobalConfig.services.sensorUnits = item.value
        }

        SelectRow {
            last: true
            label: Tr.tr("Data sizes")
            subtext: Tr.tr("Units for data sizes and network speeds")
            menuItems: root.dataItems
            active: root.dataItems.find(i => i.value === GlobalConfig.services.dataUnits)
            onSelected: item => GlobalConfig.services.dataUnits = item.value
        }

        // Time & date
        SectionHeader {
            text: Tr.tr("Time & date")
        }

        SelectRow {
            first: true
            last: true
            label: Tr.tr("Clock format")
            subtext: Tr.tr("How times are shown across the shell")
            menuItems: root.clockItems
            active: root.clockItems.find(i => i.value === GlobalConfig.services.clockFormat)
            onSelected: item => GlobalConfig.services.clockFormat = item.value
        }
    }
}
