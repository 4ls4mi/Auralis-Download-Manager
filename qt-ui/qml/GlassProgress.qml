pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import "MaterialGeometry.js" as Geometry

Item {
    id: progress

    property real value: 0
    property string material: MaterialTheme.current
    property bool animated: false
    property string animationStyle: "classic"
    property bool showLabel: false
    property string shape: ["bubble", "prism", "ice"].includes(profile.shape) ? profile.shape : "round"
    property string fillStyle: "sculpted"
    property color startColor: profile.accent
    property color endColor: profile.secondary
    property color trackColor: profile.background

    readonly property var profile: MaterialTheme.profile(material)
    readonly property bool sculpted: fillStyle === "sculpted"
    readonly property var firstTone: MaterialTheme.neonTone(startColor)
    readonly property var lastTone: MaterialTheme.neonTone(endColor)
    readonly property real glowMargin: height >= 28 ? 5 : 3
    readonly property int contour: shape === "bubble" ? 1 : ["prism", "ice", "chamfer"].includes(shape) ? 2
        : ["square", "plain"].includes(shape) ? 3 : 0
    readonly property bool renderWithShader: width >= 12 && height >= 7
        && GraphicsInfo.api !== GraphicsInfo.Software && GraphicsInfo.api !== GraphicsInfo.Unknown
    readonly property int motionKind: animationStyle === "water" ? 1 : animationStyle === "jelly" ? 2 : 0
    readonly property bool canAnimate: animationStyle !== "none" && animated && visible
        && width >= 12 && height >= 7 && !MaterialTheme.reducedMotion
    readonly property bool liquidMoving: canAnimate && amount > 0 && amount < 1
    readonly property real amount: Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0
    property real shownAmount: amount
    property real wavePhase

    implicitWidth: 204
    implicitHeight: 22
    Accessible.role: Accessible.ProgressBar
    Accessible.name: qsTr("Download progress")
    Accessible.description: qsTr("%1 percent").arg(Math.round(amount * 100))

    Behavior on shownAmount {
        enabled: progress.canAnimate
        NumberAnimation { duration: progress.motionKind === 2 ? 380 : 240; easing.type: Easing.OutCubic }
    }

    NumberAnimation on wavePhase {
        from: 0
        to: Math.PI * 2
        duration: progress.motionKind === 1 ? 680 : progress.motionKind === 2 ? 2840 : 1850
        loops: Animation.Infinite
        running: progress.liquidMoving
    }

    Loader {
        anchors.fill: parent
        anchors.margins: -progress.glowMargin
        active: progress.renderWithShader
        sourceComponent: shader
    }

    Component {
        id: shader
        ShaderEffect {
            property vector2d surfaceSize: Qt.vector2d(progress.width, progress.height)
            property real padding: progress.glowMargin
            property color liquidStart: progress.firstTone.glow
            property color liquidEnd: progress.lastTone.glow
            property color glassTint: progress.trackColor
            property real amount: progress.shownAmount
            property real phase: progress.wavePhase
            property real polish: progress.sculpted ? 1 : 0.7
            property real flow: progress.liquidMoving ? 1 : 0
            property real contour: progress.contour
            property real motionKind: progress.motionKind
            fragmentShader: "qrc:/auralis/shaders/bubble.frag.qsb"
        }
    }

    Loader {
        anchors.fill: parent
        anchors.margins: 1.5
        active: !progress.renderWithShader

        sourceComponent: Item {
            id: vessel

            readonly property string trackPath: Geometry.barContour(width, height, progress.shape, 1, 0)
            readonly property string fillPath: Geometry.barContour(width, height, progress.shape, progress.shownAmount,
                progress.liquidMoving ? progress.wavePhase : 0)

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                // The color field is transparent. Reflections live on the rim.
                ShapePath {
                    strokeWidth: 1.45
                    strokeColor: MaterialTheme.rgba(progress.lastTone.glow, .46)
                    fillColor: MaterialTheme.rgba(progress.trackColor, .12)
                    PathSvg { path: vessel.trackPath }
                }

                ShapePath {
                    strokeWidth: -1
                    fillGradient: LinearGradient {
                        x1: 0; y1: 0; x2: 0; y2: vessel.height
                        GradientStop { position: 0; color: MaterialTheme.rgba(progress.firstTone.edge, .45) }
                        GradientStop { position: .18; color: MaterialTheme.rgba(progress.firstTone.glow, .12) }
                        GradientStop { position: .42; color: "transparent" }
                        GradientStop { position: .66; color: MaterialTheme.rgba(progress.profile.shade, .05) }
                        GradientStop { position: .88; color: MaterialTheme.rgba(progress.lastTone.glow, .17) }
                        GradientStop { position: 1; color: MaterialTheme.rgba(progress.lastTone.edge, .45) }
                    }
                    PathSvg { path: vessel.trackPath }
                }

                ShapePath {
                    strokeWidth: 2 * progress.glowMargin + 1
                    strokeColor: MaterialTheme.mix(progress.firstTone.glow, progress.lastTone.glow, .5, .13)
                    fillColor: "transparent"
                    PathSvg { path: vessel.fillPath }
                }

                ShapePath {
                    strokeWidth: progress.glowMargin
                    strokeColor: MaterialTheme.mix(progress.firstTone.glow, progress.lastTone.glow, .5, .39)
                    fillColor: "transparent"
                    PathSvg { path: vessel.fillPath }
                }

                ShapePath {
                    strokeWidth: 1
                    strokeColor: MaterialTheme.rgba(progress.lastTone.edge, .9)
                    fillGradient: LinearGradient {
                        x1: 0; y1: 0; x2: Math.max(1, vessel.width * progress.shownAmount); y2: 0
                        GradientStop { position: 0; color: progress.firstTone.body }
                        GradientStop { position: .57; color: MaterialTheme.mix(progress.firstTone.body, progress.lastTone.body, .5, 1) }
                        GradientStop { position: 1; color: progress.lastTone.body }
                    }
                    PathSvg { path: vessel.fillPath }
                }

                ShapePath {
                    strokeWidth: -1
                    fillGradient: LinearGradient {
                        x1: 0; y1: 0; x2: 0; y2: vessel.height
                        GradientStop { position: 0; color: MaterialTheme.rgba(progress.firstTone.glow, .56) }
                        GradientStop { position: .13; color: MaterialTheme.rgba(progress.firstTone.edge, .84) }
                        GradientStop { position: .31; color: MaterialTheme.rgba(progress.firstTone.glow, .23) }
                        GradientStop { position: .55; color: MaterialTheme.rgba(progress.lastTone.core, progress.sculpted ? .87 : .70) }
                        GradientStop { position: .73; color: MaterialTheme.rgba(progress.lastTone.core, .41) }
                        GradientStop { position: .91; color: MaterialTheme.rgba(progress.lastTone.glow, .84) }
                        GradientStop { position: 1; color: MaterialTheme.rgba(progress.lastTone.edge, .55) }
                    }
                    PathSvg { path: vessel.fillPath }
                }

                ShapePath {
                    strokeWidth: -1
                    fillGradient: LinearGradient {
                        readonly property real sweep: -.4 + 1.8 * progress.wavePhase / (Math.PI * 2)
                        readonly property real spread: progress.motionKind === 1 ? .18 : progress.motionKind === 2 ? .42 : .31
                        x1: vessel.width * progress.shownAmount * (sweep - spread)
                        x2: vessel.width * progress.shownAmount * (sweep + spread)
                        y1: vessel.height
                        y2: progress.motionKind === 2 ? vessel.height * .28 : 0
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: .29; color: MaterialTheme.rgba(progress.firstTone.glow, progress.motionKind === 2 ? .46 : .25) }
                        GradientStop { position: .51; color: MaterialTheme.rgba(progress.firstTone.edge, progress.motionKind === 1 ? .82 : .58) }
                        GradientStop { position: .67; color: MaterialTheme.rgba(progress.lastTone.glow, .29) }
                        GradientStop { position: 1; color: "transparent" }
                    }
                    PathSvg { path: progress.liquidMoving ? vessel.fillPath : "" }
                }

                ShapePath {
                    strokeColor: MaterialTheme.rgba(progress.firstTone.edge, .76)
                    strokeWidth: Math.min(1.8, vessel.height * .078)
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathSvg {
                        path: progress.sculpted && vessel.width >= 25
                            ? Geometry.barHighlights(vessel.width, vessel.height, progress.shape, false) : ""
                    }
                }

                ShapePath {
                    strokeColor: MaterialTheme.rgba(progress.lastTone.glow, .68)
                    strokeWidth: Math.min(1.35, vessel.height * .055)
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathSvg {
                        path: progress.sculpted && vessel.width >= 25
                            ? Geometry.barHighlights(vessel.width, vessel.height, progress.shape, true) : ""
                    }
                }

                ShapePath {
                    strokeWidth: .95
                    strokeColor: MaterialTheme.rgba(progress.lastTone.glow, .25)
                    fillColor: "transparent"
                    PathSvg { path: vessel.trackPath }
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: progress.showLabel
        text: qsTr("%1%").arg(Math.round(progress.amount * 100))
        color: "#ffffff"
        font.pixelSize: 12
        font.weight: Font.DemiBold
        style: Text.Outline
        styleColor: progress.lastTone.core
        Accessible.ignored: true
    }
}
