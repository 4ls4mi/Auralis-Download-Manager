import QtQuick

Canvas {
    id: root

    property var samples: []
    property bool paintingPaused: false
    property color lineColor: MaterialTheme.graphColors[0]
    property color endpointColor: MaterialTheme.graphColors[1]
    property color gridColor: MaterialTheme.palette.divider
    property bool light: MaterialTheme.palette.light
    property string graphShape: WindowAppearance.graphShape
    readonly property var lineTone: MaterialTheme.neonTone(lineColor)
    readonly property var endpointTone: MaterialTheme.neonTone(endpointColor)

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

    function gradient(ctx, from, to) {
        const band = ctx.createLinearGradient(0, 0, width, 0)
        band.addColorStop(0, from)
        band.addColorStop(1, to)
        return band
    }

    function trace(ctx, peak, floor, range) {
        ctx.beginPath()
        const spacing = (width - 1) / (samples.length - 1)
        ctx.moveTo(0, floor - samples[0] / peak * range)
        for (let i = 1; i < samples.length; ++i)
            ctx.lineTo(i * spacing, floor - samples[i] / peak * range)
    }

    function drawBars(ctx, peak, floor, range, glow, core, edge) {
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
        if (graphShape === "bars") {
            drawBars(ctx, peak, floor, range, glow, core, edge)
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
    }
}
