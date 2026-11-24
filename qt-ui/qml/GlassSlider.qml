pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Basic

Basic.Slider {
    id: control

    property string material: MaterialTheme.current
    readonly property var profile: MaterialTheme.profile(material)
    readonly property real thumbExtent: 28
    readonly property real grooveThickness: 7
    readonly property color fieldColor: profile.roleFaces?.field || profile.background
    readonly property color grooveColor: MaterialTheme.mix(fieldColor, profile.divider, .72, 1)
    readonly property color grooveEdge: MaterialTheme.controlIconInk(
        MaterialTheme.mix(profile.divider, palette.highlight, .24, 1), fieldColor)
    readonly property color fillColor: MaterialTheme.controlIconInk(palette.highlight, grooveColor)
    readonly property color thumbColor: MaterialTheme.controlTextInk(profile.buttonFace || profile.background, fillColor)

    hoverEnabled: true
    palette.highlight: profile.accent

    background: Rectangle {
        id: groove
        implicitWidth: control.horizontal ? 200 : control.grooveThickness
        implicitHeight: control.horizontal ? control.grooveThickness : 200
        width: control.horizontal ? Math.max(0, control.availableWidth - control.thumbExtent) : implicitWidth
        height: control.horizontal ? implicitHeight : Math.max(0, control.availableHeight - control.thumbExtent)
        x: control.leftPadding + (control.horizontal ? control.thumbExtent / 2 : (control.availableWidth - width) / 2)
        y: control.topPadding + (control.horizontal ? (control.availableHeight - height) / 2 : control.thumbExtent / 2)
        radius: control.grooveThickness / 2
        color: control.grooveColor
        border.color: control.grooveEdge
        opacity: control.enabled ? 1 : .55

        Rectangle {
            x: control.horizontal && control.mirrored ? groove.width - width : 0
            y: control.horizontal ? 0 : groove.height - height
            width: control.horizontal ? groove.width * control.position : groove.width
            height: control.horizontal ? groove.height : groove.height * control.position
            radius: Math.min(width, height) / 2
            color: control.fillColor
        }
    }

    handle: Item {
        id: thumb
        implicitWidth: control.thumbExtent
        implicitHeight: control.thumbExtent
        x: control.leftPadding + (control.horizontal ? control.visualPosition * (control.availableWidth - width)
            : (control.availableWidth - width) / 2)
        y: control.topPadding + (control.horizontal ? (control.availableHeight - height) / 2
            : control.visualPosition * (control.availableHeight - height))
        opacity: control.enabled ? 1 : .55

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            visible: control.visualFocus
            color: "transparent"
            border.width: 1.5
            border.color: MaterialTheme.controlIconInk(control.palette.highlight, control.profile.background)
            radius: width / 2
        }

        Rectangle {
            anchors.centerIn: parent
            width: control.pressed ? 17 : control.hovered ? 21 : 19
            height: width
            radius: width / 2
            color: control.thumbColor
            border.width: 2
            border.color: control.fillColor

            Behavior on width {
                enabled: !MaterialTheme.reducedMotion
                NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
            }
        }
    }
}
