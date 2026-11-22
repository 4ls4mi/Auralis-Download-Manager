pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window

Item {
    id: root

    required property Window hostWindow
    property int borderSize: 5
    property int cornerSize: 9

    visible: hostWindow.visibility !== Window.Maximized && hostWindow.visibility !== Window.FullScreen

    Repeater {
        model: [
            {edges: Qt.TopEdge, horizontal: true, trailing: false},
            {edges: Qt.BottomEdge, horizontal: true, trailing: true},
            {edges: Qt.LeftEdge, horizontal: false, trailing: false},
            {edges: Qt.RightEdge, horizontal: false, trailing: true}
        ]
        delegate: MouseArea {
            required property var modelData
            width: modelData.horizontal ? root.width - 2 * root.cornerSize : root.borderSize
            height: modelData.horizontal ? root.borderSize : root.height - 2 * root.cornerSize
            x: modelData.horizontal ? root.cornerSize : modelData.trailing ? root.width - width : 0
            y: modelData.horizontal ? modelData.trailing ? root.height - height : 0 : root.cornerSize
            cursorShape: modelData.horizontal ? Qt.SizeVerCursor : Qt.SizeHorCursor
            onPressed: root.hostWindow.startSystemResize(modelData.edges)
        }
    }
    Repeater {
        model: [
            {edges: Qt.TopEdge | Qt.LeftEdge, right: false, bottom: false, cursor: Qt.SizeFDiagCursor},
            {edges: Qt.TopEdge | Qt.RightEdge, right: true, bottom: false, cursor: Qt.SizeBDiagCursor},
            {edges: Qt.BottomEdge | Qt.LeftEdge, right: false, bottom: true, cursor: Qt.SizeBDiagCursor},
            {edges: Qt.BottomEdge | Qt.RightEdge, right: true, bottom: true, cursor: Qt.SizeFDiagCursor}
        ]
        delegate: MouseArea {
            required property var modelData
            width: root.cornerSize
            height: root.cornerSize
            x: modelData.right ? root.width - width : 0
            y: modelData.bottom ? root.height - height : 0
            cursorShape: modelData.cursor
            onPressed: root.hostWindow.startSystemResize(modelData.edges)
        }
    }
}
