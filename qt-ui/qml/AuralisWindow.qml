pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Window

ApplicationWindow {
    id: window

    LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    readonly property var fontSettings: typeof typography === "undefined" ? null : typography
    readonly property int frameCornerRadius: visibility === Window.Windowed ? 12 : 0

    function refreshFrameShape() {
        if (visible && typeof engine !== "undefined")
            engine.setWindowCornerRadius?.(window, frameCornerRadius)
    }

    Component.onCompleted: Qt.callLater(refreshFrameShape)
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

    function fontFamilyForText(text) {
        if (!fontSettings || (!fontSettings.englishFamily && !fontSettings.arabicFamily))
            return font.family
        return fontSettings.fontForText(text).family || font.family
    }
}
