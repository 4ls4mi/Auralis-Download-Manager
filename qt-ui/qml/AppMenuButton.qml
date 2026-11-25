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
    readonly property var profile: MaterialTheme.palette
    readonly property var classic: profile.mdm
    readonly property color menuBarFace: profile.menuOverride || classic?.menubar || profile.roleFaces?.toolbar
        || profile.background
    readonly property color classicFace: !emphasized ? "transparent"
        : customTint || (down || menuOpen ? classic?.menubarOpen || colors.pressed
            : classic?.menubarHot || colors.highlight)
    readonly property color classicInk: MaterialTheme.controlTextInk(
        profile.textOverride || classic?.text || idleInk,
        MaterialTheme.mix(menuBarFace, classicFace, classicFace.a, 1))
    readonly property var finish: MaterialTheme.buttonFinishes[profile.finish]
    readonly property bool emphasized: enabled && (hovered || visualFocus || down || menuOpen)
    readonly property string customTint: MaterialTheme.buttonColorOverride(MaterialTheme.current, accent)
    readonly property bool customized: Boolean(customTint || profile.menuOverride || profile.textOverride || profile.contentOverride)
    readonly property color actionAccent: customTint || MaterialTheme.vividControlAccent(MaterialTheme.forcedAccent || accent,
        profile.light)
    readonly property color pigment: customTint || MaterialTheme.controlPigment(actionAccent, profile.secondary, finish.tint)
    readonly property real idleStrength: MaterialTheme.controlIdleStrength(profile, finish)
    readonly property color idleFace: MaterialTheme.mix(colors.surface, pigment, idleStrength * .79, 1)
    readonly property color face: MaterialTheme.controlHighlight(pigment, down, hovered || visualFocus)
    readonly property color activeInk: customized
        ? MaterialTheme.controlTextInk(profile.textOverride || colors.ink, face) : MaterialTheme.contrastInk(face)
    readonly property color restingInk: customized
        ? MaterialTheme.controlTextInk(profile.textOverride || idleInk, idleFace) : idleInk

    hoverEnabled: true
    leftPadding: classic ? 8 : 11
    rightPadding: classic ? 8 : 11
    topPadding: classic ? 3 : 4
    bottomPadding: classic ? 3 : 5
    font.pixelSize: TypographyScale.pixels(classic ? 13 : 14)
    font.weight: classic ? Font.Normal : Font.Medium
    palette.buttonText: railIcon.length ? "transparent" : classic ? classicInk : emphasized ? activeInk : restingInk
    palette.highlightedText: classic ? classicInk : activeInk
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
        relief: button.enabled
        surface: button.emphasized ? button.face : button.idleFace
        ink: !button.enabled && !button.customized ? button.colors.muted
            : MaterialTheme.controlIconInk(button.enabled ? button.actionAccent : button.colors.muted, surface)
    }

    background: Item {
        implicitHeight: button.classic ? 23 : 29

        Rectangle {
            id: menuFace
            anchors.fill: parent
            anchors.margins: 1
            radius: button.classic ? Math.min(4, button.profile.buttonRadius || 0) : Math.min(8, button.profile.radius)
            color: button.classic ? button.classicFace : "transparent"
            gradient: button.classic ? null : modernGradient
            Gradient {
                id: modernGradient
                GradientStop {
                    position: 0
                    color: button.emphasized ? MaterialTheme.mix(button.face, button.profile.upper, button.finish.crown * .45, 1)
                        : MaterialTheme.rgba(button.pigment, button.idleStrength)
                }
                GradientStop {
                    position: button.finish.shoulder
                    color: button.emphasized ? button.face : MaterialTheme.rgba(button.pigment, button.idleStrength * .79)
                }
                GradientStop {
                    position: .71
                    color: button.emphasized ? button.face : MaterialTheme.rgba(button.pigment, button.idleStrength * .71)
                }
                GradientStop {
                    position: 1
                    color: button.emphasized ? MaterialTheme.mix(button.face, button.profile.shade, button.finish.depth, 1)
                        : MaterialTheme.rgba(button.pigment, button.idleStrength * .57)
                }
            }
            border.width: button.visualFocus ? 1 : 0
            border.color: button.classic ? MaterialTheme.controlIconInk(
                button.classic.focusRing || button.profile.accent, button.classicFace.a > 0 ? button.classicFace : button.menuBarFace)
                : button.activeInk
        }

        ButtonLighting {
            anchors.fill: menuFace
            visible: !button.classic
            radius: menuFace.radius
            accent: button.actionAccent
            emphasized: button.emphasized
            pressed: button.down
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: !button.classic && button.emphasized ? Math.max(0, parent.width - 16) : 0
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
