pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import "MaterialGeometry.js" as Geometry
import "IndicatorLighting.js" as Lighting
import "ProgressLayoutGeometry.js" as LayoutGeometry

Item {
    id: progress

    property real value: 0
    property string material: MaterialTheme.current
    property bool animated: false
    property string animationStyle: "classic"
    property string lightingStyle: WindowAppearance.progressLighting
    property string layoutStyle: WindowAppearance.progressLayout ?? "classic"
    property string transferState: ""
    property real externalPhase: -1
    property bool showLabel: false
    property real baseHeight: 22
    readonly property string shapeChoice: WindowAppearance.progressShape || "material"
    property string shape: shapeChoice === "material"
        ? (["bubble", "prism", "ice"].includes(profile.shape) ? profile.shape : "round") : shapeChoice
    readonly property real thicknessScale: (WindowAppearance.progressThickness ?? 100) / 100
    property color startColor: profile.accent
    property color endColor: profile.secondary
    property color trackColor: profile.background

    readonly property var profile: MaterialTheme.profile(material)
    readonly property bool usesMaterialProgress: !WindowAppearance.customProgressFill && Boolean(profile.mdm)
    readonly property var trackPaint: customTrackPaint(WindowAppearance.progressTrackFinish,
        WindowAppearance.progressTrackColors)
    readonly property var finish: Lighting.style(lightingStyle)
    readonly property string layoutKind: LayoutGeometry.style(layoutStyle)
    readonly property bool creativeLayout: !usesMaterialProgress && ["liquid-capsule", "jelly-beads",
        "braided-ribbon", "prism-segments", "molten-glass", "orbit-marker", "glass-tiles", "checkpoints", "tidal-ribbon", "frosted-cells", "filament-core", "twin-rails"].includes(layoutKind)
    readonly property bool classicLayout: layoutKind === "classic"
    readonly property bool labelAtEnd: showLabel && (usesMaterialProgress || creativeLayout || layoutKind === "thin-line")
    readonly property string transferStatus: transferState.toLowerCase()
    readonly property color statusTrackTint: layoutKind !== "status-track" ? "transparent"
        : transferStatus === "paused" || transferStatus === "stopped" ? profile.caution
        : transferStatus === "failed" || transferStatus === "error" ? profile.destructive : "transparent"
    readonly property var firstTone: MaterialTheme.neonTone(startColor)
    readonly property var lastTone: MaterialTheme.neonTone(endColor)
    readonly property real glowMargin: Math.round(Math.max(3, Math.min(5, height * .14)) * finish.haloWidth)
    readonly property int contour: shape === "bubble" ? 1 : shape === "ice" ? 4
        : ["prism", "chamfer"].includes(shape) ? 2
        : ["square", "plain"].includes(shape) ? 3 : 0
    readonly property bool renderWithShader: !usesMaterialProgress && classicLayout && width >= 12 && height >= 7
        && GraphicsInfo.api !== GraphicsInfo.Software && GraphicsInfo.api !== GraphicsInfo.Unknown
    readonly property int motionKind: animationStyle === "water" ? 1 : animationStyle === "jelly" ? 2 : 0
    readonly property bool canAnimate: !usesMaterialProgress && animationStyle !== "none" && animated && visible
        && width >= 12 && height >= 7 && !MaterialTheme.reducedMotion
    readonly property bool liquidMoving: canAnimate && amount > 0 && amount < 1
    readonly property real amount: Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0
    readonly property real wavePhase: externalPhase >= 0 ? externalPhase : localPhase
    property real shownAmount: amount
    property real localPhase: 0

    implicitWidth: 204
    implicitHeight: Math.round(baseHeight * thicknessScale)
    Accessible.role: Accessible.ProgressBar
    Accessible.name: qsTr("Download progress")
    Accessible.description: qsTr("%1 percent").arg(Math.round(amount * 100))

    function customTrackPaint(finishStyle, colors) {
        if (finishStyle === "default" && colors.length === 0)
            return null

        const mix = MaterialTheme.mix
        const rgba = MaterialTheme.rgba
        const materialColor = usesMaterialProgress ? profile.mdm?.progressTrack : undefined
        const first = colors[0] ?? materialColor ?? mix(trackColor, profile.ink, profile.light ? .16 : .24, 1)
        const last = colors[1] ?? first
        const tint = color => statusTrackTint.a > 0 ? mix(color, statusTrackTint, .30, 1) : color
        const light = "#f2f8ff"
        const shade = "#0d1320"
        const top = mix(first, light, .56, 1)
        const bottom = mix(last, shade, .53, 1)

        if (finishStyle === "clear")
            return { start: rgba(tint(first), .36), end: rgba(tint(last), .36),
                upper: rgba(top, .40), lower: rgba(last, .30), edge: rgba(top, .39) }
        if (finishStyle === "frosted")
            return { start: mix(tint(first), light, .34, .76), end: mix(tint(last), light, .34, .76),
                upper: rgba(light, .51), lower: rgba(top, .23), edge: rgba(top, .64) }
        if (finishStyle === "recessed")
            return { start: mix(tint(first), shade, .42, .91), end: mix(tint(last), shade, .42, .91),
                upper: rgba(shade, .65), lower: rgba(top, .28), edge: rgba(bottom, .77) }
        return { start: rgba(tint(first), .71), end: rgba(tint(last), .71),
            upper: rgba(top, .28), lower: rgba(bottom, .32), edge: rgba(top, .48) }
    }

    Behavior on shownAmount {
        enabled: progress.canAnimate
        NumberAnimation { duration: progress.motionKind === 2 ? 380 : 240; easing.type: Easing.OutCubic }
    }

    NumberAnimation on localPhase {
        from: 0
        to: Math.PI * 2
        duration: progress.motionKind === 1 ? 1480 : progress.motionKind === 2 ? 3700 : 2450
        loops: Animation.Infinite
        running: progress.liquidMoving && progress.externalPhase < 0
    }

    Loader {
        anchors.fill: parent
        anchors.margins: -progress.glowMargin
        active: progress.renderWithShader
        sourceComponent: shader
    }

    Loader {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: progress.labelAtEnd ? amountLabel.width + 8 : 0
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        active: progress.usesMaterialProgress
        sourceComponent: MdmProgressBar {
            appearance: progress.profile
            amount: progress.amount
            shape: progress.shapeChoice === "material" ? "material" : progress.shape
            thicknessScale: progress.thicknessScale
            trackPaint: progress.trackPaint
        }
    }

    Component {
        id: shader
        ShaderEffect {
            property vector2d surfaceSize: Qt.vector2d(progress.width, progress.height)
            property real padding: progress.glowMargin
            property color liquidStart: progress.firstTone.glow
            property color liquidEnd: progress.lastTone.glow
            property color glassTint: progress.trackColor
            property color trackStart: progress.trackPaint?.start ?? "transparent"
            property color trackEnd: progress.trackPaint?.end ?? "transparent"
            property color trackUpper: progress.trackPaint?.upper ?? "transparent"
            property color trackLower: progress.trackPaint?.lower ?? "transparent"
            property color trackEdge: progress.trackPaint?.edge ?? "transparent"
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
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 1.5
        anchors.rightMargin: progress.labelAtEnd ? amountLabel.width + 8 : 1.5
        anchors.verticalCenter: parent.verticalCenter
        height: LayoutGeometry.trackHeight(Math.max(0, progress.height - 3), progress.layoutKind, progress.thicknessScale)
        active: !progress.usesMaterialProgress && !progress.renderWithShader && !progress.creativeLayout

        sourceComponent: Item {
            id: vessel

            readonly property var trackSpans: progress.classicLayout ? []
                : LayoutGeometry.spans(width, height, progress.layoutKind, 1)
            readonly property var fillSpans: progress.classicLayout ? []
                : LayoutGeometry.spans(width, height, progress.layoutKind, progress.shownAmount)
            readonly property string trackPath: progress.classicLayout
                ? Geometry.barContour(width, height, progress.shape, 1, 0)
                : LayoutGeometry.path(trackSpans, height, progress.layoutKind, progress.shape)
            readonly property string fillPath: progress.classicLayout
                ? Geometry.barContour(width, height, progress.shape, progress.shownAmount,
                    progress.liquidMoving ? progress.wavePhase * (progress.motionKind === 1 ? 2 : 1) : 0)
                : LayoutGeometry.path(fillSpans, height, progress.layoutKind, progress.shape)
            readonly property real front: {
                if (progress.classicLayout)
                    return width * progress.shownAmount
                const last = fillSpans[fillSpans.length - 1]
                return last ? last.x + last.width : 0
            }
            readonly property real remainder: Math.max(0, width - front)
            readonly property bool striped: progress.layoutKind === "striped-fill"
            readonly property real glowSize: progress.classicLayout ? progress.glowMargin
                : Math.min(progress.glowMargin, height * .23,
                    progress.layoutKind === "pill-segments"
                        ? LayoutGeometry.gap(width, height, progress.layoutKind) * .22 : height)
            readonly property color trackBody: {
                if (progress.classicLayout)
                    return MaterialTheme.rgba(progress.trackColor, .08 + .1 * progress.finish.depth)
                const base = MaterialTheme.mix(progress.trackColor, progress.profile.ink,
                    progress.profile.light ? .12 : .20, .75)
                return progress.statusTrackTint.a > 0
                    ? MaterialTheme.mix(base, progress.statusTrackTint, .35, .85) : base
            }
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
                if (!progress.finish.caustic || height < 7)
                    return ""
                const drift = progress.liquidMoving ? progress.wavePhase * (progress.motionKind === 1 ? 2 : 1) : 0
                const spans = progress.classicLayout ? [{x: 0, width: front}] : fillSpans
                let path = ""
                for (const span of spans) {
                    const start = span.x + Math.min(height * .3, progress.classicLayout ? width * .06 : span.width * .25)
                    const end = span.x + span.width - height * .2
                    if (end <= start)
                        continue
                    const segments = Math.ceil(Math.min(48, (end - start) / 3))
                    for (let i = 0; i <= segments; ++i) {
                        const x = start + (end - start) * i / segments
                        const radius = progress.classicLayout
                            ? height * .5 - Geometry.barEdge(x, width, height, progress.shape) : height * .42
                        const longitudinal = x / Math.max(6, height * .74)
                        const wave = second ? .17 - .44 * Math.cos(longitudinal * .79 + drift)
                            : -.09 - .50 * Math.sin(longitudinal - drift)
                        path += (i ? " L " : " M ") + x + " " + (height * .5 + radius * wave)
                    }
                }
                return path
            }

            function highlights(lower) {
                if (progress.classicLayout)
                    return width >= 25 ? Geometry.barHighlights(width, height, progress.shape, lower) : ""
                return LayoutGeometry.highlights(trackSpans, height, lower)
            }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                // The color field is transparent. Reflections live on the rim.
                ShapePath {
                    strokeWidth: 1.45
                    strokeColor: MaterialTheme.rgba(progress.lastTone.glow, .46 * progress.finish.reflection)
                    fillColor: vessel.trackBody
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
            }

            Loader {
                x: vessel.front
                width: vessel.remainder
                height: vessel.height
                clip: true
                active: Boolean(progress.trackPaint) && width > 0

                sourceComponent: Item {
                    Shape {
                        x: -vessel.front
                        width: vessel.width
                        height: vessel.height
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeWidth: 1
                            strokeColor: progress.trackPaint?.edge ?? "transparent"
                            fillGradient: LinearGradient {
                                x2: vessel.width
                                y2: 0
                                GradientStop { position: 0; color: progress.trackPaint?.start ?? "transparent" }
                                GradientStop { position: 1; color: progress.trackPaint?.end ?? "transparent" }
                            }
                            PathSvg { path: vessel.trackPath }
                        }

                        ShapePath {
                            strokeWidth: -1
                            fillGradient: LinearGradient {
                                x2: 0
                                y2: vessel.height
                                GradientStop { position: 0; color: progress.trackPaint?.upper ?? "transparent" }
                                GradientStop { position: .50; color: "transparent" }
                                GradientStop { position: 1; color: progress.trackPaint?.lower ?? "transparent" }
                            }
                            PathSvg { path: vessel.trackPath }
                        }
                    }
                }
            }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeWidth: 2 * vessel.glowSize + 1
                    strokeColor: MaterialTheme.mix(progress.firstTone.glow, progress.lastTone.glow, .5,
                        .14 * progress.finish.halo)
                    fillColor: "transparent"
                    PathSvg { path: vessel.fillPath }
                }

                ShapePath {
                    strokeWidth: vessel.glowSize
                    strokeColor: MaterialTheme.mix(progress.firstTone.glow, progress.lastTone.glow, .5,
                        .38 * progress.finish.halo)
                    fillColor: "transparent"
                    PathSvg { path: vessel.fillPath }
                }

                ShapePath {
                    strokeWidth: 1
                    strokeColor: MaterialTheme.rgba(progress.lastTone.edge, .84 * progress.finish.reflection)
                    fillGradient: LinearGradient {
                        x1: 0; y1: 0; x2: Math.max(1, vessel.front); y2: 0
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
                        x1: vessel.front * (sweep - spread)
                        x2: vessel.front * (sweep + spread)
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
                    PathSvg { path: vessel.highlights(false) }
                }

                ShapePath {
                    strokeColor: MaterialTheme.rgba(progress.lastTone.glow, .72 * progress.finish.reflection)
                    strokeWidth: Math.min(1.35, vessel.height * .055)
                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    PathSvg { path: vessel.highlights(true) }
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
                active: vessel.spraying || (progress.visible && (vessel.striped || progress.finish.optic >= 5)
                    && progress.shownAmount > 0)
                sourceComponent: Canvas {
                    readonly property real phase: spraying ? progress.wavePhase : 0
                    readonly property real front: vessel.front
                    readonly property string outline: vessel.trackPath
                    readonly property string filledPath: vessel.fillPath
                    readonly property bool spraying: vessel.spraying
                    readonly property bool striped: vessel.striped
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
                    onStripedChanged: requestPaint()
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
                        if (!progress.classicLayout)
                            return height * (.5 + chamberY * .44)
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

                    function paintStripes(ctx) {
                        const slant = height * .85
                        const band = Math.max(1.5, height * .32)
                        ctx.save()
                        ctx.path = filledPath
                        ctx.clip()
                        ctx.beginPath()
                        for (let x = -slant; x < front; x += band * 2.1) {
                            ctx.moveTo(x, height)
                            ctx.lineTo(x + slant, 0)
                        }
                        ctx.lineWidth = band
                        ctx.strokeStyle = MaterialTheme.mix(inletLight, highlight, .5, .23)
                        ctx.stroke()
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
                        if (striped && front > 0)
                            paintStripes(ctx)
                        if (spraying)
                            paintSpray(ctx)
                    }
                }
            }
        }
    }

    Loader {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: progress.showLabel ? amountLabel.width + 8 : 0
        anchors.verticalCenter: parent.verticalCenter
        height: progress.height
        active: progress.creativeLayout
        sourceComponent: CreativeProgress {
            amount: progress.amount
            layoutStyle: progress.layoutKind
            shape: progress.shape
            lightingStyle: progress.lightingStyle
            animationStyle: progress.animationStyle
            startColor: progress.startColor
            endColor: progress.endColor
            trackColor: progress.trackColor
            phase: progress.liquidMoving ? progress.wavePhase : 0
            light: progress.profile.light
        }
    }

    Loader {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: progress.labelAtEnd ? amountLabel.width + 8 : 0
        height: progress.height
        active: !progress.creativeLayout && !progress.usesMaterialProgress && progress.liquidMoving
            && ["sheen", "heartbeat", "tide", "elastic", "glints", "current"].includes(progress.animationStyle)
        sourceComponent: CreativeProgress {
            overlayOnly: true
            fillMask: progress.classicLayout
                ? Geometry.barContour(width,height,progress.shape,progress.shownAmount,0)
                : LayoutGeometry.path(LayoutGeometry.spans(width,height,progress.layoutKind,progress.shownAmount),height,progress.layoutKind,progress.shape)
            amount: progress.amount
            shape: progress.shape
            layoutStyle: progress.layoutKind
            animationStyle: progress.animationStyle
            phase: progress.wavePhase
            startColor: progress.startColor
            endColor: progress.endColor
        }
    }

    NumeralLabel {
        id: amountLabel
        anchors.horizontalCenter: progress.labelAtEnd ? undefined : parent.horizontalCenter
        anchors.right: progress.labelAtEnd ? parent.right : undefined
        anchors.verticalCenter: parent.verticalCenter
        visible: progress.showLabel
        valueText: qsTr("%1%").arg(Math.round(progress.amount * 100))
        color: progress.labelAtEnd ? progress.profile.ink : "#ffffff"
        font.pixelSize: TypographyScale.pixels(12)
        font.weight: Font.DemiBold
        style: progress.labelAtEnd ? Text.Normal : Text.Outline
        styleColor: progress.lastTone.core
        Accessible.ignored: true
    }
}
