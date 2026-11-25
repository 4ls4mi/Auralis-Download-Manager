pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Window

ApplicationWindow {
    id: window

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

    Component.onCompleted: Qt.callLater(refreshFrameShape)
    onFrameCornerMaskChanged: Qt.callLater(refreshFrameShape)
    onFrameCornerRadiusChanged: Qt.callLater(refreshFrameShape)

    Connections {
        target: window
        function onWidthChanged() { Qt.callLater(window.refreshFrameShape) }
        function onHeightChanged() { Qt.callLater(window.refreshFrameShape) }
        function onVisibleChanged() { Qt.callLater(window.refreshFrameShape) }
        function onScreenChanged() { Qt.callLater(window.refreshFrameShape) }
    }

    Binding on font {
        when: window.fontSettings !== null
        value: window.fontSettings?.interfaceFont
    }

    Binding {
        target: window.contentItem
        property: "scale"
        value: window.interfaceScale
    }
    Binding {
        target: window.contentItem
        property: "transformOrigin"
        value: Item.TopLeft
    }
    Binding {
        target: window.contentItem
        property: "width"
        value: window.width / window.interfaceScale
    }
    Binding {
        target: window.contentItem
        property: "height"
        value: window.height / window.interfaceScale
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
