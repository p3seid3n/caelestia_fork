pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import M3Shapes

// The typed characters, animated exactly like Caelestia's lock screen
// (modules/lock/center/InputField.qml): each character pops in as a random Material
// shape, then settles into a small circle. Revealing shows the real characters.
Item {
    id: root

    required property string buffer
    property bool showPassword
    property color colour: "white"
    property real charSize: 14 // Caelestia body.medium

    property string shown // follows buffer, so removals can animate first
    readonly property list<int> shapeQueue: {
        const shapes = [MaterialShape.Slanted, MaterialShape.Arch, MaterialShape.Fan, MaterialShape.Arrow, MaterialShape.SemiCircle, MaterialShape.Triangle, MaterialShape.Diamond, MaterialShape.ClamShell, MaterialShape.Pentagon, MaterialShape.Gem, MaterialShape.Sunny, MaterialShape.VerySunny, MaterialShape.Cookie4Sided, MaterialShape.Ghostish, MaterialShape.SoftBurst];
        for (let i = shapes.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [shapes[i], shapes[j]] = [shapes[j], shapes[i]];
        }
        return shapes;
    }

    clip: true

    onBufferChanged: {
        if (buffer.length > shown.length)
            charList.bindImWidth();
        else if (buffer.length === 0)
            charList.implicitWidth = charList.implicitWidth; // freeze, then shrink as chars leave
        shown = buffer;
    }

    ListView {
        id: charList

        readonly property int fullWidth: {
            let w = (count - 1) * spacing;
            for (let i = 0; i < count; i++)
                w += ((itemAtIndex(i) as CharItem)?.nonAnimWidthScale ?? 1) * implicitHeight;
            return w + implicitHeight;
        }

        function bindImWidth(): void {
            imWidthBehavior.enabled = false;
            implicitWidth = Qt.binding(() => fullWidth);
            imWidthBehavior.enabled = true;
        }

        anchors.centerIn: parent
        anchors.horizontalCenterOffset: implicitWidth > root.width ? -(implicitWidth - root.width) / 2 : 0

        implicitWidth: fullWidth
        implicitHeight: root.charSize

        orientation: Qt.Horizontal
        spacing: 4
        interactive: false

        model: ScriptModel {
            values: root.shown.split("")
        }

        delegate: CharItem {}

        Behavior on implicitWidth {
            id: imWidthBehavior

            Motion {}
        }
    }

    component CharItem: Item {
        id: char

        required property int index
        property real nonAnimWidthScale: 1

        implicitHeight: charList.implicitHeight

        ListView.onRemove: {
            initAnim.stop();
            removeAnim.start();
        }

        SequentialAnimation {
            id: initAnim

            running: true

            ParallelAnimation {
                Motion {
                    target: char
                    property: "opacity"
                    from: 0
                    to: 1
                    type: "defaultEffects"
                }
                Motion {
                    target: char
                    property: "scale"
                    from: 0
                    to: 1
                    type: "fastSpatial"
                }
                Motion {
                    target: char
                    property: "implicitWidth"
                    from: charList.implicitHeight
                    to: charList.implicitHeight * 1.3
                    type: "defaultEffects"
                }
                PropertyAction {
                    target: char
                    property: "nonAnimWidthScale"
                    value: 1.5
                }
            }
            PauseAnimation {
                duration: 180
            }
            PropertyAction {
                target: charShape
                property: "shape"
                value: MaterialShape.Circle
            }
            ParallelAnimation {
                Motion {
                    target: charShape
                    property: "scale"
                    to: 2 / 3
                    type: "fastSpatial"
                }
                Motion {
                    target: char
                    property: "implicitWidth"
                    to: charList.implicitHeight
                    type: "defaultEffects"
                }
                PropertyAction {
                    target: char
                    property: "nonAnimWidthScale"
                    value: 1
                }
            }
        }

        SequentialAnimation {
            id: removeAnim

            PropertyAction {
                target: char
                property: "ListView.delayRemove"
                value: true
            }
            ParallelAnimation {
                Motion {
                    target: char
                    property: "opacity"
                    to: 0
                    type: "defaultEffects"
                }
                Motion {
                    target: char
                    property: "scale"
                    to: 0.5
                }
            }
            PropertyAction {
                target: char
                property: "ListView.delayRemove"
                value: false
            }
        }

        MaterialShape {
            id: charShape

            anchors.centerIn: parent
            implicitSize: charList.implicitHeight * 1.5
            shape: root.shapeQueue[char.index % root.shapeQueue.length] ?? MaterialShape.Circle
            color: root.colour
            opacity: root.showPassword ? 0 : 1

            Behavior on opacity {
                Motion {
                    type: "defaultEffects"
                }
            }
        }

        Text {
            anchors.centerIn: parent
            text: root.shown[char.index] ?? ""
            color: root.colour
            font.family: "Google Sans Flex"
            font.pointSize: 12
            opacity: root.showPassword ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                Motion {
                    type: "defaultEffects"
                }
            }
        }
    }
}
