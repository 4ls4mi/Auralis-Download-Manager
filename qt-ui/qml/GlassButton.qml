pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Basic

Basic.Button {
    id: control

    property string material: MaterialTheme.current
    property bool danger: false
    property bool filled: false
    property color accent: danger ? materialPalette.destructive : materialPalette.accent
    readonly property var materialPalette: MaterialTheme.profile(material)
    readonly property real prominence: .31
    readonly property color activeAccent: MaterialTheme.safeAccent(MaterialTheme.forcedAccent || accent, materialPalette.light)
    readonly property color displayAccent: hovered || down
        ? MaterialTheme.mix(activeAccent, materialPalette.light ? "#2d124c" : "#ffffff", .24, 1)
        : activeAccent
    readonly property bool accentFill: filled || enabled && (down || hovered || visualFocus || checked || highlighted)
    readonly property color fillColor: MaterialTheme.controlHighlight(activeAccent, down, hovered || visualFocus)
    readonly property color fillInk: MaterialTheme.contrastInk(fillColor)
    readonly property color buttonInk: accentFill ? fillInk : materialPalette.text

    hoverEnabled: true
    font.pixelSize: 13
    topPadding: 7
    bottomPadding: 7
    leftPadding: 13
    rightPadding: 13
    implicitWidth: Math.max(35, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(32, implicitContentHeight + topPadding + bottomPadding)
    palette.buttonText: buttonInk
    palette.highlightedText: buttonInk
    icon.color: accentFill ? fillInk : displayAccent

    background: Item {
        GlassSurface {
            anchors.fill: parent
            visible: !control.accentFill
            material: control.material
            role: "button"
            radius: Math.min(10, control.materialPalette.radius)
            accent: control.displayAccent
            emphasis: control.prominence
            opacity: control.enabled ? 1 : .59
        }
        Rectangle {
            anchors.fill: parent
            visible: control.accentFill
            radius: Math.min(10, control.materialPalette.radius)
            color: control.fillColor
            opacity: control.enabled ? 1 : .47
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: control.visualFocus ? 2 : 0
            color: "transparent"
            radius: Math.max(3, Math.min(10, control.materialPalette.radius) - anchors.margins)
            border.width: control.visualFocus ? 2 : 1
            border.color: control.visualFocus ? control.buttonInk
                : MaterialTheme.rgba(control.activeAccent, control.enabled ? .57 : .25)
            visible: control.visualFocus || !control.accentFill
        }
    }
}
