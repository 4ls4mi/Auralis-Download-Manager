pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic

Basic.MenuItem {
    id: item

    property string symbol: ""
    property color commandColor: symbol.length
        ? MaterialTheme.actionColor(symbol, MaterialTheme.palette.light) : MaterialTheme.menuColors.icon
    property bool destructive: false
    readonly property var colors: MaterialTheme.menuColors
    readonly property var profile: MaterialTheme.palette
    readonly property var finish: MaterialTheme.buttonFinishes[profile.finish]
    readonly property bool selected: enabled && (highlighted || hovered || activeFocus || down)
    readonly property color actionAccent: MaterialTheme.vividControlAccent(MaterialTheme.forcedAccent
        || (destructive ? colors.danger : symbol.length ? commandColor : colors.highlight), profile.light)
    readonly property color pigment: MaterialTheme.controlPigment(actionAccent, profile.secondary, finish.tint)
    readonly property real idleStrength: MaterialTheme.controlIdleStrength(profile, finish) * .42
    readonly property color idleFace: MaterialTheme.mix(colors.surface, pigment, idleStrength * .78, 1)
    readonly property color face: MaterialTheme.controlHighlight(pigment, down, hovered)
    readonly property color activeInk: MaterialTheme.contrastInk(face)
    readonly property real glyphSpace: symbol.length ? 27 : 0
    readonly property string shortcutText: subMenu ? "" : menuShortcut.nativeText
    readonly property real shortcutSpace: shortcutText.length ? shortcutBadge.width + 9 : 0
    readonly property color foreground: !enabled ? colors.muted : selected ? activeInk
        : MaterialTheme.controlTextInk(destructive ? colors.danger : colors.ink, idleFace)

    hoverEnabled: true
    leftPadding: 12 + (mirrored ? shortcutSpace : glyphSpace)
    rightPadding: 12 + (mirrored ? glyphSpace : shortcutSpace)
    topPadding: 6
    bottomPadding: 6
    font.pixelSize: TypographyScale.pixels(14)
    font.weight: Font.Medium
    palette.windowText: foreground
    palette.text: foreground
    icon.color: !enabled ? colors.muted : MaterialTheme.controlIconInk(actionAccent, selected ? face : idleFace)

    Shortcut {
        id: menuShortcut
        enabled: false
        sequence: item.colors.showShortcuts && item.action ? item.action.shortcut : ""
    }

    background: Item {
        implicitWidth: 214
        implicitHeight: 35

        Rectangle {
            id: itemFace
            anchors.fill: parent
            anchors.topMargin: 1
            anchors.bottomMargin: 1
            radius: Math.min(9, item.profile.radius)
            visible: item.enabled
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: item.selected ? MaterialTheme.mix(item.face, item.profile.upper, item.finish.crown * .45, 1)
                        : MaterialTheme.rgba(item.pigment, item.idleStrength)
                }
                GradientStop {
                    position: item.finish.shoulder
                    color: item.selected ? item.face : MaterialTheme.rgba(item.pigment, item.idleStrength * .78)
                }
                GradientStop {
                    position: .71
                    color: item.selected ? item.face : MaterialTheme.rgba(item.pigment, item.idleStrength * .70)
                }
                GradientStop {
                    position: 1
                    color: item.selected ? MaterialTheme.mix(item.face, item.profile.shade, item.finish.depth, 1)
                        : MaterialTheme.rgba(item.pigment, item.idleStrength * .58)
                }
            }
        }

        ButtonLighting {
            anchors.fill: itemFace
            radius: itemFace.radius
            accent: item.actionAccent
            emphasized: item.selected
            pressed: item.down
        }

        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 6
            anchors.bottomMargin: 6
            x: item.mirrored ? parent.width - width - 2 : 2
            width: item.selected ? 3 : 0
            radius: 1.5
            color: item.activeInk

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
                font.pixelSize: TypographyScale.pixels(11)
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
            relief: item.enabled
            surface: item.selected ? item.face : item.idleFace
            ink: !item.enabled ? item.colors.muted
                : MaterialTheme.controlIconInk(item.actionAccent, surface)
        }
    }
}
