import QtQuick

Canvas {
    id: root
    property real amount: 0
    property string layoutStyle: "liquid-capsule"
    property color startColor: "#38d8ce"
    property color endColor: "#a97afa"
    property color trackColor: "#202530"
    property real phase: 0
    property bool light: false
    readonly property real fraction: Number.isFinite(amount) ? Math.max(0, Math.min(1, amount)) : 0
    renderTarget: Canvas.Image
    onAmountChanged: requestPaint()
    onLayoutStyleChanged: requestPaint()
    onStartColorChanged: requestPaint()
    onEndColorChanged: requestPaint()
    onTrackColorChanged: requestPaint()
    onPhaseChanged: requestPaint()
    onLightChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()
    onAvailableChanged: if (available) requestPaint()

    function capsule(ctx, x, y, w, h) {
        const r = Math.max(0, Math.min(h / 2, w / 2))
        ctx.beginPath()
        ctx.moveTo(x + r, y)
        ctx.lineTo(x + w - r, y)
        ctx.quadraticCurveTo(x + w, y, x + w, y + r)
        ctx.lineTo(x + w, y + h - r)
        ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h)
        ctx.lineTo(x + r, y + h)
        ctx.quadraticCurveTo(x, y + h, x, y + h - r)
        ctx.lineTo(x, y + r)
        ctx.quadraticCurveTo(x, y, x + r, y)
        ctx.closePath()
    }

    function drawProgress(ctx) {
        ctx.reset()
        ctx.clearRect(0, 0, width, height)
        if (width < 3 || height < 3) return
        const x = 2, y = Math.max(2, height * .12)
        const w = width - 4, h = Math.max(1, height - 2 * y)
        const front = w * fraction
        const orbit = layoutStyle === "orbit-marker"
        const trackH = orbit ? Math.max(2, h * .18) : h
        capsule(ctx, x, y + (h - trackH) / 2, w, trackH)
        ctx.fillStyle = trackColor
        ctx.fill()
        ctx.strokeStyle = light ? "#65000000" : "#70ffffff"
        ctx.lineWidth = .7
        ctx.stroke()
        if (fraction <= 0) return
        ctx.save()
        capsule(ctx, x, y, w, h)
        ctx.clip()
        // Clip every decoration at the real byte boundary, including partial cells.
        ctx.beginPath()
        ctx.rect(x, y, front, h)
        ctx.clip()
        const color = ctx.createLinearGradient(x, 0, x + w, 0)
        color.addColorStop(0, startColor)
        color.addColorStop(1, endColor)
        ctx.fillStyle = color
        const segmented = layoutStyle === "jelly-beads" || layoutStyle === "prism-segments"
        if (segmented) {
            const count = Math.max(1, Math.min(24, Math.floor(w / Math.max(14, h * 1.7))))
            const step = w / count, gap = Math.min(4, step * .14)
            for (let i = 0; i < count; i++) {
                const left = x + i * step, span = step - gap
                if (layoutStyle === "jelly-beads") capsule(ctx, left, y + 1, span, Math.max(1, h - 2))
                else {
                    ctx.beginPath()
                    ctx.moveTo(left + span * .22, y)
                    ctx.lineTo(left + span, y)
                    ctx.lineTo(left + span * .78, y + h)
                    ctx.lineTo(left, y + h)
                    ctx.closePath()
                }
                ctx.fillStyle = color
                ctx.fill()
                ctx.save()
                ctx.clip()
                const gloss = ctx.createLinearGradient(0, y, 0, y + h)
                gloss.addColorStop(0, "#c0ffffff")
                gloss.addColorStop(.32, "#15ffffff")
                gloss.addColorStop(.7, "#18000000")
                gloss.addColorStop(1, "#70000000")
                ctx.fillStyle = gloss
                ctx.fillRect(left, y, span, h)
                if (layoutStyle === "prism-segments") {
                    ctx.beginPath()
                    ctx.moveTo(left, y + h)
                    ctx.lineTo(left + span * .5, y + h * .5)
                    ctx.lineTo(left + span, y)
                    ctx.strokeStyle = "#90ffffff"
                    ctx.lineWidth = .7
                    ctx.stroke()
                }
                ctx.restore()
            }
        } else if (layoutStyle === "braided-ribbon") {
            for (let strand = 0; strand < 2; strand++) {
                ctx.beginPath()
                const points = Math.min(240, Math.ceil(w / 2))
                for (let i = 0; i <= points; i++) {
                    const px = w * i / points
                    const py = y + h / 2 + Math.sin(px / Math.max(8, h) + phase + strand * Math.PI) * h * .25
                    if (!i) ctx.moveTo(x + px, py)
                    else ctx.lineTo(x + px, py)
                }
                ctx.lineWidth = Math.max(2, h * .23)
                ctx.strokeStyle = strand ? endColor : startColor
                ctx.stroke()
            }
        } else {
            capsule(ctx, x, y + (h - trackH) / 2, front, trackH)
            ctx.fillStyle = color
            ctx.fill()
            if (!orbit) {
                const gloss = ctx.createLinearGradient(0, y, 0, y + h)
                gloss.addColorStop(0, "#c0ffffff")
                gloss.addColorStop(.3, "#18ffffff")
                gloss.addColorStop(.75, "#10000000")
                gloss.addColorStop(1, "#80000000")
                ctx.fillStyle = gloss
                ctx.fill()
                if (layoutStyle === "molten-glass") {
                    for (let band = 0; band < 2; band++) {
                        ctx.beginPath()
                        for (let i = 0; i <= 64; i++) {
                            const px = front * i / 64
                            const py = y + h * (.38 + band * .25) + Math.sin(i / 7 + phase + band * 2) * h * .14
                            if (!i) ctx.moveTo(x + px, py)
                            else ctx.lineTo(x + px, py)
                        }
                        ctx.strokeStyle = band ? "#80ffffff" : "#b0ffd28b"
                        ctx.lineWidth = Math.max(1, h * .16)
                        ctx.stroke()
                    }
                }
            }
        }
        ctx.restore()
        if (orbit) {
            const radius = Math.max(1, Math.min(h * .32, width * .08))
            const center = Math.max(x + radius, Math.min(x + w - radius, x + front))
            ctx.beginPath()
            ctx.arc(center, y + h / 2, radius, 0, Math.PI * 2)
            ctx.fillStyle = trackColor
            ctx.fill()
            ctx.strokeStyle = endColor
            ctx.lineWidth = 2
            ctx.stroke()
            ctx.strokeStyle = "#a0ffffff"
            ctx.lineWidth = .6
            ctx.stroke()
        }
    }
    onPaint: {
        const ctx = getContext("2d")
        if (ctx) drawProgress(ctx)
    }
}
