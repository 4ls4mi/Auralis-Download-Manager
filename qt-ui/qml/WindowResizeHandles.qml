pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window

Item {
    id: root

    required property Window hostWindow
    property int borderSize: 7
    property int cornerSize: 13
    property bool windowMouseEvents: false
    property bool showGrip: false
    property color gripColor: "white"

    // ApplicationWindow's content item is inset by the header and footer.
    parent: hostWindow.contentItem.parent ?? hostWindow.contentItem
    anchors.fill: parent
    z: 20
    objectName: "windowResizeHandles"
    visible: hostWindow.visibility === Window.Windowed

    Component.onCompleted: {
        if (windowMouseEvents && Qt.platform.os === "windows")
            engine.installInteractiveResize(hostWindow, borderSize, cornerSize)
    }

    Item {
        visible: root.showGrip
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: root.cornerSize
        height: root.cornerSize
        Accessible.ignored: true

        Repeater {
            model: [4, 8, 12]
            Rectangle {
                required property int modelData
                width: modelData * Math.SQRT2
                height: 1
                x: parent.width - 4 - (width + modelData) / 2
                y: parent.height - 4 - modelData / 2
                rotation: -45
                color: root.gripColor
                opacity: .64
                antialiasing: true
            }
        }
    }

    component ResizeArea: MouseArea {
        id: resizeArea

        required property int edges
        property bool manualResize: false
        property point startPosition
        property rect startGeometry

        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        preventStealing: true

        onPressed: mouse => {
            const window = root.hostWindow
            // Windows frameless HWNDs lack WS_THICKFRAME. Qt's native API
            // reports success after posting a system command the frame cannot honor.
            const framelessWindows = Qt.platform.os === "windows" && (window.flags & Qt.FramelessWindowHint)
            startPosition = mapToGlobal(mouse.x, mouse.y)
            startGeometry = Qt.rect(window.x, window.y, window.width, window.height)
            manualResize = framelessWindows || !window.startSystemResize(edges)
        }

        onPositionChanged: mouse => {
            if (!pressed || !manualResize)
                return

            const window = root.hostWindow
            const position = mapToGlobal(mouse.x, mouse.y)
            const dx = Math.round(position.x - startPosition.x)
            const dy = Math.round(position.y - startPosition.y)
            const left = edges & Qt.LeftEdge
            const top = edges & Qt.TopEdge
            const horizontal = edges & (Qt.LeftEdge | Qt.RightEdge)
            const vertical = edges & (Qt.TopEdge | Qt.BottomEdge)
            const width = horizontal
                ? Math.max(window.minimumWidth, Math.min(window.maximumWidth, startGeometry.width + (left ? -dx : dx)))
                : startGeometry.width
            const height = vertical
                ? Math.max(window.minimumHeight, Math.min(window.maximumHeight, startGeometry.height + (top ? -dy : dy)))
                : startGeometry.height

            window.setGeometry(startGeometry.x + (left ? startGeometry.width - width : 0),
                               startGeometry.y + (top ? startGeometry.height - height : 0),
                               width, height)
        }

        onReleased: manualResize = false
        onCanceled: manualResize = false
    }

    Repeater {
        model: [
            {edges: Qt.TopEdge, horizontal: true, trailing: false},
            {edges: Qt.BottomEdge, horizontal: true, trailing: true},
            {edges: Qt.LeftEdge, horizontal: false, trailing: false},
            {edges: Qt.RightEdge, horizontal: false, trailing: true}
        ]
        delegate: ResizeArea {
            required property var modelData
            edges: modelData.edges
            width: modelData.horizontal ? root.width - 2 * root.cornerSize : root.borderSize
            height: modelData.horizontal ? root.borderSize : root.height - 2 * root.cornerSize
            x: modelData.horizontal ? root.cornerSize : modelData.trailing ? root.width - width : 0
            y: modelData.horizontal ? modelData.trailing ? root.height - height : 0 : root.cornerSize
            cursorShape: modelData.horizontal ? Qt.SizeVerCursor : Qt.SizeHorCursor
        }
    }
    Repeater {
        model: [
            {edges: Qt.TopEdge | Qt.LeftEdge, right: false, bottom: false, cursor: Qt.SizeFDiagCursor},
            {edges: Qt.TopEdge | Qt.RightEdge, right: true, bottom: false, cursor: Qt.SizeBDiagCursor},
            {edges: Qt.BottomEdge | Qt.LeftEdge, right: false, bottom: true, cursor: Qt.SizeBDiagCursor},
            {edges: Qt.BottomEdge | Qt.RightEdge, right: true, bottom: true, cursor: Qt.SizeFDiagCursor}
        ]
        delegate: ResizeArea {
            required property var modelData
            edges: modelData.edges
            width: root.cornerSize
            height: root.cornerSize
            x: modelData.right ? root.width - width : 0
            y: modelData.bottom ? root.height - height : 0
            cursorShape: modelData.cursor
        }
    }
}
