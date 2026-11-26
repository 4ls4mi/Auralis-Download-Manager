pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Window

ApplicationWindow {
    id: window

    default property alias windowContent: scaledContent.data
    property alias scaledContentItem: scaledContent

    LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    readonly property var fontSettings: typeof typography === "undefined" ? null : typography
    readonly property real interfaceScale: (fontSettings?.interfaceScalePercent ?? 100) / 100
    readonly property var interfaceColors: MaterialTheme.palette
    palette.windowText: interfaceColors.text
    palette.text: interfaceColors.text
    palette.buttonText: interfaceColors.text
    palette.highlight: interfaceColors.accent
    property bool frameShapingEnabled: true
    readonly property int frameCornerMask: {
        if (!frameShapingEnabled || visibility !== Window.Windowed)
            return 0
        return ({square: 0, top: 3, bottom: 12, all: 15})[WindowAppearance.cornerPlacement]
    }
    readonly property int frameCornerRadius: frameCornerMask ? WindowAppearance.cornerRadius : 0
    readonly property int frameResizeInset: Math.ceil(frameCornerRadius * (1 - Math.pow(0.5, 1 / 3.05)))
    readonly property int frameSafeInset: {
        if (!frameCornerRadius || !(frameCornerMask & 3))
            return 0
        // Reserve room at both sides of a caption that starts at least 8 logical pixels from the edge.
        const rise = frameCornerRadius * 113 / 114
        const vertical = Math.max(0, 1 - 8 / rise)
        return 1 + Math.ceil(frameCornerRadius * (1 - Math.pow(1 - Math.pow(vertical, 3.05), 1 / 3.05)))
    }

    function refreshFrameShape() {
        if (visible && typeof engine !== "undefined")
            engine.setWindowCornerRadius?.(window, frameCornerRadius)
    }

    function scheduleFrameShapeRefresh() {
        frameShapeRefresh.restart()
    }

    Component.onCompleted: scheduleFrameShapeRefresh()
    onFrameCornerMaskChanged: scheduleFrameShapeRefresh()
    onFrameCornerRadiusChanged: scheduleFrameShapeRefresh()

    Timer {
        id: frameShapeRefresh
        interval: 16
        repeat: false
        onTriggered: window.refreshFrameShape()
    }

    Connections {
        target: window
        function onWidthChanged() { window.scheduleFrameShapeRefresh() }
        function onHeightChanged() { window.scheduleFrameShapeRefresh() }
        function onVisibleChanged() { window.scheduleFrameShapeRefresh() }
        function onScreenChanged() { window.scheduleFrameShapeRefresh() }
    }

    Binding on font {
        when: window.fontSettings !== null
        value: window.fontSettings?.interfaceFont
    }

    Item {
        id: scaledContent
        parent: window.contentItem
        x: 0
        y: 0
        width: parent ? parent.width / window.interfaceScale : 0
        height: parent ? parent.height / window.interfaceScale : 0
        scale: window.interfaceScale
        transformOrigin: Item.TopLeft
    }

    // A shallow highlight and inset rim give every application frame depth.
    Item {
        parent: window.contentItem.parent
        width: window.width
        height: window.height
        z: 100000
        visible: window.visibility === Window.Windowed
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, window.frameCornerRadius - 1)
            color: "transparent"
            border.width: 1
            border.color: window.interfaceColors.light ? "#65ffffff" : "#38ffffff"
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: Math.max(0, window.frameCornerRadius - 3)
            color: "transparent"
            border.width: 1
            border.color: "#35000000"
        }
    }

    function fontFamilyForText(text) {
        if (!fontSettings || (!fontSettings.englishFamily && !fontSettings.arabicFamily))
            return font.family
        return fontSettings.fontForText(text).family || font.family
    }

    function numeralInputFamily() {
        return fontSettings?.numeralInputFamily?.(font.family) || font.family
    }
}
