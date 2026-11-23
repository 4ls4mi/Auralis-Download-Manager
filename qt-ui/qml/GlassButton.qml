pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Basic
import QtQuick.Shapes
import "MaterialGeometry.js" as Geometry

Basic.Button {
    id: control

    property string material: MaterialTheme.current
    property bool danger: false
    property bool filled: false
    property color accent: danger ? materialPalette.destructive : materialPalette.accent
    readonly property var materialPalette: MaterialTheme.profile(material)
    readonly property color activeAccent: MaterialTheme.safeAccent(MaterialTheme.forcedAccent || accent, materialPalette.light)
    readonly property color vividAccent: MaterialTheme.vividControlAccent(activeAccent, materialPalette.light)
    readonly property color neutralFace: materialPalette.buttonFace || materialPalette.background
    readonly property color restingFace: MaterialTheme.mix(neutralFace, vividAccent,
        materialPalette.light ? .09 : .20, materialPalette.opaque ? 1 : .88)
    readonly property bool selectedFace: filled || checked || highlighted
    readonly property real accentStrength: down ? .47 : hovered ? .80 : visualFocus ? .70 : .63
    readonly property color engagedFace: MaterialTheme.mix(neutralFace, vividAccent, accentStrength, 1)
    readonly property bool accentFill: enabled && (selectedFace || hovered || down || visualFocus)
    readonly property color faceColor: accentFill ? engagedFace : restingFace
    readonly property color buttonInk: accentFill ? MaterialTheme.contrastInk(engagedFace) : materialPalette.text
    readonly property color iconInk: !enabled ? MaterialTheme.mix(materialPalette.muted, neutralFace, .36, 1)
        : accentFill ? MaterialTheme.mix(buttonInk, vividAccent, .19, 1)
        : MaterialTheme.controlIconInk(vividAccent, restingFace)
    property real faceOffset: enabled ? down ? 1.55 : hovered ? -.45 : 0 : 0

    hoverEnabled: true
    font.pixelSize: 13
    font.weight: Font.Medium
    topPadding: 7
    bottomPadding: 7
    leftPadding: 13
    rightPadding: 13
    implicitWidth: Math.max(35, implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(32, implicitContentHeight + topPadding + bottomPadding)
    palette.buttonText: buttonInk
    palette.brightText: buttonInk
    palette.highlightedText: buttonInk
    icon.color: iconInk

    Behavior on faceOffset {
        enabled: !MaterialTheme.reducedMotion
        NumberAnimation {
            duration: control.down ? 72 : 135
            easing.type: Easing.OutCubic
        }
    }

    background: Item {
        id: buttonBackground

        readonly property var profile: control.materialPalette
        readonly property real radius: Math.min(10, profile.radius)
        readonly property string outline: profile.softChrome ? "round" : profile.shape
        readonly property real gloss: profile.gloss
        readonly property real lip: .85 + gloss * .45
        readonly property color highlight: MaterialTheme.mix(profile.light ? "#ffffff" : profile.upper,
            control.vividAccent, control.accentFill ? .44 : .19, 1)
        readonly property color shade: profile.light ? "#31304b" : profile.shade
        readonly property color edge: MaterialTheme.mix(profile.edge, control.vividAccent,
            control.accentFill ? .82 : .44, 1)
        readonly property color baseShadow: MaterialTheme.rgba(shade, profile.light ? .30 : .75)
        readonly property real faceHeight: height - 2.8
        readonly property real focusInset: lip + 1.55
        readonly property string edgePath: Geometry.buttonFrame(.7, .7, width - 1.4, faceHeight, radius, outline)
        readonly property string facePath: Geometry.buttonFrame(.7 + lip, .7 + lip, width - 1.4 - 2 * lip,
            faceHeight - 2 * lip, radius - lip, outline)
        readonly property string focusPath: Geometry.buttonFrame(.7 + focusInset, .7 + focusInset,
            width - 1.4 - 2 * focusInset, faceHeight - 2 * focusInset, radius - focusInset, outline)

        opacity: control.enabled ? 1 : .54

        // The well stays in place as the cap lifts or settles into it.
        Shape {
            anchors.fill: parent
            transform: Translate { y: 1.7 }
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                fillColor: buttonBackground.baseShadow
                PathSvg { path: buttonBackground.edgePath }
            }
        }

        Shape {
            anchors.fill: parent
            transform: Translate { y: control.faceOffset }
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillGradient: LinearGradient {
                    x2: buttonBackground.width * .03
                    y2: buttonBackground.faceHeight
                    GradientStop {
                        position: 0
                        color: MaterialTheme.mix(buttonBackground.edge, buttonBackground.highlight,
                            control.down ? .13 : .31 + buttonBackground.gloss * .26, 1)
                    }
                    GradientStop {
                        position: .46
                        color: MaterialTheme.rgba(buttonBackground.edge, .68)
                    }
                    GradientStop {
                        position: 1
                        color: MaterialTheme.mix(buttonBackground.edge, buttonBackground.shade, .51, 1)
                    }
                }
                PathSvg { path: buttonBackground.edgePath }
            }

            ShapePath {
                strokeWidth: -1
                fillGradient: LinearGradient {
                    x2: buttonBackground.width * .03
                    y2: buttonBackground.faceHeight
                    GradientStop {
                        position: 0
                        color: control.down ? MaterialTheme.mix(control.faceColor, buttonBackground.shade, .19, 1)
                            : MaterialTheme.mix(control.faceColor, buttonBackground.highlight,
                                .19 + .23 * buttonBackground.gloss, 1)
                    }
                    GradientStop {
                        position: .36
                        color: control.faceColor
                    }
                    GradientStop {
                        position: .68
                        color: control.faceColor
                    }
                    GradientStop {
                        position: 1
                        color: MaterialTheme.mix(control.faceColor, buttonBackground.shade,
                            control.down ? .10 : .19 + .07 * buttonBackground.gloss, 1)
                    }
                }
                PathSvg { path: buttonBackground.facePath }
            }
        }

        Shape {
            anchors.fill: parent
            transform: Translate { y: control.faceOffset }
            preferredRendererType: Shape.CurveRenderer
            opacity: control.visualFocus && control.enabled ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                enabled: !MaterialTheme.reducedMotion
                NumberAnimation { duration: 105 }
            }

            ShapePath {
                strokeWidth: 1.4
                strokeColor: MaterialTheme.mix(control.iconInk, control.buttonInk, .30, 1)
                fillColor: "transparent"
                PathSvg { path: buttonBackground.focusPath }
            }
        }
    }
}
