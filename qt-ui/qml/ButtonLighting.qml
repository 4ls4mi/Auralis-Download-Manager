pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import "MaterialGeometry.js" as Geometry

Shape {
    id: lighting

    property string material: MaterialTheme.current
    property color accent: profile.accent
    property real radius: Math.min(8, profile.radius)
    property bool emphasized: false
    property bool pressed: false
    property string surfacePath: Geometry.buttonFrame(.8, .8, width - 1.6, height - 1.6, radius, "round")

    readonly property var profile: MaterialTheme.profile(material)
    readonly property var finish: MaterialTheme.buttonFinishes[profile.finish]
    readonly property bool moving: visible && enabled && width >= 12 && height >= 8
        && Boolean(Window.window?.visible) && Window.window.visibility !== Window.Minimized
        && !MaterialTheme.reducedMotion
    property bool clockRegistered: false
    readonly property real phase: moving ? MaterialTheme.buttonLightPhase : 0
    readonly property real center: width * (.50 + .30 * Math.sin(phase + Math.max(0, accent.hsvHue) * 2.5))
    readonly property real span: Math.max(8, width * finish.spread) * .5
    readonly property color glint: MaterialTheme.mix(profile.upper, accent, profile.light ? .68 : .63, 1)
    readonly property color returnLight: MaterialTheme.controlPigment(glint, profile.secondary, .28)
    readonly property real strength: finish.light * (.78 + profile.gloss * .44)
        * (pressed ? .66 : emphasized ? 1.13 : .88)

    opacity: enabled ? 1 : 0
    preferredRendererType: Shape.CurveRenderer

    function registerClock() {
        if (clockRegistered === moving)
            return
        clockRegistered = moving
        MaterialTheme.visibleButtonLights += clockRegistered ? 1 : -1
    }

    onMovingChanged: registerClock()
    Component.onCompleted: registerClock()
    Component.onDestruction: if (clockRegistered && MaterialTheme) MaterialTheme.visibleButtonLights--

    ShapePath {
        strokeWidth: -1
        fillGradient: LinearGradient {
            x1: lighting.center - lighting.span
            y1: lighting.height * .09
            x2: lighting.center + lighting.span
            y2: lighting.height * (.09 + lighting.finish.slant)
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: .32; color: MaterialTheme.rgba(lighting.glint, lighting.strength * .38) }
            GradientStop { position: .51; color: MaterialTheme.rgba(lighting.glint, lighting.strength) }
            GradientStop { position: .68; color: MaterialTheme.rgba(lighting.returnLight, lighting.strength * .45) }
            GradientStop { position: 1; color: "transparent" }
        }
        PathSvg { path: lighting.surfacePath }
    }
}
