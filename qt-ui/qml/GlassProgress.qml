pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import "MaterialGeometry.js" as Geometry

Item {
    id: progress

    property real value: 0
    property string material: MaterialTheme.current
    property bool animated: false
    property bool showLabel: false
    property string shape: ["bubble", "prism", "ice"].includes(profile.shape) ? profile.shape : "round"
    property string fillStyle: "sculpted"
    property color startColor: profile.accent
    property color endColor: profile.secondary
    property color trackColor: profile.background

    readonly property var profile: MaterialTheme.profile(material)
    readonly property bool sculpted: fillStyle === "sculpted"
    readonly property bool renderWithShader: shape === "bubble" && width >= 40 && height >= 9
        && GraphicsInfo.api !== GraphicsInfo.Software && GraphicsInfo.api !== GraphicsInfo.Unknown
    readonly property bool canAnimate: animated && visible && width >= 40 && height >= 9 && !MaterialTheme.reducedMotion
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
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
    }

    NumberAnimation on wavePhase {
        from: 0
        to: Math.PI * 2
        duration: 1850
        loops: Animation.Infinite
        running: progress.liquidMoving
    }

    ShaderEffect {
        anchors.fill: parent
        visible: progress.renderWithShader
        property vector2d surfaceSize: Qt.vector2d(width, height)
        property color liquidStart: progress.startColor
        property color liquidEnd: progress.endColor
        property color glassTint: progress.trackColor
        property real amount: progress.shownAmount
        property real phase: progress.wavePhase
        property real polish: progress.sculpted ? 1 : 0.7
        property real flow: progress.liquidMoving ? 1 : 0
        fragmentShader: "qrc:/auralis/shaders/bubble.frag.qsb"
    }

    Item {
        id: vessel
        visible: !progress.renderWithShader
        anchors.fill: parent
        anchors.margins: 1.5

        readonly property string trackPath: Geometry.barContour(width, height, progress.shape, 1, 0)
        readonly property string fillPath: Geometry.barContour(width, height, progress.shape, progress.shownAmount,
                                                               progress.shape === "bubble" ? progress.wavePhase : 0)

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // The color field is transparent. Reflections live on the rim.
            ShapePath {
                strokeWidth: progress.shape === "bubble" ? 2.5 : 1.35
                strokeColor: MaterialTheme.rgba(progress.endColor, .34)
                fillColor: MaterialTheme.rgba(progress.trackColor, .09)
                PathSvg { path: vessel.trackPath }
            }

            ShapePath {
                strokeWidth: -1
                fillGradient: LinearGradient {
                    x1: 0; y1: 0; x2: 0; y2: vessel.height
                    GradientStop { position: 0; color: MaterialTheme.rgba(progress.profile.upper, .54) }
                    GradientStop { position: .2; color: MaterialTheme.rgba(progress.profile.accent, .16) }
                    GradientStop { position: .42; color: "transparent" }
                    GradientStop { position: .66; color: MaterialTheme.rgba(progress.profile.shade, .05) }
                    GradientStop { position: .88; color: MaterialTheme.rgba(progress.profile.accent, .22) }
                    GradientStop { position: 1; color: MaterialTheme.rgba(progress.profile.edge, .61) }
                }
                PathSvg { path: vessel.trackPath }
            }

            ShapePath {
                strokeWidth: .7
                strokeColor: MaterialTheme.rgba(progress.endColor, .67)
                fillGradient: LinearGradient {
                    x1: 0; y1: vessel.height * .65; x2: vessel.width; y2: vessel.height * .12
                    GradientStop { position: 0; color: MaterialTheme.rgba(progress.startColor, .88) }
                    GradientStop { position: .61; color: MaterialTheme.rgba(progress.endColor, .8) }
                    GradientStop { position: 1; color: MaterialTheme.rgba(progress.endColor, .92) }
                }
                PathSvg { path: vessel.fillPath }
            }

            ShapePath {
                strokeWidth: -1
                fillGradient: LinearGradient {
                    x1: 0; y1: 0; x2: 0; y2: vessel.height
                    GradientStop { position: 0; color: MaterialTheme.rgba(progress.profile.upper, .79) }
                    GradientStop { position: .20; color: MaterialTheme.rgba(progress.startColor, .22) }
                    GradientStop { position: .42; color: "transparent" }
                    GradientStop { position: .60; color: MaterialTheme.rgba(progress.profile.shade, progress.sculpted ? .25 : .10) }
                    GradientStop { position: .80; color: MaterialTheme.rgba(progress.endColor, .10) }
                    GradientStop { position: 1; color: MaterialTheme.rgba(progress.profile.upper, .51) }
                }
                PathSvg { path: vessel.fillPath }
            }

            ShapePath {
                strokeWidth: -1
                fillGradient: LinearGradient {
                    readonly property real sweep: 0.5 - 0.5 * Math.cos(progress.wavePhase)
                    x1: vessel.width * progress.shownAmount * (sweep - .36)
                    x2: vessel.width * progress.shownAmount * (sweep + .36)
                    y1: vessel.height
                    y2: 0
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: .37; color: MaterialTheme.rgba(progress.startColor, .11) }
                    GradientStop { position: .58; color: MaterialTheme.rgba(progress.profile.upper, .42) }
                    GradientStop { position: 1; color: "transparent" }
                }
                PathSvg { path: progress.liquidMoving ? vessel.fillPath : "" }
            }

            ShapePath {
                strokeColor: MaterialTheme.rgba(progress.profile.upper, .79)
                strokeWidth: Math.min(1.8, vessel.height * .078)
                capStyle: ShapePath.RoundCap
                fillColor: "transparent"
                PathSvg {
                    path: progress.sculpted && vessel.width >= 25
                        ? Geometry.barHighlights(vessel.width, vessel.height, progress.shape, false) : ""
                }
            }

            ShapePath {
                strokeColor: MaterialTheme.rgba(progress.endColor, .53)
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
                strokeColor: MaterialTheme.rgba(progress.profile.edge, .67)
                fillColor: "transparent"
                PathSvg { path: vessel.trackPath }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: progress.showLabel
        text: qsTr("%1%").arg(Math.round(progress.amount * 100))
        color: progress.profile.text
        font.pixelSize: 12
        font.weight: Font.DemiBold
        style: progress.profile.light ? Text.Normal : Text.Outline
        styleColor: MaterialTheme.rgba(progress.profile.shade, .9)
        Accessible.ignored: true
    }
}
