import QtQuick

Canvas {
    id: root
    property var samples: []
    property color lineColor: "#77e8ff"
    property color endpointColor: "#9666ff"
    property color gridColor: "#385f79"
    property string graphShape: WindowAppearance.graphShape
    renderTarget: Canvas.Image
    onSamplesChanged: requestPaint()
    onLineColorChanged: requestPaint()
    onEndpointColorChanged: requestPaint()
    onGridColorChanged: requestPaint()
    onGraphShapeChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onAvailableChanged: if (available) requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        const floor = height - 1
        ctx.strokeStyle = gridColor
        ctx.lineWidth = 1
        ctx.globalAlpha = .42
        for (let i = 1; i <= 3; i++) {
            const y = i * height / 4
            ctx.beginPath()
            ctx.moveTo(0, y)
            ctx.lineTo(width, y)
            ctx.stroke()
        }
        if (samples.length < 2)
            return
        const peak = Math.max(1, ...samples) * 1.15
        const line = ctx.createLinearGradient(0, 0, width, 0)
        line.addColorStop(0, lineColor)
        line.addColorStop(1, endpointColor)
        ctx.globalAlpha = 1
        if (graphShape === "bars") {
            const stride = width / samples.length
            const gap = Math.min(2, Math.max(0, stride / 4))
            ctx.fillStyle = line
            for (let index = 0; index < samples.length; ++index) {
                const heightUsed = Math.max(0, samples[index] / peak * (height - 8))
                ctx.fillRect(index * stride + gap / 2, floor - heightUsed, Math.max(1, stride - gap), heightUsed)
            }
            return
        }
        ctx.beginPath()
        for (let i = 0; i < samples.length; i++) {
            const x = i * (width - 1) / (samples.length - 1)
            const y = floor - samples[i] / peak * (height - 8)
            if (i === 0)
                ctx.moveTo(x, y)
            else
                ctx.lineTo(x, y)
        }
        ctx.globalAlpha = 1
        ctx.strokeStyle = line
        ctx.lineWidth = 2.5
        ctx.stroke()
        if (graphShape === "line")
            return
        ctx.lineTo(width - 1, floor)
        ctx.lineTo(0, floor)
        ctx.closePath()
        ctx.globalAlpha = .26
        ctx.fillStyle = line
        ctx.fill()
        ctx.globalAlpha = 1
    }
}
