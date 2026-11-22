pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window

MouseArea {
    id: root

    required property Window hostWindow
    property point origin
    property bool moving: false
    signal doubleClickRequested()

    acceptedButtons: Qt.LeftButton

    onPressed: mouse => {
        origin = Qt.point(mouse.x, mouse.y)
        moving = false
    }
    onPositionChanged: mouse => {
        if (pressed && !moving && Math.abs(mouse.x - origin.x) + Math.abs(mouse.y - origin.y) >= 6) {
            moving = true
            hostWindow.startSystemMove()
        }
    }
    onDoubleClicked: doubleClickRequested()
}
