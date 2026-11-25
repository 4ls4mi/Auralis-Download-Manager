pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Basic

Basic.Switch {
    id: control

    property string material: MaterialTheme.current
    readonly property var profile: MaterialTheme.profile(material)
    readonly property color fieldColor: profile.roleFaces?.field || profile.background
    readonly property color idleTrack: MaterialTheme.mix(MaterialTheme.mix(fieldColor, profile.divider, .62, 1),
        palette.highlight, .13, 1)
    readonly property color selectedTrack: MaterialTheme.safeAccent(palette.highlight, profile.light)
    readonly property color trackColor: checked ? selectedTrack : idleTrack
    readonly property color thumbColor: MaterialTheme.controlTextInk(profile.text, trackColor)

    hoverEnabled: true
    palette.highlight: profile.accent
    palette.windowText: profile.text

    indicator: Item {
        implicitWidth: 56
        implicitHeight: 28
        x: control.text.length > 0
            ? (control.mirrored ? control.width - width - control.rightPadding : control.leftPadding)
            : control.leftPadding + (control.availableWidth - width) / 2
        y: control.topPadding + (control.availableHeight - height) / 2
        opacity: control.enabled ? 1 : .55

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: height / 2
            color: "transparent"
            visible: control.visualFocus
            border.width: 1.5
            border.color: MaterialTheme.controlIconInk(control.palette.highlight, control.fieldColor)
        }

        Rectangle {
            id: track
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            anchors.topMargin: 3
            anchors.bottomMargin: 3
            radius: height / 2
            border.width: control.checked ? 1.5 : 1
            border.color: control.checked ? control.palette.highlight
                : MaterialTheme.mix(control.trackColor, control.profile.ink, .42, 1)
            gradient: Gradient {
                GradientStop { position: 0; color: MaterialTheme.mix(control.trackColor, control.profile.upper, control.hovered ? .20 : .12, 1) }
                GradientStop { position: .45; color: control.trackColor }
                GradientStop { position: 1; color: MaterialTheme.mix(control.trackColor, control.profile.shade, .16, 1) }
            }
        }

        Rectangle {
            x: thumb.x
            y: thumb.y + 1.2
            width: thumb.width
            height: thumb.height
            radius: width / 2
            color: Qt.alpha(control.profile.shade, .64)
        }

        Rectangle {
            id: thumb
            readonly property int inset: 3
            width: track.height - 2 * inset
            height: width
            radius: width / 2
            x: track.x + inset + control.visualPosition * (track.width - 2 * inset - width)
            y: track.y + inset
            gradient: Gradient {
                GradientStop { position: 0; color: MaterialTheme.mix(control.thumbColor, control.profile.upper, control.down ? .03 : .11, 1) }
                GradientStop { position: .58; color: control.thumbColor }
                GradientStop { position: 1; color: MaterialTheme.mix(control.thumbColor, control.profile.shade, .14, 1) }
            }

            Behavior on x {
                enabled: !control.down && !MaterialTheme.reducedMotion
                NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
            }
        }

        Text {
            anchors.fill: thumb
            visible: control.checked
            text: "✓"
            color: MaterialTheme.controlTextInk(control.profile.ink, control.thumbColor)
            font.pixelSize: 10
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
