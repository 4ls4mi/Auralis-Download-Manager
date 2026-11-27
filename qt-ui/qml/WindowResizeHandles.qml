pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window

Item {
    id: root

    required property Window hostWindow
    property int borderSize: 7
    property int cornerSize: 13
    property bool windowMouseEvents: false
    // Batch manual resize updates for every window using these handles.
    property bool coalesceGeometry: true
    property bool showGrip: false
    property color gripColor: "white"
    readonly property int shapedCornerOffset: hostWindow["frameResizeInset"] ?? 0
    readonly property int handleCornerSize: Math.min(cornerSize + shapedCornerOffset,
        Math.floor(Math.min(width, height) / 2))
    readonly property bool resizing: activeHandle !== null || pendingSystemResizeEdges !== 0
    property Item activeHandle: null
    property rect pendingGeometry
    property int pendingSystemResizeEdges: 0
    property size pendingSystemResizeStart
    signal resizeFinished(size previousSize, size currentSize, int edges)

    // ApplicationWindow's content item is inset by the header and footer.
    parent: hostWindow.contentItem.parent ?? hostWindow.contentItem
    anchors.fill: parent
    z: 20
    objectName: "windowResizeHandles"
    visible: hostWindow.visibility === Window.Windowed
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    onVisibleChanged: if (!visible) {
        if (activeHandle)
            finishResize(activeHandle, false)
        finishSystemResize(false)
    }

    function queueResize(geometry) {
        pendingGeometry = geometry
        if (coalesceGeometry) {
            if (!resizeFrame.running)
                resizeFrame.start()
        } else {
            applyResize()
        }
    }

    function applyResize() {
        if (!activeHandle)
            return
        const window = hostWindow
        const geometry = pendingGeometry
        if (window.x !== geometry.x || window.y !== geometry.y
            || window.width !== geometry.width || window.height !== geometry.height)
            window.setGeometry(geometry.x, geometry.y, geometry.width, geometry.height)
    }

    function finishResize(handle, completed) {
        if (activeHandle !== handle)
            return
        if (resizeFrame.running) {
            resizeFrame.stop()
            if (completed)
                applyResize()
        }
        activeHandle = null
        if (completed)
            reportResize(Qt.size(handle.startGeometry.width, handle.startGeometry.height), handle.edges)
    }

    function reportResize(previousSize, edges) {
        const window = hostWindow
        if (window.visibility === Window.Windowed
            && (window.width !== previousSize.width || window.height !== previousSize.height))
            resizeFinished(previousSize, Qt.size(window.width, window.height), edges)
    }

    function beginSystemResize(previousSize, edges) {
        pendingSystemResizeStart = previousSize
        pendingSystemResizeEdges = edges
        // A compositor can take the pointer grab without reporting its release to Qt Quick.
        systemResizeSettled.interval = 1500
        systemResizeSettled.restart()
    }

    function trackSystemResize() {
        const window = hostWindow
        const edges = pendingSystemResizeEdges
        if (((edges & (Qt.LeftEdge | Qt.RightEdge)) && window.width !== pendingSystemResizeStart.width)
            || ((edges & (Qt.TopEdge | Qt.BottomEdge)) && window.height !== pendingSystemResizeStart.height)) {
            systemResizeSettled.interval = 240
            systemResizeSettled.restart()
        }
    }

    function finishSystemResize(completed) {
        if (!pendingSystemResizeEdges)
            return
        const edges = pendingSystemResizeEdges
        pendingSystemResizeEdges = 0
        systemResizeSettled.stop()
        if (completed)
            reportResize(pendingSystemResizeStart, edges)
    }

    Timer {
        id: resizeFrame
        interval: 16
        onTriggered: root.applyResize()
    }

    Timer {
        id: systemResizeSettled
        onTriggered: root.finishSystemResize(true)
    }

    Connections {
        target: root.hostWindow
        enabled: root.pendingSystemResizeEdges !== 0
        ignoreUnknownSignals: true
        function onWidthChanged() { root.trackSystemResize() }
        function onHeightChanged() { root.trackSystemResize() }
        function onScreenChanged() { root.finishSystemResize(false) }
        function onInterfaceScaleChanged() { root.finishSystemResize(false) }
    }

    Component.onCompleted: {
        if (Qt.platform.os === "windows" && typeof engine !== "undefined") {
            engine.observeNativeResize?.(hostWindow)
            if (windowMouseEvents)
                engine.installInteractiveResize(hostWindow, borderSize, cornerSize)
        }
    }

    Connections {
        target: Qt.platform.os === "windows" && typeof engine !== "undefined" ? engine : null
        ignoreUnknownSignals: true
        function onWindowResizeFinished(window, previousSize, currentSize, edges) {
            if (window === root.hostWindow)
                root.resizeFinished(previousSize, currentSize, edges)
        }
    }

    Item {
        visible: root.showGrip
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: root.shapedCornerOffset
        anchors.bottomMargin: root.shapedCornerOffset
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
            root.finishSystemResize(true)
            startPosition = mapToGlobal(mouse.x, mouse.y)
            startGeometry = Qt.rect(window.x, window.y, window.width, window.height)
            manualResize = framelessWindows || !window.startSystemResize(edges)
            if (manualResize)
                root.activeHandle = resizeArea
            else if (Qt.platform.os !== "windows") {
                root.beginSystemResize(Qt.size(startGeometry.width, startGeometry.height), edges)
                root.trackSystemResize()
            }
        }

        function moveEdge(pointerX, pointerY) {
            const window = root.hostWindow
            const position = mapToGlobal(pointerX, pointerY)
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

            root.queueResize(Qt.rect(startGeometry.x + (left ? startGeometry.width - width : 0),
                                     startGeometry.y + (top ? startGeometry.height - height : 0),
                                     width, height))
        }

        onPositionChanged: mouse => {
            if (pressed && manualResize && root.activeHandle === resizeArea)
                moveEdge(mouse.x, mouse.y)
        }

        onReleased: mouse => {
            if (manualResize && root.activeHandle === resizeArea)
                moveEdge(mouse.x, mouse.y)
            if (manualResize)
                root.finishResize(resizeArea, true)
            else if (root.pendingSystemResizeEdges)
                root.trackSystemResize()
            manualResize = false
        }

        onCanceled: {
            root.finishResize(resizeArea, false)
            manualResize = false
        }
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
            width: modelData.horizontal ? root.width - 2 * root.handleCornerSize : root.borderSize
            height: modelData.horizontal ? root.borderSize : root.height - 2 * root.handleCornerSize
            x: modelData.horizontal ? root.handleCornerSize : modelData.trailing ? root.width - width : 0
            y: modelData.horizontal ? modelData.trailing ? root.height - height : 0 : root.handleCornerSize
            cursorShape: modelData.horizontal ? Qt.SizeVerCursor : Qt.SizeHorCursor
        }
    }
    Repeater {
        model: [
            {edges: Qt.TopEdge | Qt.LeftEdge, right: false, bottom: false, cursor: Qt.SizeFDiagCursor},
            {edges: Qt.TopEdge | Qt.RightEdge, right: true, bottom: false, cursor: Qt.SizeBDiagCursor},
            {edges: Qt.BottomEdge | Qt.LeftEdge, right: false, bottom: true, cursor: Qt.SizeBDiagCursor}
        ]
        delegate: ResizeArea {
            required property var modelData
            edges: modelData.edges
            width: root.handleCornerSize
            height: root.handleCornerSize
            x: modelData.right ? root.width - width : 0
            y: modelData.bottom ? root.height - height : 0
            cursorShape: modelData.cursor
        }
    }

    ResizeArea {
        objectName: "bottomRightResizeHandle"
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        edges: Qt.BottomEdge | Qt.RightEdge
        width: root.handleCornerSize
        height: root.handleCornerSize
        cursorShape: Qt.SizeFDiagCursor
    }
}
