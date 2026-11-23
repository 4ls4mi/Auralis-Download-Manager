pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import "MaterialGeometry.js" as Geometry
import "IndicatorLighting.js" as Lighting

Item {
    id: progress

    property real value: 0
    property string material: MaterialTheme.current
    property bool animated: false
    property string animationStyle: "classic"
    property string lightingStyle: WindowAppearance.progressLighting
    property real externalPhase: -1
    property bool showLabel: false
    property string shape: ["bubble", "prism", "ice"].includes(profile.shape) ? profile.shape : "round"
    property color startColor: profile.accent
    property color endColor: profile.secondary
    property color trackColor: profile.background

    readonly property var profile: MaterialTheme.profile(material)
    readonly property var finish: Lighting.style(lightingStyle)
    readonly property var firstTone: MaterialTheme.neonTone(startColor)
    readonly property var lastTone: MaterialTheme.neonTone(endColor)
    readonly property real glowMargin: Math.round((height >= 28 ? 5 : 3) * finish.haloWidth)
    readonly property int contour: shape === "bubble" ? 1 : ["prism", "ice", "chamfer"].includes(shape) ? 2
        : ["square", "plain"].includes(shape) ? 3 : 0
    readonly property bool renderWithShader: width >= 12 && height >= 7
        && GraphicsInfo.api !== GraphicsInfo.Software && GraphicsInfo.api !== GraphicsInfo.Unknown
    readonly property int motionKind: animationStyle === "water" ? 1 : animationStyle === "jelly" ? 2 : 0
    readonly property bool canAnimate: animationStyle !== "none" && animated && visible
        && width >= 12 && height >= 7 && !MaterialTheme.reducedMotion
    readonly property bool liquidMoving: canAnimate && amount > 0 && amount < 1
    readonly property real amount: Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0
    readonly property real wavePhase: externalPhase >= 0 ? externalPhase : localPhase
    property real shownAmount: amount
    property real localPhase: 0

    implicitWidth: 204
    implicitHeight: 22
    Accessible.role: Accessible.ProgressBar
    Accessible.name: qsTr("Download progress")
    Accessible.description: qsTr("%1 percent").arg(Math.round(amount * 100))

    Behavior on shownAmount {
        enabled: progress.canAnimate
        NumberAnimation { duration: progress.motionKind === 2 ? 380 : 240; easing.type: Easing.OutCubic }
    }

    NumberAnimation on localPhase {
        from: 0
        to: Math.PI * 2
        duration: progress.motionKind === 1 ? 580 : progress.motionKind === 2 ? 2840 : 1850
        loops: Animation.Infinite
        running: progress.liquidMoving && progress.externalPhase < 0
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
            property vector4d lighting: Qt.vector4d(progress.finish.halo, progress.finish.reflection,
                progress.finish.depth, progress.finish.caustic)
            property real amount: progress.shownAmount
            property real phase: progress.liquidMoving ? progress.wavePhase : 0
            property real flow: progress.liquidMoving ? 1 : 0
            property real contour: progress.contour
            property real motionKind: progress.motionKind
            property real optic: progress.finish.optic
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
                progress.liquidMoving ? progress.wavePhase * (progress.motionKind === 1 ? 2 : 1) : 0)
            readonly property real remainder: width * (1 - progress.shownAmount)
            readonly property bool spraying: progress.liquidMoving && progress.motionKind === 1
                && progress.shownAmount > .001 && remainder >= 8 && height >= 8
            readonly property color firstBody: bodyColor(progress.firstTone)
            readonly property color lastBody: bodyColor(progress.lastTone)
            readonly property var fillBands: opticalBands()

            function bodyColor(tone) {
                if (progress.finish.optic === 1)
                    return MaterialTheme.mix(tone.glow, "#eef7ff", .56, 1)
                if (progress.finish.optic === 4)
                    return MaterialTheme.rgba(tone.core, .72)
                return tone.body
            }

            function opticalBands() {
                const first = progress.firstTone
                const last = progress.lastTone
                const rgba = MaterialTheme.rgba
                const finish = progress.finish
                switch (finish.optic) {
                case 1: {
                    const frost = MaterialTheme.mix(first.edge, "#eff9ff", .65, .78)
                    return [[0, rgba(first.edge, .58)], [.18, frost], [.37, rgba(frost, .65)],
                        [.61, rgba(last.edge, .40)], [.75, rgba(last.edge, .29)],
                        [.91, rgba(last.glow, .27)], [1, rgba(last.edge, .53)]]
                }
                case 2: {
                    const chrome = MaterialTheme.mix(first.edge, "#f4fbff", .80, .98)
                    const dark = rgba(first.core, .66)
                    return [[0, dark], [.075, dark], [.13, chrome], [.18, dark],
                        [.233, chrome], [.29, dark], [1, rgba(last.edge, .63)]]
                }
                case 3:
                    return [[0, rgba(first.core, .94)], [.15, rgba(first.core, .92)],
                        [.39, rgba(first.core, .81)], [.60, rgba(last.core, .64)],
                        [.76, rgba(last.glow, .68)], [.90, rgba(last.edge, .92)], [1, rgba(last.glow, .68)]]
                case 4:
                    return [[0, rgba(first.glow, .58)], [.095, rgba(first.edge, .57)],
                        [.24, rgba(first.core, .55)], [.56, rgba(last.core, .65)],
                        [.77, rgba(last.core, .71)], [.93, rgba(last.glow, .55)], [1, rgba(last.edge, .29)]]
                default:
                    return [[0, rgba(first.glow, .56)], [.13, rgba(first.edge, .85 * finish.reflection)],
                        [.31, rgba(first.glow, .23)], [.55, rgba(last.core, .35 + .53 * finish.depth)],
                        [.73, rgba(last.core, .12 + .52 * finish.depth)],
                        [.91, rgba(last.glow, .60 + .22 * finish.depth)], [1, rgba(last.edge, .55)]]
                }
            }

            function causticPath(second) {
                const start = Math.min(height * .3, width * .06)
                const end = width * progress.shownAmount - height * .2
                if (!progress.finish.caustic || height < 7 || end <= start)
                    return ""
                const drift = progress.liquidMoving ? progress.wavePhase * (progress.motionKind === 1 ? 2 : 1) : 0
                const segments = Math.ceil(Math.min(48, (end - start) / 3))
                let path = ""
                for (let i = 0; i <= segments; ++i) {
                    const x = start + (end - start) * i / segments
                    const radius = height * .5 - Geometry.barEdge(x, width, height, progress.shape)
                    const longitudinal = x / Math.max(6, height * .74)
                    const wave = second ? .17 - .44 * Math.cos(longitudinal * .79 + drift)
                        : -.09 - .50 * Math.sin(longitudinal - drift)
                    path += (i ? " L " : " M ") + x + " " + (height * .5 + radius * wave)
                }
                return path
            }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                // The color field is transparent. Reflections live on the rim.
                ShapePath {
                    strokeWidth: 1.45
                    strokeColor: MaterialTheme.rgba(progress.lastTone.glow, .46 * progress.finish.reflection)
                    fillColor: MaterialTheme.rgba(progress.trackColor, .08 + .1 * progress.finish.depth)
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
                    strokeColor: MaterialTheme.mix(progress.firstTone.glow, progress.lastTone.glow, .5,
                        .14 * progress.finish.halo)
                    fillColor: "transparent"
                    PathSvg { path: vessel.fillPath }
                }

                ShapePath {
                    strokeWidth: progress.glowMargin
                    strokeColor: MaterialTheme.mix(progress.firstTone.glow, progress.lastTone.glow, .5,
                        .38 * progress.finish.halo)
                    fillColor: "transparent"
                    PathSvg { path: vessel.fillPath }
                }

                ShapePath {
                    strokeWidth: 1
                    strokeColor: MaterialTheme.rgba(progress.lastTone.edge, .84 * progress.finish.reflection)
                    fillGradient: LinearGradient {
                        x1: 0; y1: 0; x2: Math.max(1, vessel.width * progress.shownAmount); y2: 0
                        GradientStop { position: 0; color: vessel.firstBody }
                        GradientStop {
                            position: .57
                            color: MaterialTheme.mix(vessel.firstBody, vessel.lastBody, .5, (vessel.firstBody.a + vessel.lastBody.a) / 2)
                        }
                        GradientStop { position: 1; color: vessel.lastBody }
                    }
                    PathSvg { path: vessel.fillPath }
                }

                ShapePath {
                    strokeWidth: -1
                    fillGradient: LinearGradient {
                        x1: 0; y1: 0; x2: 0; y2: vessel.height
                        GradientStop { position: vessel.fillBands[0][0]; color: vessel.fillBands[0][1] }
                        GradientStop { position: vessel.fillBands[1][0]; color: vessel.fillBands[1][1] }
                        GradientStop { position: vessel.fillBands[2][0]; color: vessel.fillBands[2][1] }
                        GradientStop { position: vessel.fillBands[3][0]; color: vessel.fillBands[3][1] }
                        GradientStop { position: vessel.fillBands[4][0]; color: vessel.fillBands[4][1] }
                        GradientStop { position: vessel.fillBands[5][0]; color: vessel.fillBands[5][1] }
                        GradientStop { position: vessel.fillBands[6][0]; color: vessel.fillBands[6][1] }
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
                    strokeColor: MaterialTheme.rgba(progress.firstTone.edge, .74)
                    strokeWidth: Math.min(1.7, vessel.height * .065)
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathSvg { path: vessel.causticPath(false) }
                }

                ShapePath {
                    strokeColor: MaterialTheme.rgba(progress.lastTone.edge, .62)
                    strokeWidth: Math.min(1.25, vessel.height * .055)
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathSvg { path: vessel.causticPath(true) }
                }

                ShapePath {
                    strokeColor: MaterialTheme.rgba(progress.firstTone.edge, .77 * progress.finish.reflection)
                    strokeWidth: Math.min(1.8, vessel.height * .078)
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathSvg {
                        path: vessel.width >= 25
                            ? Geometry.barHighlights(vessel.width, vessel.height, progress.shape, false) : ""
                    }
                }

                ShapePath {
                    strokeColor: MaterialTheme.rgba(progress.lastTone.glow, .72 * progress.finish.reflection)
                    strokeWidth: Math.min(1.35, vessel.height * .055)
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathSvg {
                        path: vessel.width >= 25
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

            Loader {
                anchors.fill: parent
                active: vessel.spraying || (progress.visible && progress.finish.optic >= 5 && progress.shownAmount > 0)
                sourceComponent: Canvas {
                    readonly property real phase: progress.wavePhase
                    readonly property real front: width - vessel.remainder
                    readonly property string outline: vessel.trackPath
                    readonly property string filledPath: vessel.fillPath
                    readonly property bool spraying: vessel.spraying
                    readonly property int optic: progress.finish.optic
                    readonly property color inletLight: progress.firstTone.edge
                    readonly property color glow: progress.lastTone.glow
                    readonly property color highlight: progress.lastTone.edge

                    onAvailableChanged: if (available) requestPaint()
                    onPhaseChanged: requestPaint()
                    onFrontChanged: requestPaint()
                    onOutlineChanged: requestPaint()
                    onFilledPathChanged: requestPaint()
                    onSprayingChanged: requestPaint()
                    onOpticChanged: requestPaint()
                    onInletLightChanged: requestPaint()
                    onGlowChanged: requestPaint()
                    onHighlightChanged: requestPaint()

                    function fraction(value) {
                        return value - Math.floor(value)
                    }

                    function advances(life) {
                        return life * (1.18 - .18 * life)
                    }

                    function positionY(x, chamberY) {
                        const edge = Geometry.barEdge(Math.max(0, Math.min(width, x)), width, height, progress.shape)
                        return height * .5 + chamberY * (height * .5 - edge)
                    }

                    function dot(ctx, x, y, radiusX, radiusY, color, alpha) {
                        ctx.beginPath()
                        ctx.ellipse(x - radiusX, y - radiusY, 2 * radiusX, 2 * radiusY)
                        ctx.fillStyle = color
                        ctx.globalAlpha = alpha
                        ctx.fill()
                    }

                    function lightWash(ctx, x1, y1, x2, y2, stops) {
                        const gradient = ctx.createLinearGradient(x1, y1, x2, y2)
                        for (const stop of stops)
                            gradient.addColorStop(stop[0], stop[1])
                        ctx.fillStyle = gradient
                        ctx.fillRect(0, 0, front, height)
                    }

                    function glint(ctx, x, y, radius) {
                        const spark = ctx.createRadialGradient(x, y, 0, x, y, radius)
                        spark.addColorStop(0, "#f1faff")
                        spark.addColorStop(.32, MaterialTheme.rgba(highlight, .57))
                        spark.addColorStop(1, "transparent")
                        ctx.fillStyle = spark
                        ctx.fillRect(x - radius, y - radius, radius * 2, radius * 2)
                    }

                    function paintOptics(ctx) {
                        const rgba = MaterialTheme.rgba
                        const tint = MaterialTheme.mix(inletLight, highlight, .5, 1)
                        const shade = MaterialTheme.mix(tint, "#08101c", .90, 1)
                        ctx.save()
                        ctx.path = filledPath
                        ctx.clip()
                        switch (optic) {
                        case 5: {
                            const satin = MaterialTheme.mix(tint, "#eff8ff", .55, .67)
                            lightWash(ctx, 0, height, front, -height * .26,
                                [[0, "transparent"], [.22, "transparent"], [.49, satin],
                                 [.70, rgba(satin, .22)], [1, "transparent"]])
                            break
                        }
                        case 6: {
                            const step = front / 6
                            for (let index = 0; index < 6; ++index) {
                                const x = index * step
                                const peak = index % 2 ? height * .90 : height * .10
                                ctx.beginPath()
                                ctx.moveTo(x, height * .5)
                                ctx.lineTo(x + step * .72, peak)
                                ctx.lineTo(x + step, height * .5)
                                ctx.lineTo(x + step * .38, height - peak)
                                ctx.closePath()
                                ctx.fillStyle = rgba(index % 2 ? shade : tint, .52)
                                ctx.fill()
                                ctx.lineWidth = .85
                                ctx.strokeStyle = rgba(tint, .56)
                                ctx.stroke()
                            }
                            break
                        }
                        case 7:
                            lightWash(ctx, 0, height * .14, front * .7, height * 1.1,
                                [[0, rgba(inletLight, .83)], [.38, rgba(inletLight, .28)],
                                 [.64, rgba(shade, .65)], [1, "transparent"]])
                            lightWash(ctx, front, height * .92, front * .30, -height * .08,
                                [[0, rgba(highlight, .86)], [.23, rgba(highlight, .37)], [.70, "transparent"], [1, "transparent"]])
                            break
                        case 8:
                            ctx.fillStyle = rgba(shade, .50)
                            ctx.fillRect(0, 0, front, height)
                            glint(ctx, front * .11, positionY(front * .11, -.69), Math.max(2.25, height * .16))
                            glint(ctx, front * .92, positionY(front * .92, .66), Math.max(2.25, height * .15))
                            break
                        case 9: {
                            const ribs = Math.max(3, Math.min(22, Math.round(front / 9)))
                            const pitch = front / ribs
                            for (let index = 0; index < ribs; ++index) {
                                const x = (index + .33) * pitch
                                ctx.beginPath()
                                ctx.moveTo(x + pitch * .28, 0)
                                ctx.quadraticCurveTo(x - pitch * .34, height * .52, x + pitch * .28, height)
                                ctx.lineWidth = Math.max(1.15, pitch * .40)
                                ctx.strokeStyle = rgba(shade, .59)
                                ctx.stroke()
                                ctx.lineWidth = Math.max(.65, pitch * .14)
                                ctx.strokeStyle = rgba(tint, .85)
                                ctx.stroke()
                            }
                            break
                        }
                        case 10: {
                            const film = ctx.createLinearGradient(0, 0, front, height)
                            film.addColorStop(0, MaterialTheme.mix(inletLight, "#89ffd4", .56, .89))
                            film.addColorStop(.43, MaterialTheme.mix(tint, "#f7c9fb", .56, .83))
                            film.addColorStop(.76, MaterialTheme.mix(tint, "#e8f1ff", .61, .88))
                            film.addColorStop(1, MaterialTheme.mix(highlight, "#ffd5a8", .54, .84))
                            ctx.path = filledPath
                            ctx.strokeStyle = film
                            ctx.lineWidth = Math.max(1.6, height * .12)
                            ctx.stroke()
                            break
                        }
                        case 11:
                            lightWash(ctx, 0, 0, 0, height,
                                [[0, rgba(shade, .78)], [.25, rgba(shade, .52)],
                                 [.52, MaterialTheme.mix(tint, "#f1f9ff", .37, .77)],
                                 [.75, rgba(glow, .33)], [1, rgba(shade, .79)]])
                            break
                        case 12: {
                            ctx.fillStyle = rgba(shade, .83)
                            ctx.fillRect(0, 0, front, height)
                            const edge = ctx.createLinearGradient(0, 0, front, 0)
                            edge.addColorStop(0, inletLight)
                            edge.addColorStop(1, highlight)
                            ctx.path = filledPath
                            ctx.strokeStyle = edge
                            ctx.lineWidth = Math.max(1.6, height * .106)
                            ctx.stroke()
                            break
                        }
                        }
                        ctx.restore()
                    }

                    function paintSpray(ctx) {
                        ctx.save()
                        ctx.path = outline
                        ctx.clip()
                        ctx.beginPath()
                        ctx.rect(front, 0, vessel.remainder, height)
                        ctx.clip()

                        const reach = vessel.remainder - 3
                        const count = reach >= 46 ? 7 : 3
                        const clock = 2 * phase / (2 * Math.PI)
                        for (let index = 0; index < count; ++index) {
                            const life = fraction(clock + index * .381966)
                            const wall = (index % 2 ? 1 : -1) * .87
                            const distance = reach * (index === 0 ? 1 : .39 + .60 * fraction(index * .754878))
                            const firstImpact = .235 + .112 * fraction((index + 1) * .618034)
                            const reflectedTime = life / firstImpact
                            const x = front + 2 + distance * advances(life)
                            const y = positionY(x, wall * (1 - Math.abs((reflectedTime + 1) % 4 - 2)))
                            const fade = Math.min(1, life / .07, (1 - life) / .33)
                            const size = (1.14 - life * .38) * (.75 + .39 * fraction((index + 1) * .56984))
                            const radiusX = size * Math.max(1.3, height * .085)
                            const radiusY = size * Math.max(1, height * .049)
                            dot(ctx, x, y, radiusX * 1.62, radiusY * 1.4, glow, fade * .38)
                            dot(ctx, x, y, radiusX, radiusY, highlight, fade * .93)

                            const hit = Math.floor((reflectedTime + 1) * .5)
                            const contact = (hit * 2 - 1) * firstImpact
                            const age = (life - contact) / .21
                            if (hit < 1 || age < 0 || age >= 1)
                                continue
                            const hitX = front + 2 + distance * advances(contact)
                            const hitWall = hit < 2 ? wall : -wall
                            const hitY = positionY(hitX, hitWall)
                            const impact = (1 - age) * (1 - .62 * contact)
                            const ringRadius = 1.1 + age * height * .37
                            ctx.beginPath()
                            ctx.ellipse(hitX - ringRadius, hitY - ringRadius / 2.3,
                                ringRadius * 2, ringRadius * 2 / 2.3)
                            ctx.lineWidth = 1.15
                            ctx.strokeStyle = glow
                            ctx.globalAlpha = impact * .67
                            ctx.stroke()

                            const advance = age * height
                            const lift = .86 * 4 * age * (1 - age)
                            const firstX = hitX + advance * .38
                            const secondX = hitX - advance * .23
                            const fragmentX = Math.max(1.15, height * .054)
                            const fragmentY = Math.max(.85, height * .037)
                            dot(ctx, firstX, positionY(firstX, hitWall * (1 - lift)),
                                fragmentX, fragmentY, highlight, impact * .83)
                            dot(ctx, secondX, positionY(secondX, hitWall * (1 - lift * .62)),
                                fragmentX * .8, fragmentY * .8, highlight, impact * .58)
                        }
                        ctx.restore()
                    }

                    onPaint: {
                        const ctx = getContext("2d")
                        if (!ctx)
                            return
                        ctx.reset()
                        ctx.clearRect(0, 0, width, height)
                        if (optic >= 5 && front > 0)
                            paintOptics(ctx)
                        if (spraying)
                            paintSpray(ctx)
                    }
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: progress.showLabel
        text: qsTr("%1%").arg(Math.round(progress.amount * 100))
        color: "#ffffff"
        font.pixelSize: TypographyScale.pixels(12)
        font.weight: Font.DemiBold
        style: Text.Outline
        styleColor: progress.lastTone.core
        Accessible.ignored: true
    }
}
