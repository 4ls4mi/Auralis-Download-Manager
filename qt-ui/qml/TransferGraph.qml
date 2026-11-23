import QtQuick

Canvas {
    id: root

    property var samples: []
    property bool paintingPaused: false
    property bool flowActive: false
    property string animationStyle: "classic"
    property color lineColor: MaterialTheme.graphColors[0]
    property color endpointColor: MaterialTheme.graphColors[1]
    property color gridColor: MaterialTheme.palette.divider
    property bool light: MaterialTheme.palette.light
    property string graphShape: WindowAppearance.graphShape
    readonly property var lineTone: MaterialTheme.neonTone(lineColor)
    readonly property var endpointTone: MaterialTheme.neonTone(endpointColor)
    readonly property bool jellyFlow: animationStyle === "jelly"
    readonly property bool flowEnabled: flowActive && visible && available && !paintingPaused
        && !MaterialTheme.reducedMotion && samples.length > 1 && width >= 2 && height >= 3
        && (animationStyle === "water" || jellyFlow)
    property real flowPhase: 0

    renderTarget: Canvas.Image
    onSamplesChanged: requestPaint()
    onPaintingPausedChanged: if (!paintingPaused) requestPaint()
    onLineColorChanged: requestPaint()
    onEndpointColorChanged: requestPaint()
    onGridColorChanged: requestPaint()
    onLightChanged: requestPaint()
    onGraphShapeChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
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

    Timer {
        interval: 40
        repeat: true
        running: root.flowEnabled
        onTriggered: {
            const duration = root.jellyFlow ? 2900 : 1200
            root.flowPhase = (root.flowPhase + interval / duration) % 1
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

    function drawBars(ctx, peak, floor, range, glow, core, edge, flow) {
        const stride = width / samples.length
        const gap = Math.min(3, stride * .27)
        const barWidth = Math.max(1, stride - gap)
        const haloSize = Math.min(2, stride * .24)
        for (let i = 0; i < samples.length; ++i) {
            const barHeight = Math.max(0, samples[i] / peak * range)
            if (barHeight < 1)
                continue

            const top = floor - barHeight
            const x = i * stride + gap * .5
            ctx.fillStyle = glow
            ctx.globalAlpha = light ? .18 : .32
            ctx.fillRect(x - haloSize, top - haloSize, barWidth + haloSize * 2, barHeight + haloSize)
            ctx.fillStyle = core
            ctx.globalAlpha = .95
            ctx.fillRect(x, top, barWidth, barHeight)
            ctx.fillStyle = glow
            ctx.globalAlpha = .69
            ctx.fillRect(x, top, barWidth, Math.min(barHeight, height < 38 ? 2.15 : 3.4))
            ctx.fillStyle = edge
            ctx.globalAlpha = .98
            ctx.fillRect(x, top, barWidth, Math.min(barHeight, height < 38 ? 1 : 1.35))
            if (flow) {
                ctx.fillStyle = flow
                ctx.globalAlpha = light ? .66 : .84
                ctx.fillRect(x, top, barWidth, barHeight)
            }
        }
    }

    onPaint: {
        if (paintingPaused)
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

        if (graphShape !== "line") {
            trace(ctx, peak, floor, range)
            ctx.lineTo(width - 1, floor)
            ctx.lineTo(0, floor)
            ctx.closePath()
            ctx.fillStyle = gradient(ctx, first.body, last.body)
            ctx.globalAlpha = light ? .15 : .25
            ctx.fill()
            const depth = ctx.createLinearGradient(0, 0, 0, height)
            depth.addColorStop(0, MaterialTheme.rgba(first.core, 0))
            depth.addColorStop(1, MaterialTheme.rgba(last.core, light ? .12 : .34))
            ctx.fillStyle = depth
            ctx.globalAlpha = 1
            ctx.fill()
            if (flow) {
                ctx.fillStyle = flow
                ctx.globalAlpha = light ? .37 : .56
                ctx.fill()
            }
        }

        trace(ctx, peak, floor, range)
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        const compact = height < 38
        ctx.strokeStyle = glow
        ctx.lineWidth = compact ? 5.4 : 8
        ctx.globalAlpha = light ? .13 : .20
        ctx.stroke()
        ctx.lineWidth = compact ? 3.1 : 4.8
        ctx.globalAlpha = light ? .28 : .48
        ctx.stroke()
        ctx.strokeStyle = core
        ctx.lineWidth = compact ? 1.9 : 3
        ctx.globalAlpha = light ? .91 : .72
        ctx.stroke()
        ctx.strokeStyle = edge
        ctx.lineWidth = compact ? .95 : 1.55
        ctx.globalAlpha = 1
        ctx.stroke()
        if (flow) {
            ctx.strokeStyle = flow
            ctx.lineWidth = compact ? 1.3 : 2.1
            ctx.globalAlpha = light ? .78 : .93
            ctx.stroke()
        }
    }
}
