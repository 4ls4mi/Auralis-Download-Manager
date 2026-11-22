pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window

MouseArea {
    id: root

    required property Window hostWindow
    property bool allowManualMove: false
    property point origin
    property point pointerOrigin
    property point windowOrigin
    property bool moving: false
    readonly property bool dragging: pressed && moving
    property bool manualMoving: false
    signal doubleClickRequested()

    acceptedButtons: Qt.LeftButton

    onPressed: mouse => {
        origin = Qt.point(mouse.x, mouse.y)
        pointerOrigin = mapToGlobal(mouse.x, mouse.y)
        windowOrigin = Qt.point(hostWindow.x, hostWindow.y)
        moving = false
        manualMoving = false
    }
    onPositionChanged: mouse => {
        if (!pressed)
            return
        if (!moving && Math.abs(mouse.x - origin.x) + Math.abs(mouse.y - origin.y) >= 6) {
            moving = true
            if (!hostWindow.startSystemMove())
                manualMoving = allowManualMove && hostWindow.visibility === Window.Windowed
        }
        if (manualMoving) {
            const position = mapToGlobal(mouse.x, mouse.y)
            hostWindow.setGeometry(Math.round(windowOrigin.x + position.x - pointerOrigin.x),
                                   Math.round(windowOrigin.y + position.y - pointerOrigin.y),
                                   hostWindow.width, hostWindow.height)
        }
    }
    onReleased: manualMoving = false
    onCanceled: manualMoving = false
    onDoubleClicked: doubleClickRequested()
}
