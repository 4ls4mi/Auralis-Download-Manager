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
    readonly property var mdmColors: materialPalette.mdm
    readonly property var finish: MaterialTheme.buttonFinishes[materialPalette.finish]
    readonly property color activeAccent: MaterialTheme.safeAccent(MaterialTheme.forcedAccent || accent, materialPalette.light)
    readonly property color vividAccent: MaterialTheme.vividControlAccent(activeAccent, materialPalette.light)
    readonly property color neutralFace: materialPalette.buttonFace || materialPalette.background
    readonly property color facePigment: MaterialTheme.controlPigment(vividAccent, materialPalette.secondary, finish.tint)
    readonly property real backingOpacity: finish.opacity + (1 - finish.opacity) * MaterialTheme.opacityFor(material)
    readonly property color restingFace: MaterialTheme.mix(neutralFace, facePigment,
        MaterialTheme.controlIdleStrength(materialPalette, finish), backingOpacity)
    readonly property bool selectedFace: filled || checked || highlighted
    readonly property real accentStrength: down ? finish.press : hovered ? finish.hover
        : visualFocus ? (finish.hover + finish.selected) / 2 : finish.selected
    readonly property color engagedFace: MaterialTheme.mix(neutralFace, facePigment, accentStrength,
        Math.max(.93, backingOpacity))
    readonly property bool accentFill: enabled && (selectedFace || hovered || down || visualFocus)
    readonly property color faceColor: accentFill ? engagedFace : restingFace
    readonly property color buttonInk: mdmColors
        ? !enabled ? mdmColors.textDisabled : selectedFace ? mdmColors.buttonAccentText : mdmColors.buttonText
        : MaterialTheme.controlTextInk(materialPalette.text, faceColor)
    readonly property color iconInk: mdmColors ? buttonInk : !enabled ? MaterialTheme.mix(materialPalette.muted, neutralFace, .36, 1)
        : MaterialTheme.controlIconInk(vividAccent, faceColor)
    property real faceOffset: enabled && !mdmColors ? down ? 1.55 : hovered ? -.45 : 0 : 0

    hoverEnabled: true
    font.pixelSize: TypographyScale.pixels(13)
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
        readonly property string outline: profile.shape === "plain" ? "square" : profile.shape
        readonly property real gloss: profile.gloss
        readonly property real lip: control.finish.lip + gloss * .34
        readonly property color highlight: MaterialTheme.mix(profile.light ? "#ffffff" : profile.upper,
            control.facePigment, control.accentFill ? .70 : .59, 1)
        readonly property color shade: profile.light ? MaterialTheme.mix(profile.shade, "#20283d", .38, 1) : profile.shade
        readonly property color edge: MaterialTheme.mix(profile.edge, control.facePigment,
            control.accentFill ? .83 + .10 * gloss : .54 + .19 * gloss, 1)
        readonly property color baseShadow: MaterialTheme.rgba(shade, profile.light ? .26 : .30 + .38 * control.backingOpacity)
        readonly property real faceHeight: height - 2.8
        readonly property real focusInset: lip + 1.55
        readonly property string edgePath: Geometry.buttonFrame(.7, .7, width - 1.4, faceHeight, radius, outline)
        readonly property string facePath: Geometry.buttonFrame(.7 + lip, .7 + lip, width - 1.4 - 2 * lip,
            faceHeight - 2 * lip, radius - lip, outline)
        readonly property string focusPath: Geometry.buttonFrame(.7 + focusInset, .7 + focusInset,
            width - 1.4 - 2 * focusInset, faceHeight - 2 * focusInset, radius - focusInset, outline)

        opacity: control.enabled || control.mdmColors ? 1 : .54

        Loader {
            anchors.fill: parent
            active: Boolean(control.mdmColors)
            sourceComponent: Rectangle {
                id: classicButton
                anchors.fill: parent
                radius: control.materialPalette.buttonRadius
                gradient: control.materialPalette.mdmGlossyButtons ? classicGloss : null
                Gradient {
                    id: classicGloss
                    GradientStop {
                        position: 0
                        color: MaterialTheme.mix(classicButton.color, control.mdmColors.gloss, .46, 1)
                    }
                    GradientStop { position: .55; color: classicButton.color }
                    GradientStop {
                        position: 1
                        color: MaterialTheme.mix(classicButton.color, control.mdmColors.buttonBorder, .22, 1)
                    }
                }
                color: !control.enabled ? control.mdmColors.buttonDisabled
                    : control.selectedFace ? control.mdmColors.buttonAccent
                    : control.down ? control.mdmColors.buttonPressed
                    : control.hovered ? control.mdmColors.buttonHot : control.mdmColors.button
                border.width: 1
                border.color: !control.enabled ? control.mdmColors.buttonDisabledBorder
                    : control.visualFocus ? control.mdmColors.focusRing : control.mdmColors.buttonBorder
            }
        }

        // The well stays in place as the cap lifts or settles into it.
        Shape {
            anchors.fill: parent
            visible: !control.mdmColors
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
            visible: !control.mdmColors
            transform: Translate { y: control.faceOffset }
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: -1
                fillRule: ShapePath.OddEvenFill
                fillGradient: LinearGradient {
                    x2: buttonBackground.width * .03
                    y2: buttonBackground.faceHeight
                    GradientStop {
                        position: 0
                        color: MaterialTheme.mix(buttonBackground.edge, buttonBackground.highlight,
                            control.down ? .17 : .24 + control.finish.crown, 1)
                    }
                    GradientStop {
                        position: .46
                        color: MaterialTheme.rgba(buttonBackground.edge, .84)
                    }
                    GradientStop {
                        position: 1
                        color: MaterialTheme.mix(buttonBackground.edge, buttonBackground.shade, .51, 1)
                    }
                }
                // Qt 6.8 can read past trailing whitespace when an inset path is still empty.
                PathSvg { path: (buttonBackground.edgePath + " " + buttonBackground.facePath).trim() }
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
                                control.finish.crown + .08 * buttonBackground.gloss, control.faceColor.a)
                    }
                    GradientStop {
                        position: control.finish.shoulder
                        color: control.faceColor
                    }
                    GradientStop {
                        position: .68
                        color: control.faceColor
                    }
                    GradientStop {
                        position: 1
                        color: MaterialTheme.mix(control.faceColor, buttonBackground.shade,
                            control.down ? .12 : control.finish.depth, control.faceColor.a)
                    }
                }
                PathSvg { path: buttonBackground.facePath }
            }
        }

        ButtonLighting {
            visible: !control.mdmColors
            anchors.fill: parent
            transform: Translate { y: control.faceOffset }
            material: control.material
            accent: control.vividAccent
            emphasized: control.accentFill
            pressed: control.down
            surfacePath: buttonBackground.facePath
        }

        Shape {
            anchors.fill: parent
            transform: Translate { y: control.faceOffset }
            preferredRendererType: Shape.CurveRenderer
            opacity: control.visualFocus && control.enabled ? 1 : 0
            visible: !control.mdmColors && opacity > 0

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
