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
    readonly property int contour: shape === "bubble" ? 1 : ["prism", "ice", "chamfer"].includes(shape) ? 2
        : ["square", "plain"].includes(shape) ? 3 : 0
    readonly property bool renderWithShader: width >= 12 && height >= 7
        && GraphicsInfo.api !== GraphicsInfo.Software && GraphicsInfo.api !== GraphicsInfo.Unknown
    readonly property bool canAnimate: animated && visible && width >= 12 && height >= 7 && !MaterialTheme.reducedMotion
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

    Loader {
        anchors.fill: parent
        active: progress.renderWithShader
        sourceComponent: shader
    }

    Component {
        id: shader
        ShaderEffect {
            property vector2d surfaceSize: Qt.vector2d(width, height)
            property color liquidStart: progress.startColor
            property color liquidEnd: progress.endColor
            property color glassTint: progress.trackColor
            property real amount: progress.shownAmount
            property real phase: progress.wavePhase
            property real polish: progress.sculpted ? 1 : 0.7
            property real flow: progress.liquidMoving ? 1 : 0
            property real contour: progress.contour
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
                    strokeWidth: Math.min(3.8, vessel.height * .29)
                    strokeColor: MaterialTheme.rgba(progress.endColor, .27)
                    fillColor: "transparent"
                    PathSvg { path: vessel.fillPath }
                }

                ShapePath {
                    strokeWidth: .9
                    strokeColor: MaterialTheme.mix(progress.endColor, progress.profile.upper, .30, .83)
                    fillGradient: LinearGradient {
                        x1: 0; y1: vessel.height * .65; x2: vessel.width; y2: vessel.height * .12
                        GradientStop { position: 0; color: MaterialTheme.rgba(progress.startColor, .96) }
                        GradientStop { position: .61; color: MaterialTheme.rgba(progress.endColor, .91) }
                        GradientStop { position: 1; color: MaterialTheme.rgba(progress.endColor, .98) }
                    }
                    PathSvg { path: vessel.fillPath }
                }

                ShapePath {
                    strokeWidth: -1
                    fillGradient: LinearGradient {
                        x1: 0; y1: 0; x2: 0; y2: vessel.height
                        GradientStop { position: 0; color: MaterialTheme.mix(progress.startColor, progress.profile.upper, .58, .92) }
                        GradientStop { position: .20; color: MaterialTheme.rgba(progress.startColor, .22) }
                        GradientStop { position: .42; color: "transparent" }
                        GradientStop { position: .60; color: MaterialTheme.rgba(progress.profile.shade, progress.sculpted ? .25 : .10) }
                        GradientStop { position: .80; color: MaterialTheme.rgba(progress.endColor, .10) }
                        GradientStop { position: 1; color: MaterialTheme.mix(progress.endColor, progress.profile.upper, .50, .69) }
                    }
                    PathSvg { path: vessel.fillPath }
                }

                ShapePath {
                    strokeWidth: -1
                    fillGradient: LinearGradient {
                        readonly property real sweep: -.4 + 1.8 * progress.wavePhase / (Math.PI * 2)
                        x1: vessel.width * progress.shownAmount * (sweep - .31)
                        x2: vessel.width * progress.shownAmount * (sweep + .31)
                        y1: vessel.height
                        y2: 0
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: .27; color: MaterialTheme.rgba(progress.profile.shade, .28) }
                        GradientStop { position: .52; color: MaterialTheme.rgba(progress.profile.upper, .61) }
                        GradientStop { position: .73; color: MaterialTheme.rgba(progress.endColor, .26) }
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
