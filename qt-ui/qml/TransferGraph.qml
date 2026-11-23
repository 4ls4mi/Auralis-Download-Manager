import QtQuick
import QtQuick.Window
import "IndicatorLighting.js" as Lighting

Canvas {
    id: root

    property var samples: []
    property bool paintingPaused: false
    property bool flowActive: false
    property string animationStyle: "classic"
    property string lightingStyle: WindowAppearance.graphLighting || "polished"
    property color lineColor: MaterialTheme.graphColors[0]
    property color endpointColor: MaterialTheme.graphColors[1]
    property color gridColor: MaterialTheme.palette.divider
    property bool light: MaterialTheme.palette.light
    property string graphShape: WindowAppearance.graphShape
    readonly property var lineTone: MaterialTheme.neonTone(lineColor)
    readonly property var endpointTone: MaterialTheme.neonTone(endpointColor)
    readonly property var lighting: Lighting.style(lightingStyle)
    readonly property int optic: lighting.optic || 0
    readonly property color frostStart: MaterialTheme.mix(lineTone.edge, "#f1fbff", .46, 1)
    readonly property color frostEnd: MaterialTheme.mix(endpointTone.edge, "#f1fbff", .46, 1)
    readonly property color smokeStart: MaterialTheme.mix(lineTone.glow, "#070912", .88, 1)
    readonly property color smokeEnd: MaterialTheme.mix(endpointTone.glow, "#070912", .88, 1)
    readonly property bool compact: height < 38
    readonly property bool jellyFlow: animationStyle === "jelly"
    readonly property bool flowEnabled: flowActive && visible && available && !paintingPaused
        && !MaterialTheme.reducedMotion && samples.length > 1 && width >= 2 && height >= 3
        && animationStyle !== "none"
        && (!Window.window || (Window.window.visible && Window.window.visibility !== Window.Minimized))
    property real flowPhase: 0

    renderTarget: Canvas.Image
    onSamplesChanged: requestPaint()
    onPaintingPausedChanged: if (!paintingPaused) requestPaint()
    onLineColorChanged: requestPaint()
    onEndpointColorChanged: requestPaint()
    onGridColorChanged: requestPaint()
    onLightChanged: requestPaint()
    onGraphShapeChanged: requestPaint()
    onLightingStyleChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()
    onAvailableChanged: if (available) requestPaint()
    onAnimationStyleChanged: {
        flowPhase = 0
        requestPaint()
    }
    onFlowEnabledChanged: {
        if (!flowEnabled)
            flowPhase = 0
        requestPaint()
    }
    onFlowPhaseChanged: if (flowEnabled) requestPaint()

    FrameAnimation {
        running: root.flowEnabled
        property real lastPaint: -1
        onRunningChanged: lastPaint = -1
        onTriggered: {
            // Dense dashboard graphs need fewer repaints than the full-size history.
            if (root.compact && lastPaint >= 0 && elapsedTime - lastPaint < .030)
                return
            lastPaint = elapsedTime
            const duration = root.jellyFlow ? 2.9 : root.animationStyle === "water" ? 1.2 : 3.6
            root.flowPhase = (elapsedTime / duration) % 1
        }
    }

    function gradient(ctx, from, to) {
        const band = ctx.createLinearGradient(0, 0, width, 0)
        band.addColorStop(0, from)
        band.addColorStop(1, to)
        return band
    }

    // The reflection moves across the measured path without moving any sample.
    function flowGradient(ctx, first, last) {
        const rebound = jellyFlow ? Math.sin(flowPhase * Math.PI * 7) * (1 - flowPhase) : 0
        const spread = Math.max(3, width * (jellyFlow ? .28 + rebound * .06 : .16))
        const travel = jellyFlow
            ? flowPhase - Math.sin(flowPhase * Math.PI * 2) * .09 + rebound * .045
            : flowPhase
        const center = (width + spread * 2) * travel - spread
        const fraction = Math.max(0, Math.min(1, center / width))
        const glow = MaterialTheme.mix(first.glow, last.glow, fraction, 1)
        const edge = MaterialTheme.mix(first.edge, last.edge, fraction, 1)
        const shadow = MaterialTheme.mix(first.body, last.body, fraction, 1)
        const band = ctx.createLinearGradient(center - spread, 0, center + spread, 0)
        band.addColorStop(0, MaterialTheme.rgba(glow, 0))
        if (jellyFlow) {
            band.addColorStop(.20, MaterialTheme.rgba(shadow, .27))
            band.addColorStop(.39, MaterialTheme.rgba(glow, .54))
            band.addColorStop(.56 + rebound * .07, MaterialTheme.rgba(edge, .87))
            band.addColorStop(.82, MaterialTheme.rgba(glow, .26))
        } else {
            band.addColorStop(.23, MaterialTheme.rgba(glow, .28))
            band.addColorStop(.43, MaterialTheme.rgba(edge, .84))
            band.addColorStop(.55, MaterialTheme.rgba(shadow, .58))
            band.addColorStop(.68, MaterialTheme.rgba(edge, .68))
            band.addColorStop(.83, MaterialTheme.rgba(glow, .28))
        }
        band.addColorStop(1, MaterialTheme.rgba(glow, 0))
        return band
    }

    function trace(ctx, peak, floor, range) {
        ctx.beginPath()
        const spacing = (width - 1) / (samples.length - 1)
        ctx.moveTo(0, floor - samples[0] / peak * range)
        for (let i = 1; i < samples.length; ++i)
            ctx.lineTo(i * spacing, floor - samples[i] / peak * range)
    }

    function spectrum(tone, shift, alpha) {
        const hue = (Math.max(0, tone.hsvHue) + shift + 1) % 1
        return MaterialTheme.mix(tone, Qt.hsva(hue, .73, 1), .42, alpha)
    }

    function opticalShade(ctx, top, bottom, strength, x = 0, span = width) {
        const diagonal = optic >= 5 && optic <= 7
        const drift = optic === 5 || optic === 7 ? Math.sin(flowPhase * Math.PI * 2) * span * .10 : 0
        const shade = diagonal ? ctx.createLinearGradient(x + drift - span * .18, bottom, x + drift + span, top)
            : optic === 9 ? ctx.createLinearGradient(x, bottom, x + span, top)
            : ctx.createLinearGradient(0, top, 0, bottom)
        const color = MaterialTheme.rgba
        const first = lineTone
        const last = endpointTone
        switch (optic) {
        case 1:
            shade.addColorStop(0, color(frostStart, .92 * strength))
            shade.addColorStop(.35, color(frostStart, .68 * strength))
            shade.addColorStop(.79, color(frostEnd, .46 * strength))
            shade.addColorStop(1, color(last.glow, .28 * strength))
            break
        case 2:
            shade.addColorStop(0, color(first.body, .73 * strength))
            shade.addColorStop(.20, color(frostStart, .90 * strength))
            shade.addColorStop(.26, color(first.edge, .96 * strength))
            shade.addColorStop(.31, color(first.core, .92 * strength))
            shade.addColorStop(.70, color(last.body, .84 * strength))
            shade.addColorStop(.78, color(last.edge, .82 * strength))
            shade.addColorStop(.84, color(last.core, .65 * strength))
            shade.addColorStop(1, color(last.body, .30 * strength))
            break
        case 3:
            shade.addColorStop(0, color(first.core, .96 * strength))
            shade.addColorStop(.42, color(first.core, .88 * strength))
            shade.addColorStop(.62, color(last.body, .64 * strength))
            shade.addColorStop(.83, color(last.glow, .66 * strength))
            shade.addColorStop(.96, color(frostEnd, .98 * strength))
            shade.addColorStop(1, color(last.glow, .88 * strength))
            break
        case 4:
            shade.addColorStop(0, color(smokeStart, .73 * strength))
            shade.addColorStop(.31, color(smokeStart, .99 * strength))
            shade.addColorStop(.82, color(smokeEnd, .97 * strength))
            shade.addColorStop(1, color(last.body, .55 * strength))
            break
        case 5:
            shade.addColorStop(0, color(first.glow, .11 * strength))
            shade.addColorStop(.28, color(first.edge, .40 * strength))
            shade.addColorStop(.53, color(frostStart, .92 * strength))
            shade.addColorStop(.80, color(frostEnd, .39 * strength))
            shade.addColorStop(1, color(last.glow, .17 * strength))
            break
        case 6:
            shade.addColorStop(0, color(first.glow, .56 * strength))
            shade.addColorStop(.25, color(frostStart, .94 * strength))
            shade.addColorStop(.26, color(first.core, .91 * strength))
            shade.addColorStop(.55, color(last.body, .90 * strength))
            shade.addColorStop(.56, color(last.edge, .92 * strength))
            shade.addColorStop(.83, color(last.glow, .46 * strength))
            shade.addColorStop(.84, color(last.core, .85 * strength))
            shade.addColorStop(1, color(last.body, .54 * strength))
            break
        case 7:
            shade.addColorStop(0, color(first.body, .67 * strength))
            shade.addColorStop(.30, color(first.edge, .06))
            shade.addColorStop(.48, color(first.edge, .91 * strength))
            shade.addColorStop(.70, color(last.edge, .06))
            shade.addColorStop(1, color(last.body, .67 * strength))
            break
        case 8:
            shade.addColorStop(0, color(first.core, .67 * strength))
            shade.addColorStop(.44, color(smokeStart, .92 * strength))
            shade.addColorStop(1, color(smokeEnd, .86 * strength))
            break
        case 9:
            for (let band = 0; band < 4; ++band) {
                const position = band * .25
                const step = MaterialTheme.mix(first.glow, last.glow, band / 3, strength)
                shade.addColorStop(position, color(step, .16 * strength))
                shade.addColorStop(position + .115, color(step, .79 * strength))
                shade.addColorStop(position + .151, color(step, .94 * strength))
                shade.addColorStop(position + .172, color(last.core, .78 * strength))
            }
            shade.addColorStop(1, color(last.body, .63 * strength))
            break
        case 10:
            shade.addColorStop(0, spectrum(first.edge, -.09, .61 * strength))
            shade.addColorStop(.17, color(first.glow, .23 * strength))
            shade.addColorStop(.73, color(last.glow, .28 * strength))
            shade.addColorStop(1, spectrum(last.edge, .14, .79 * strength))
            break
        case 11:
            shade.addColorStop(0, color(first.core, .92 * strength))
            shade.addColorStop(.43, color(first.edge, .84 * strength))
            shade.addColorStop(.60, color(last.glow, .92 * strength))
            shade.addColorStop(1, color(last.core, .92 * strength))
            break
        case 12:
            shade.addColorStop(0, color(first.glow, .79 * strength))
            shade.addColorStop(.09, color(first.core, .76 * strength))
            shade.addColorStop(.88, color(last.core, .77 * strength))
            shade.addColorStop(.97, color(last.edge, .98 * strength))
            shade.addColorStop(1, color(last.glow, .73 * strength))
            break
        }
        return shade
    }

    function crossingBeam(ctx, x, top, span, bottom, strength) {
        const brush = ctx.createLinearGradient(x + span * .13, top, x + span * .91, bottom)
        const tint = frostEnd
        brush.addColorStop(0, MaterialTheme.rgba(tint, 0))
        brush.addColorStop(.44, MaterialTheme.rgba(tint, 0))
        brush.addColorStop(.66, MaterialTheme.rgba(tint, strength))
        brush.addColorStop(.81, MaterialTheme.rgba(tint, 0))
        brush.addColorStop(1, MaterialTheme.rgba(tint, 0))
        return brush
    }

    function traceHighlight(ctx, edge) {
        if (optic !== 6 && optic !== 7 && optic !== 9 && optic !== 10)
            return optic === 1 || optic === 5 ? gradient(ctx, frostStart, frostEnd) : edge

        const stroke = ctx.createLinearGradient(0, 0, width, 0)
        const first = lineTone.edge
        const last = endpointTone.edge
        const color = MaterialTheme.rgba
        switch (optic) {
        case 6:
            stroke.addColorStop(0, first)
            stroke.addColorStop(.21, frostStart)
            stroke.addColorStop(.23, color(first, .45))
            stroke.addColorStop(.39, color(first, .56))
            stroke.addColorStop(.41, frostStart)
            stroke.addColorStop(.62, last)
            stroke.addColorStop(.64, color(last, .46))
            stroke.addColorStop(.85, frostEnd)
            stroke.addColorStop(1, last)
            break
        case 7:
            stroke.addColorStop(0, color(first, .55))
            stroke.addColorStop(.30, frostStart)
            stroke.addColorStop(.52, color(last, .53))
            stroke.addColorStop(.76, frostEnd)
            stroke.addColorStop(1, color(last, .64))
            break
        case 9:
            for (let index = 0; index < 5; ++index) {
                const value = index / 5
                const tint = MaterialTheme.mix(first, last, index / 4, 1)
                stroke.addColorStop(value, color(tint, .54))
                stroke.addColorStop(value + .11, tint)
                stroke.addColorStop(value + .16, color(tint, .76))
            }
            stroke.addColorStop(1, last)
            break
        case 10:
            stroke.addColorStop(0, first)
            stroke.addColorStop(.24, spectrum(first, -.11, 1))
            stroke.addColorStop(.46, spectrum(first, .07, 1))
            stroke.addColorStop(.75, spectrum(last, .13, 1))
            stroke.addColorStop(1, last)
            break
        }
        return stroke
    }

    function pinpointReflection(ctx, x, y, color, size) {
        const light = ctx.createRadialGradient(x, y, 0, x, y, size)
        light.addColorStop(0, color)
        light.addColorStop(.35, MaterialTheme.rgba(color, .74))
        light.addColorStop(1, MaterialTheme.rgba(color, 0))
        ctx.fillStyle = light
        ctx.globalAlpha = 1
        ctx.fillRect(x - size, y - size, 2 * size, 2 * size)
    }

    function drawBars(ctx, peak, floor, range, glow, core, edge, flow) {
        const stride = width / samples.length
        const gap = Math.min(3, stride * .27)
        const barWidth = Math.max(1, stride - gap)
        const haloSize = Math.min(2.6, stride * .24) * lighting.haloWidth
        const color = MaterialTheme.rgba
        const tintedShade = gradient(ctx, lineTone.body, endpointTone.body)
        const shimmer = lighting.caustic ? flowGradient(ctx, lineTone, endpointTone) : null
        const sharedShade = optic && barWidth < 3.5 ? opticalShade(ctx, 0, floor, .84) : null
        for (let i = 0; i < samples.length; ++i) {
            const barHeight = Math.max(0, samples[i] / peak * range)
            if (barHeight < 1)
                continue

            const top = floor - barHeight
            const x = i * stride + gap * .5
            ctx.fillStyle = glow
            ctx.globalAlpha = (light ? .16 : .27) * lighting.halo
            ctx.fillRect(x - haloSize, top - haloSize, barWidth + haloSize * 2, barHeight + haloSize)
            ctx.fillStyle = core
            ctx.globalAlpha = .95
            ctx.fillRect(x, top, barWidth, barHeight)
            if (optic) {
                ctx.fillStyle = sharedShade || opticalShade(ctx, top, floor, .86, x, barWidth)
                ctx.globalAlpha = 1
                ctx.fillRect(x, top, barWidth, barHeight)
                if (optic === 7) {
                    ctx.fillStyle = crossingBeam(ctx, x, top, barWidth, floor, .49)
                    ctx.fillRect(x, top, barWidth, barHeight)
                }
            } else if (barHeight >= 6 && barWidth >= 3.5) {
                const shade = ctx.createLinearGradient(0, top, 0, floor)
                shade.addColorStop(0, color(lineTone.edge, .20 * lighting.reflection))
                shade.addColorStop(.26, color(lineTone.body, 0))
                shade.addColorStop(.83, color(endpointTone.body, .92 * lighting.depth))
                shade.addColorStop(1, color(endpointTone.core, .37 * lighting.depth))
                ctx.fillStyle = shade
                ctx.globalAlpha = 1
                ctx.fillRect(x, top, barWidth, barHeight)
                ctx.fillStyle = tintedShade
                ctx.globalAlpha = .58 * lighting.depth
                ctx.fillRect(x + barWidth * .81, top, barWidth * .19, barHeight)
            } else if (barHeight >= 4) {
                ctx.fillStyle = tintedShade
                ctx.globalAlpha = .77 * lighting.depth
                ctx.fillRect(x, floor - barHeight * .24, barWidth, barHeight * .24)
            }
            ctx.fillStyle = glow
            const upperLight = optic === 3 ? .43 : optic === 4 || optic === 8 || optic === 11 ? .61 : 1
            ctx.globalAlpha = (.57 + .11 * lighting.halo) * upperLight
            ctx.fillRect(x, top, barWidth, Math.min(barHeight, compact ? 2.15 : 3.4))
            ctx.fillStyle = edge
            ctx.globalAlpha = (.64 + .34 * lighting.reflection) * upperLight
            ctx.fillRect(x, top, barWidth, Math.min(barHeight, compact ? 1 : 1.35))
            if (optic === 8 && i % 3 === 1 && barWidth >= 3 && barHeight >= 4) {
                const radius = Math.max(1, Math.min(2.3, barWidth * .29, barHeight * .27))
                pinpointReflection(ctx, x + barWidth * .42, top + radius + .4, frostStart, radius)
            }
            if (shimmer && barHeight >= 6) {
                ctx.fillStyle = edge
                ctx.globalAlpha = .43 * lighting.caustic
                const refraction = (Math.cos(i * .67 - flowPhase * Math.PI * 2) + 1) * .19
                ctx.fillRect(x, top + barHeight * (.24 + refraction), barWidth, compact ? .75 : 1.1)
                ctx.fillStyle = shimmer
                ctx.globalAlpha = .36 * lighting.caustic
                ctx.fillRect(x, top, barWidth, barHeight)
            }
            if (flow) {
                ctx.fillStyle = flow
                ctx.globalAlpha = (light ? .66 : .84) * (optic === 3 || optic === 4 ? .62 : 1)
                ctx.fillRect(x, top, barWidth, barHeight)
            }
        }
    }

    function paintArea(ctx, peak, floor, range, first, last, flow) {
        trace(ctx, peak, floor, range)
        ctx.lineTo(width - 1, floor)
        ctx.lineTo(0, floor)
        ctx.closePath()
        const color = MaterialTheme.rgba
        ctx.fillStyle = gradient(ctx, first.core, last.core)
        ctx.globalAlpha = (light ? .10 : .15) + lighting.depth * .14
        ctx.fill()

        const shading = optic
            ? opticalShade(ctx, Math.max(0, floor - range / 1.15), floor, light ? .49 : .60)
            : ctx.createLinearGradient(0, 0, 0, height)
        if (!optic) {
            shading.addColorStop(0, color(first.glow, .27 * lighting.reflection))
            shading.addColorStop(.48, color(first.core, .04))
            shading.addColorStop(.88, color(last.body, (light ? .26 : .50) * lighting.depth))
            shading.addColorStop(1, color(last.glow, (light ? .08 : .19) * lighting.halo))
        }
        ctx.fillStyle = shading
        ctx.globalAlpha = 1
        ctx.fill()
        if (optic === 7) {
            ctx.fillStyle = crossingBeam(ctx, 0, 0, width, height, light ? .28 : .41)
            ctx.fill()
        }
        if (flow) {
            ctx.fillStyle = flow
            ctx.globalAlpha = (light ? .37 : .54) * (animationStyle === "classic" ? .55 : 1)
                * (optic === 3 || optic === 4 ? .68 : 1)
            ctx.fill()
        }

        if (optic === 9 && width >= 30) {
            ctx.save()
            ctx.clip()
            ctx.globalAlpha = 1
            const spacing = width / (compact ? 4 : 6)
            const curve = Math.sin(flowPhase * Math.PI * 2) * spacing * .14
            ctx.strokeStyle = color(last.edge, .51)
            ctx.lineWidth = compact ? .88 : 1.55
            for (let x = spacing * .35; x < width; x += spacing) {
                ctx.beginPath()
                ctx.moveTo(x, floor)
                ctx.quadraticCurveTo(x - spacing * .6 + curve, height * .44, x + spacing * .39, 0)
                ctx.stroke()
            }
            ctx.restore()
        } else if (lighting.caustic && width >= 22) {
            // Refracted light is clipped to the real speed history.
            ctx.save()
            ctx.clip()
            ctx.globalAlpha = 1
            const shift = Math.sin(flowPhase * Math.PI * 2)
            const reflection = ctx.createLinearGradient(0, 0, width, 0)
            reflection.addColorStop(0, color(first.glow, 0))
            reflection.addColorStop(.16 + shift * .06, color(first.edge, .51 * lighting.caustic))
            reflection.addColorStop(.41, color(first.glow, .08 * lighting.caustic))
            reflection.addColorStop(.69 + shift * .06, color(last.edge, .58 * lighting.caustic))
            reflection.addColorStop(1, color(last.glow, 0))
            ctx.strokeStyle = reflection
            ctx.lineWidth = compact ? .76 : 1.25
            for (let band = 0; band < (compact ? 1 : 2); ++band) {
                const y = height * (.55 + band * .21)
                const spread = height * (.18 - band * .04)
                ctx.beginPath()
                ctx.moveTo(0, y)
                ctx.bezierCurveTo(width * .13, y - spread * (1 + shift * .28), width * .30, y - spread,
                    width * .49, y + spread * .24 * shift)
                ctx.bezierCurveTo(width * .64, y + spread, width * .82, y - spread * (.32 + shift * .38), width, y + spread)
                ctx.stroke()
            }
            ctx.restore()
        }
    }

    onPaint: {
        if (paintingPaused || !visible)
            return
        const ctx = getContext("2d")
        if (!ctx)
            return
        ctx.reset()
        ctx.clearRect(0, 0, width, height)
        if (width < 2 || height < 3)
            return

        const floor = height - 1
        ctx.strokeStyle = gridColor
        ctx.lineWidth = 1
        ctx.globalAlpha = .42
        for (let i = 1; i <= 3; ++i) {
            const y = i * height / 4
            ctx.beginPath()
            ctx.moveTo(0, y)
            ctx.lineTo(width, y)
            ctx.stroke()
        }
        if (samples.length < 2)
            return

        const peak = Math.max(1, ...samples) * 1.15
        const range = Math.max(1, height - Math.min(8, height * .32))
        const first = lineTone
        const last = endpointTone
        const glow = gradient(ctx, first.glow, last.glow)
        const core = gradient(ctx, first.core, last.core)
        const edge = gradient(ctx, first.edge, last.edge)
        const flow = flowEnabled ? flowGradient(ctx, first, last) : null
        if (graphShape === "bars") {
            drawBars(ctx, peak, floor, range, glow, core, edge, flow)
            ctx.globalAlpha = 1
            return
        }

        if (graphShape !== "line")
            paintArea(ctx, peak, floor, range, first, last, flow)

        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        const frost = optic === 1
        const chrome = optic === 2
        const lowerLight = optic === 3
        const smoke = optic === 4
        const satin = optic === 5
        const pinpoint = optic === 8
        const backlit = optic === 11
        const perimeter = optic === 12
        const traceAccent = traceHighlight(ctx, edge)
        const separation = compact ? 2.0 : 3.6
        ctx.save()
        ctx.translate(0, (chrome || lowerLight) ? separation : (compact ? 2.1 : 3.7) * lighting.depth)
        trace(ctx, peak, floor, range)
        ctx.strokeStyle = lowerLight ? glow : chrome ? edge : gradient(ctx, first.body, last.body)
        ctx.lineWidth = lowerLight ? (compact ? 2.2 : 3.7)
            : chrome ? (compact ? .82 : 1.22) : (compact ? 2.9 : 4.2) * lighting.depth
        ctx.globalAlpha = lowerLight ? .76 : chrome ? .73 : .67 * lighting.depth
        ctx.stroke()
        if (lighting.caustic && graphShape === "line") {
            const seam = ctx.createLinearGradient(0, 0, width, 0)
            seam.addColorStop(0, MaterialTheme.rgba(first.edge, 0))
            seam.addColorStop(.29, MaterialTheme.rgba(first.edge, .6))
            seam.addColorStop(.46, MaterialTheme.rgba(first.edge, 0))
            seam.addColorStop(.71, MaterialTheme.rgba(last.edge, .56))
            seam.addColorStop(1, MaterialTheme.rgba(last.edge, 0))
            ctx.strokeStyle = seam
            ctx.globalAlpha = .81 * lighting.caustic
            ctx.lineWidth = compact ? .72 : .92
            ctx.stroke()
        }
        ctx.restore()
        trace(ctx, peak, floor, range)
        ctx.strokeStyle = frost || satin ? traceAccent : glow
        const haloScale = lowerLight ? .44 : chrome ? .71 : smoke || pinpoint ? .52 : 1
        ctx.lineWidth = (compact ? 5.4 : 8) * lighting.haloWidth * (frost || satin || backlit ? 1.37 : 1)
        ctx.globalAlpha = (light ? .13 : .20) * lighting.halo * haloScale
        ctx.stroke()
        ctx.lineWidth = (compact ? 3.1 : 4.8) * lighting.haloWidth
        ctx.globalAlpha = (light ? .28 : .43) * lighting.halo * haloScale
        ctx.stroke()
        if (perimeter) {
            ctx.strokeStyle = traceAccent
            ctx.lineWidth = compact ? 3.65 : 5.35
            ctx.globalAlpha = .93
            ctx.stroke()
        }
        ctx.strokeStyle = smoke || pinpoint || perimeter ? gradient(ctx, smokeStart, smokeEnd) : core
        ctx.lineWidth = (compact ? 1.9 : 3) * (chrome ? 1.30 : smoke ? 1.80 : 1)
        ctx.globalAlpha = perimeter ? .94 : light ? .91 : .72
        ctx.stroke()
        ctx.strokeStyle = traceAccent
        ctx.lineWidth = (compact ? .95 : 1.55) * (chrome || smoke || perimeter ? .78 : frost || satin ? 1.24 : 1)
        ctx.globalAlpha = (.63 + .37 * lighting.reflection)
            * (lowerLight || pinpoint || perimeter ? .49 : smoke || backlit ? .76 : 1)
        ctx.stroke()
        if (flow) {
            ctx.strokeStyle = flow
            ctx.lineWidth = compact ? 1.3 : 2.1
            ctx.globalAlpha = (light ? .78 : .93) * (animationStyle === "classic" ? .56 : 1)
                * (lowerLight || smoke ? .58 : 1)
            ctx.stroke()
        }
        if (pinpoint) {
            const spacing = (width - 1) / (samples.length - 1)
            const interval = Math.max(1, Math.floor(samples.length / 5))
            for (let i = interval; i < samples.length - 1; i += interval)
                pinpointReflection(ctx, i * spacing, floor - samples[i] / peak * range - .42,
                    frostStart, compact ? 1.7 : 2.75)
        }
    }
}
