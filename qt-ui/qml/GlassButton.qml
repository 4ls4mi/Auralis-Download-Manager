pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Basic

Basic.Button {
    id: control

    property string material: MaterialTheme.current
    property bool danger: false
    property color accent: danger ? materialPalette.destructive : materialPalette.accent
    readonly property var materialPalette: MaterialTheme.profile(material)
    readonly property real prominence: down ? .80 : hovered ? .47 : checked || highlighted ? .32 : .10

    hoverEnabled: true
    font.pixelSize: 13
    topPadding: 7
    bottomPadding: 7
    leftPadding: 13
    rightPadding: 13
    implicitWidth: Math.max(35, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(32, implicitContentHeight + topPadding + bottomPadding)
    palette.buttonText: materialPalette.text
    palette.highlightedText: materialPalette.text
    icon.color: accent

    background: Item {
        GlassSurface {
            anchors.fill: parent
            material: control.material
            role: "button"
            radius: Math.min(10, control.materialPalette.radius)
            accent: control.accent
            emphasis: control.prominence
            opacity: control.enabled ? 1 : .52
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            color: "transparent"
            radius: 5
            border.width: 2
            border.color: control.materialPalette.text
            visible: control.visualFocus
        }
    }
}
