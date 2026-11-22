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
    readonly property real prominence: down ? .96 : hovered ? .76 : checked || highlighted ? .54 : .12
    readonly property color activeAccent: MaterialTheme.safeAccent(MaterialTheme.forcedAccent || accent, materialPalette.light)
    readonly property color displayAccent: hovered || down
        ? MaterialTheme.mix(activeAccent, materialPalette.light ? "#2d124c" : "#ffffff", .24, 1)
        : activeAccent
    readonly property color fillColor: down ? MaterialTheme.mix(activeAccent, "#000000", .15, 1)
        : hovered || visualFocus ? MaterialTheme.mix(activeAccent, "#ffffff", .17, 1) : activeAccent
    readonly property color fillInk: MaterialTheme.relativeLuminance(fillColor) < .179 ? "#ffffff" : "#080a12"

    hoverEnabled: true
    font.pixelSize: 13
    topPadding: 7
    bottomPadding: 7
    leftPadding: 13
    rightPadding: 13
    implicitWidth: Math.max(35, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(32, implicitContentHeight + topPadding + bottomPadding)
    palette.buttonText: filled ? fillInk : materialPalette.text
    palette.highlightedText: filled ? fillInk : materialPalette.text
    icon.color: filled ? fillInk : displayAccent

    background: Item {
        GlassSurface {
            anchors.fill: parent
            visible: !control.filled
            material: control.material
            role: "button"
            radius: Math.min(10, control.materialPalette.radius)
            accent: control.displayAccent
            emphasis: control.prominence
            opacity: control.enabled ? 1 : .59
        }
        Rectangle {
            anchors.fill: parent
            visible: control.filled
            radius: Math.min(10, control.materialPalette.radius)
            color: control.fillColor
            opacity: control.enabled ? 1 : .47
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            color: "transparent"
            radius: 5
            border.width: 2
            border.color: control.filled ? control.fillInk : control.materialPalette.text
            visible: control.visualFocus
        }
    }
}
