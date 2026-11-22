import QtQuick

Canvas {
    id: root

    property var samples: []
    property color lineColor: MaterialTheme.graphColors[0]
    property color endpointColor: MaterialTheme.graphColors[1]
    property color gridColor: MaterialTheme.palette.divider
    property bool light: MaterialTheme.palette.light
    property string graphShape: WindowAppearance.graphShape

    renderTarget: Canvas.Image
    onSamplesChanged: requestPaint()
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

    function drawBars(ctx, peak, floor, range, glow, pigment, specular) {
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
            ctx.globalAlpha = light ? .14 : .21
            ctx.fillRect(x - haloSize, top - haloSize, barWidth + haloSize * 2, barHeight + haloSize)
            ctx.fillStyle = pigment
            ctx.globalAlpha = .76
            ctx.fillRect(x, top, barWidth, barHeight)
            ctx.fillStyle = specular
            ctx.globalAlpha = .92
            ctx.fillRect(x, top, barWidth, Math.min(barHeight, height < 38 ? 1.2 : 2))
        }
    }

    onPaint: {
        const ctx = getContext("2d")
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
        const glow = gradient(ctx, lineColor, endpointColor)
        const first = MaterialTheme.safeAccent(lineColor, light)
        const last = MaterialTheme.safeAccent(endpointColor, light)
        const pigment = gradient(ctx, first, last)
        const specular = light ? pigment : gradient(ctx, MaterialTheme.mix(first, "#ebf8ff", .31, 1),
                                                     MaterialTheme.mix(last, "#ebf8ff", .31, 1))
        if (graphShape === "bars") {
            drawBars(ctx, peak, floor, range, glow, pigment, specular)
            ctx.globalAlpha = 1
            return
        }

        if (graphShape !== "line") {
            trace(ctx, peak, floor, range)
            ctx.lineTo(width - 1, floor)
            ctx.lineTo(0, floor)
            ctx.closePath()
            ctx.globalAlpha = light ? .23 : .28
            ctx.fillStyle = glow
            ctx.fill()
        }

        trace(ctx, peak, floor, range)
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        ctx.strokeStyle = glow
        ctx.lineWidth = height < 38 ? 5 : 8
        ctx.globalAlpha = light ? .14 : .22
        ctx.stroke()
        ctx.strokeStyle = pigment
        ctx.lineWidth = height < 38 ? 2.6 : 4.2
        ctx.globalAlpha = light ? .33 : .54
        ctx.stroke()
        ctx.strokeStyle = specular
        ctx.lineWidth = height < 38 ? 1.4 : 2.25
        ctx.globalAlpha = 1
        ctx.stroke()
    }
}
