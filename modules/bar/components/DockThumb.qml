import QtQuick
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.services

// One file of the file dock: its picture (images) or an icon, rounded. Dragging it hands the
// file to whatever app it is dropped on (as a file link, like dragging from a file manager).
Item {
    id: root

    required property string path
    property real radius: Tokens.rounding.small
    property bool draggable: true
    readonly property bool image: FileDock.isImage(path)
    readonly property bool dragging: handler.active
    // Small picture of this item, used as the drag cursor (made once the item has loaded).
    property url dragImage

    function grabDragImage(): void {
        if (tile.width > 0 && tile.height > 0)
            tile.grabToImage(r => root.dragImage = r.url, Qt.size(Math.round(tile.width * 1.5), Math.round(tile.height * 1.5)));
    }

    Drag.active: handler.active
    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.CopyAction | Qt.LinkAction
    Drag.proposedAction: Qt.CopyAction
    Drag.mimeData: ({
            "text/uri-list": FileDock.urlFor(root.path) + "\r\n",
            "text/plain": root.path
        })
    Drag.imageSource: dragImage
    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: height / 2
    Drag.onDragFinished: FileDock.dragging = false

    onPathChanged: dragImage = ""

    ClippingRectangle {
        id: tile

        anchors.fill: parent
        radius: root.radius
        color: Colours.palette.m3surfaceContainerHighest

        Component.onCompleted: {
            if (!root.image)
                Qt.callLater(root.grabDragImage);
        }

        Image {
            id: picture

            anchors.fill: parent
            visible: root.image && status === Image.Ready
            source: root.image ? FileDock.urlFor(root.path) : ""
            sourceSize.width: Math.ceil(root.width * 2)
            sourceSize.height: Math.ceil(root.height * 2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true

            onStatusChanged: {
                if (status === Image.Ready)
                    Qt.callLater(root.grabDragImage);
            }
        }

        MaterialIcon {
            anchors.centerIn: parent
            visible: !picture.visible
            text: FileDock.iconFor(root.path)
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.builders.small.size(Math.max(10, Math.round(Math.min(root.width, root.height) * 0.34))).build()
        }
    }

    DragHandler {
        id: handler

        enabled: root.draggable
        target: null
        onActiveChanged: FileDock.dragging = active
    }
}
