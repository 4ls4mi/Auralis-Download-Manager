pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic

Basic.MenuItem {
    id: item

    property string symbol: ""
    property color commandColor: MaterialTheme.menuColors.icon
    property bool destructive: false
    readonly property var colors: MaterialTheme.menuColors
    readonly property bool selected: enabled && (highlighted || hovered || activeFocus || down)
    readonly property real glyphSpace: symbol.length ? 27 : 0
    readonly property string shortcutText: subMenu ? "" : menuShortcut.nativeText
    readonly property real shortcutSpace: shortcutText.length ? shortcutBadge.width + 9 : 0
    readonly property color foreground: !enabled ? colors.muted : selected ? colors.highlightInk
        : destructive ? colors.danger : colors.ink

    hoverEnabled: true
    leftPadding: 12 + (mirrored ? shortcutSpace : glyphSpace)
    rightPadding: 12 + (mirrored ? glyphSpace : shortcutSpace)
    topPadding: 6
    bottomPadding: 6
    font.pixelSize: 14
    font.weight: Font.Medium
    palette.windowText: foreground
    palette.text: foreground
    icon.color: !enabled ? colors.muted : selected ? colors.highlightInk : item.commandColor

    Shortcut {
        id: menuShortcut
        enabled: false
        sequence: item.colors.showShortcuts && item.action ? item.action.shortcut : ""
    }

    background: Item {
        implicitWidth: 214
        implicitHeight: 35

        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 1
            anchors.bottomMargin: 1
            radius: item.colors.studio ? 9 : 6
            visible: item.selected
            color: item.down ? item.colors.pressed : item.colors.highlight
        }

        Loader {
            anchors.fill: parent
            anchors.margins: 2
            active: item.selected && item.colors.studio
            sourceComponent: GlassProgress {
                Accessible.ignored: true
                shape: "round"
                value: .95
                animated: true
                opacity: item.colors.showShortcuts ? .16 : .31
                startColor: item.colors.highlight
                endColor: item.colors.rail
                trackColor: "transparent"
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: item.selected ? (item.mirrored ? 8 : parent.width - width - 8)
                             : (item.mirrored ? parent.width - width - 8 : 8)
            width: Math.min(68, parent.width * .3)
            height: Math.max(0, parent.height - 5)
            radius: 5
            color: "transparent"
            visible: item.selected && !MaterialTheme.reducedMotion
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: .55; color: "#25ffffff" }
                GradientStop { position: 1; color: "transparent" }
            }

            Behavior on x {
                enabled: item.selected && !MaterialTheme.reducedMotion
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
        }

        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 6
            anchors.bottomMargin: 6
            x: item.mirrored ? parent.width - width - 2 : 2
            width: item.selected ? 3 : 0
            radius: 1.5
            color: item.colors.rail

            Behavior on width {
                NumberAnimation {
                    duration: MaterialTheme.reducedMotion ? 0 : 140
                    easing.type: Easing.OutCubic
                }
            }
        }

        Rectangle {
            id: shortcutBadge

            width: shortcutLabel.implicitWidth + 10
            height: shortcutLabel.implicitHeight + 3
            x: item.mirrored ? 12 : parent.width - width - 12
            anchors.verticalCenter: parent.verticalCenter
            radius: 4
            color: MaterialTheme.rgba(item.foreground, item.selected ? .17 : .08)
            visible: Boolean(item.shortcutText)

            Label {
                id: shortcutLabel
                anchors.centerIn: parent
                text: item.shortcutText
                font.pixelSize: 11
                color: item.foreground
                Accessible.ignored: true
            }
        }

        DashboardIcon {
            visible: item.symbol.length > 0
            width: 17
            height: 17
            x: item.mirrored ? parent.width - width - 12 : 12
            anchors.verticalCenter: parent.verticalCenter
            symbol: item.symbol
            bold: true
            ink: !item.enabled ? item.colors.muted : item.selected ? item.colors.highlightInk
                : item.destructive ? item.colors.danger : item.commandColor
        }
    }
}
