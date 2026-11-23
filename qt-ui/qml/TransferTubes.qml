import QtQuick

Canvas {
    id: tubes

    property Item sourceItem
    property Item progressItem
    property Item gridItem
    property Repeater workers
    property bool flowing: false
    property string progressAnimation: "classic"
    property string connectionAnimation: "classic"
    property real phase: 0
    property real slowPhase: phase
    property bool paintingPaused: false
    property color progressStart: MaterialTheme.palette.accent
    property color progressEnd: MaterialTheme.palette.secondary
    property color connectionStart: progressStart
    property color connectionEnd: progressEnd
    readonly property var progressStartTone: MaterialTheme.neonTone(progressStart)
    readonly property var progressEndTone: MaterialTheme.neonTone(progressEnd)
    readonly property var connectionStartTone: MaterialTheme.neonTone(connectionStart)
    readonly property var connectionEndTone: MaterialTheme.neonTone(connectionEnd)
    // The content cards reserve this lane for the vertical portion.
    property real gutter: 8

    Accessible.ignored: true

    onAvailableChanged: requestPaint()
    onPaintingPausedChanged: if (!paintingPaused) requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onVisibleChanged: requestPaint()
    onSourceItemChanged: requestPaint()
    onProgressItemChanged: requestPaint()
    onGridItemChanged: requestPaint()
    onWorkersChanged: requestPaint()
    onFlowingChanged: requestPaint()
    onPhaseChanged: if (flowing && !MaterialTheme.reducedMotion && (["classic", "water"].includes(progressAnimation)
                       || ["classic", "water"].includes(connectionAnimation))) requestPaint()
    onSlowPhaseChanged: if (flowing && !MaterialTheme.reducedMotion && (progressAnimation === "jelly"
                           || connectionAnimation === "jelly")) requestPaint()
    onProgressAnimationChanged: requestPaint()
    onConnectionAnimationChanged: requestPaint()
    onProgressStartChanged: requestPaint()
    onProgressEndChanged: requestPaint()
    onConnectionStartChanged: requestPaint()
    onConnectionEndChanged: requestPaint()

    Connections {
        target: tubes.workers
        function onCountChanged() { tubes.requestPaint() }
    }

    Connections {
        target: MaterialTheme
        function onReducedMotionChanged() { tubes.requestPaint() }
    }

    function trace(ctx, points) {
        ctx.beginPath()
        ctx.moveTo(points[0].x, points[0].y)
        for (let index = 1; index < points.length; ++index)
            ctx.lineTo(points[index].x, points[index].y)
    }

    function rail(ctx, points, offset) {
        ctx.beginPath()
        for (let index = 0; index < points.length; ++index) {
            const point = points[index]
            const before = points[index - 1]
            const after = points[index + 1]
            const normalX = (before ? Math.sign(before.y - point.y) : 0) + (after ? Math.sign(point.y - after.y) : 0)
            const normalY = (before ? Math.sign(point.x - before.x) : 0) + (after ? Math.sign(after.x - point.x) : 0)
            const x = point.x + offset * Math.sign(normalX)
            const y = point.y + offset * Math.sign(normalY)
            if (index === 0)
                ctx.moveTo(x, y)
            else
                ctx.lineTo(x, y)
        }
    }

    function pipeGradient(ctx, first, last, fromColor, toColor, alpha) {
        if (Math.abs(last.x - first.x) + Math.abs(last.y - first.y) < 8 || Qt.colorEqual(fromColor, toColor))
            return MaterialTheme.rgba(toColor, alpha)
        const fill = ctx.createLinearGradient(first.x, first.y, last.x, last.y)
        fill.addColorStop(0, MaterialTheme.rgba(fromColor, alpha))
        fill.addColorStop(1, MaterialTheme.rgba(toColor, alpha))
        return fill
    }

    function currentGradient(ctx, first, last, firstTone, lastTone, length, active, offset) {
        if (!active || MaterialTheme.reducedMotion || length < 8)
            return pipeGradient(ctx, first, last, firstTone.glow, lastTone.glow, active ? .72 : .23)

        // A broad reflection travels along the continuous seam and fades at either end.
        const cycle = (phase / (Math.PI * 2) + 1 - offset / 100) % 1
        const middle = .12 + cycle * .76
        const reflectivity = .15 * Math.sin(Math.PI * cycle)
        const fluid = ctx.createLinearGradient(first.x, first.y, last.x, last.y)
        fluid.addColorStop(0, MaterialTheme.rgba(firstTone.glow, .72))
        fluid.addColorStop(Math.max(.01, middle - .29), MaterialTheme.mix(firstTone.glow, lastTone.glow,
            Math.max(0, middle - .29), .72))
        fluid.addColorStop(middle, MaterialTheme.mix(firstTone.glow, lastTone.glow, middle, .72 + reflectivity))
        fluid.addColorStop(Math.min(.99, middle + .29), MaterialTheme.mix(firstTone.glow, lastTone.glow,
            Math.min(1, middle + .29), .72))
        fluid.addColorStop(1, MaterialTheme.rgba(lastTone.glow, .72))
        return fluid
    }

    function flowingPulse(ctx, points, total, firstTone, lastTone, style, offset) {
        const water = style === "water"
        const jelly = style === "jelly"
        const cycle = (jelly ? slowPhase : phase) / (Math.PI * 2)
        const pulseCount = water && total >= 60 ? 3 : 1
        const span = Math.min(total, water ? 22 : jelly ? 44 + 6 * Math.sin(slowPhase) : 30)
        for (let index = 0; index < pulseCount; ++index) {
            const position = ((cycle * (water ? 2 : 1) + index / pulseCount + 1 - offset / 100) % 1)
                * (total + span)
            let distance = 0
            for (let edge = 1; edge < points.length; ++edge) {
                const first = points[edge - 1]
                const last = points[edge]
                const dx = last.x - first.x
                const dy = last.y - first.y
                const spanLength = Math.hypot(dx, dy)
                const start = Math.max(0, position - span - distance)
                const end = Math.min(spanLength, position - distance)
                distance += spanLength
                if (end - start < .2)
                    continue
                const startX = first.x + dx * start / spanLength
                const startY = first.y + dy * start / spanLength
                const endX = first.x + dx * end / spanLength
                const endY = first.y + dy * end / spanLength
                ctx.beginPath()
                ctx.moveTo(startX, startY)
                ctx.lineTo(endX, endY)
                ctx.lineCap = "round"
                ctx.lineWidth = jelly ? 4.1 : 3.1
                const gradient = ctx.createLinearGradient(startX, startY, endX, endY)
                gradient.addColorStop(0, MaterialTheme.rgba(firstTone.glow, 0))
                gradient.addColorStop(jelly ? .43 : .72, MaterialTheme.rgba(lastTone.glow, jelly ? .72 : .61))
                gradient.addColorStop(1, MaterialTheme.rgba(lastTone.glow, .08))
                ctx.strokeStyle = gradient
                ctx.stroke()
                ctx.lineWidth = jelly ? 1.5 : 1.2
                gradient.addColorStop(jelly ? .59 : .84, MaterialTheme.rgba(lastTone.edge, .95))
                ctx.stroke()
            }
        }
    }

    function pipe(ctx, points, firstTone, lastTone, active, offset, style) {
        const first = points[0]
        const last = points[points.length - 1]
        const total = points.slice(1).reduce((length, point, index) =>
            length + Math.hypot(point.x - points[index].x, point.y - points[index].y), 0)
        if (total < 2)
            return

        trace(ctx, points)
        ctx.lineJoin = "round"
        ctx.lineCap = "butt"

        ctx.lineWidth = 8.8
        ctx.strokeStyle = pipeGradient(ctx, first, last, firstTone.glow, lastTone.glow, active ? .23 : .07)
        ctx.stroke()
        ctx.lineWidth = 6.4
        ctx.strokeStyle = MaterialTheme.mix(firstTone.core, lastTone.core, .5, .89)
        ctx.stroke()
        ctx.lineWidth = 4.9
        ctx.strokeStyle = pipeGradient(ctx, first, last, firstTone.glow, lastTone.glow, active ? .55 : .24)
        ctx.stroke()
        ctx.lineWidth = 3.15
        ctx.strokeStyle = pipeGradient(ctx, first, last, firstTone.core, lastTone.core, .88)
        ctx.stroke()
        ctx.lineWidth = 1.05
        ctx.strokeStyle = style === "classic" ? currentGradient(ctx, first, last, firstTone, lastTone, total, active, offset)
            : pipeGradient(ctx, first, last, firstTone.glow, lastTone.glow, active ? .72 : .23)
        ctx.stroke()

        rail(ctx, points, -1.9)
        ctx.lineWidth = .83
        ctx.strokeStyle = pipeGradient(ctx, first, last, firstTone.edge, lastTone.edge, active ? .72 : .28)
        ctx.stroke()
        rail(ctx, points, 1.70)
        ctx.lineWidth = .92
        ctx.strokeStyle = pipeGradient(ctx, first, last, firstTone.glow, lastTone.glow, active ? .53 : .20)
        ctx.stroke()
        if (active && !MaterialTheme.reducedMotion && style !== "none")
            flowingPulse(ctx, points, total, firstTone, lastTone, style, offset)
    }

    function droplet(ctx, outlet, surfaceY, cellWidth, index) {
        const water = connectionAnimation === "water"
        const jelly = connectionAnimation === "jelly"
        const cycle = ((jelly ? slowPhase : phase) / (Math.PI * 2) * (water ? 2 : 1) + index * .381966) % 1
        const fall = surfaceY - outlet.y
        const radius = Math.min(2.3, cellWidth * .09)
        if (fall < 3 || radius < 1)
            return

        const first = connectionStartTone
        const last = connectionEndTone
        const ink = MaterialTheme.rgba
        ctx.save()
        // The drop separates from the outlet, accelerates, then breaks at the waterline.
        if (cycle < .69) {
            const flight = cycle / .69
            const y = outlet.y + fall * flight * flight
            const x = outlet.x
            const length = radius * (jelly ? 2.2 + flight : 1.40 + flight * .75)
            const liquid = ctx.createLinearGradient(x - radius, y - radius, x + radius, y + radius)
            liquid.addColorStop(0, first.glow)
            liquid.addColorStop(.31, first.body)
            liquid.addColorStop(.65, last.core)
            liquid.addColorStop(1, last.glow)
            ctx.globalAlpha = Math.min(1, cycle * 22)
            ctx.beginPath()
            ctx.moveTo(x, y - length)
            ctx.bezierCurveTo(x - radius * .36, y - radius, x - radius, y - radius * .15, x - radius, y + radius * .30)
            ctx.bezierCurveTo(x - radius, y + radius * 1.58, x + radius, y + radius * 1.58, x + radius, y + radius * .30)
            ctx.bezierCurveTo(x + radius, y - radius * .18, x + radius * .36, y - radius, x, y - length)
            ctx.closePath()
            ctx.lineWidth = 1.8
            ctx.strokeStyle = ink(last.glow, .18)
            ctx.stroke()
            ctx.fillStyle = liquid
            ctx.fill()
            ctx.lineWidth = .54
            ctx.strokeStyle = ink(last.edge, .64)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(x - radius * .40, y - radius * .14)
            ctx.quadraticCurveTo(x - radius * .63, y + radius * .16, x - radius * .42, y + radius * .44)
            ctx.lineCap = "round"
            ctx.lineWidth = .48
            ctx.strokeStyle = ink(first.edge, .73)
            ctx.stroke()
        } else {
            const splash = (cycle - .69) / .31
            const span = radius * (1 + splash * 1.25)
            ctx.globalAlpha = (1 - splash) * .58
            ctx.beginPath()
            ctx.moveTo(outlet.x - span, surfaceY)
            ctx.quadraticCurveTo(outlet.x, surfaceY - radius * (1 - splash), outlet.x + span, surfaceY)
            ctx.lineWidth = Math.max(.52, radius * .30)
            ctx.strokeStyle = last.edge
            ctx.stroke()
        }
        ctx.restore()
    }

    onPaint: {
        if (paintingPaused)
            return
        const ctx = getContext("2d")
        if (!ctx)
            return
        ctx.reset()
        ctx.clearRect(0, 0, width, height)
        if (!sourceItem || !progressItem || sourceItem.width <= 0 || progressItem.width <= 0)
            return

        const inlet = sourceItem.mapToItem(tubes, -4, sourceItem.height * .5)
        const outlet = progressItem.mapToItem(tubes, -2, progressItem.height * .5)
        if (inlet.x <= gutter || outlet.x <= gutter || outlet.y <= inlet.y)
            return

        const upper = Qt.point(gutter, inlet.y)
        const split = Qt.point(gutter, outlet.y)
        pipe(ctx, [inlet, upper, split, outlet], progressStartTone, progressEndTone, flowing, 0, progressAnimation)

        if (!gridItem || !workers || workers.count === 0 || gridItem.width <= 0)
            return

        // Each row has its own header and each receiving cell its own outlet.
        // Route the shared left trunk once so overlapping rows stay clear.
        const rows = []
        for (let index = 0; index < workers.count; ++index) {
            const worker = workers.itemAt(index)
            if (!worker || worker.width <= 0 || !worker.visible)
                continue
            const port = worker.mapToItem(tubes, worker.width * .59, -6)
            const headerY = port.y - 4
            const surfaceY = Number.isFinite(worker.liquidSurface) ? worker.liquidSurface : worker.height * .76
            const surface = worker.mapToItem(tubes, 0, surfaceY).y
            let row = rows.find(entry => Math.abs(entry.y - headerY) < 1)
            if (!row) {
                row = {y: headerY, ports: [], receiving: false}
                rows.push(row)
            }
            row.ports.push({point: port, surface: surface, width: worker.width, index: index, receiving: worker.receiving})
            row.receiving = row.receiving || worker.receiving
        }
        if (!rows.length)
            return

        const active = flowing && rows.some(row => row.receiving)
        pipe(ctx, [split, Qt.point(gutter, rows[rows.length - 1].y)], progressEndTone, connectionStartTone, active, 13, connectionAnimation)

        for (const row of rows) {
            const headerStart = Qt.point(gutter, row.y)
            const headerEnd = Qt.point(row.ports[row.ports.length - 1].point.x, row.y)
            pipe(ctx, [headerStart, headerEnd], connectionStartTone, connectionEndTone, flowing && row.receiving, 20, connectionAnimation)
            for (let index = 0; index < row.ports.length; ++index) {
                const port = row.ports[index]
                const start = Qt.point(port.point.x, row.y)
                const receiving = flowing && port.receiving
                pipe(ctx, [start, port.point], connectionStartTone, connectionEndTone, receiving, 29 + index * 3, connectionAnimation)
                if (receiving && connectionAnimation !== "none" && !MaterialTheme.reducedMotion)
                    droplet(ctx, port.point, port.surface, port.width, port.index)
            }
        }
    }
}
