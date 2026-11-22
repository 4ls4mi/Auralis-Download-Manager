pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic

Basic.Button {
    id: button

    property bool menuOpen: false
    property string railIcon: ""
    property color idleInk: colors.ink
    property color accent: colors.highlight
    readonly property var colors: MaterialTheme.menuColors
    readonly property bool emphasized: enabled && (hovered || visualFocus || down || menuOpen)
    readonly property color face: MaterialTheme.controlHighlight(MaterialTheme.forcedAccent || accent, down,
        hovered || visualFocus)
    readonly property color activeInk: MaterialTheme.contrastInk(face)

    hoverEnabled: true
    leftPadding: 11
    rightPadding: 11
    topPadding: 4
    bottomPadding: 5
    font.pixelSize: 14
    font.weight: Font.Medium
    palette.buttonText: railIcon.length ? "transparent" : emphasized ? activeInk : idleInk
    palette.highlightedText: activeInk
    Accessible.name: text.replace("&", "")
    ToolTip.visible: railIcon.length > 0 && hovered && !menuOpen
    ToolTip.text: Accessible.name
    ToolTip.delay: 400

    DashboardIcon {
        anchors.centerIn: parent
        width: 19
        height: 19
        visible: button.railIcon.length > 0
        symbol: button.railIcon
        ink: button.emphasized ? button.activeInk : button.idleInk
    }

    background: Item {
        implicitHeight: 29

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 5
            color: button.emphasized ? button.face : MaterialTheme.rgba(button.accent, .13)
            border.width: button.visualFocus ? 1 : 0
            border.color: button.activeInk
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: button.emphasized ? Math.max(0, parent.width - 16) : 0
            height: 2
            radius: 1
            color: button.activeInk

            Behavior on width {
                NumberAnimation {
                    duration: MaterialTheme.reducedMotion ? 0 : 140
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
