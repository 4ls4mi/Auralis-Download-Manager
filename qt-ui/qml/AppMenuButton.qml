pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Basic

Basic.Button {
    id: button

    property bool menuOpen: false
    readonly property var colors: MaterialTheme.menuColors
    readonly property bool emphasized: enabled && (hovered || visualFocus || down || menuOpen)

    hoverEnabled: true
    leftPadding: 11
    rightPadding: 11
    topPadding: 4
    bottomPadding: 5
    font.pixelSize: 14
    font.weight: Font.Medium
    palette.buttonText: emphasized ? colors.highlightInk : colors.ink
    palette.highlightedText: colors.highlightInk

    background: Item {
        implicitHeight: 29

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 5
            color: button.down ? button.colors.pressed : button.colors.highlight
            visible: button.emphasized
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: button.emphasized ? Math.max(0, parent.width - 16) : 0
            height: 2
            radius: 1
            color: button.colors.rail

            Behavior on width {
                NumberAnimation {
                    duration: MaterialTheme.reducedMotion ? 0 : 140
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
