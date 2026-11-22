import QtQuick

Canvas {
    id: tubes

    property Item sourceItem
    property Item progressItem
    property Item gridItem
    property Repeater workers
    property bool flowing: false
    property real phase: 0
    property color progressStart: MaterialTheme.palette.accent
    property color progressEnd: MaterialTheme.palette.secondary
    property color connectionStart: progressStart
    property color connectionEnd: progressEnd
    // The content cards reserve this lane for the vertical portion.
    property real gutter: 8

    Accessible.ignored: true

    onAvailableChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onVisibleChanged: requestPaint()
    onSourceItemChanged: requestPaint()
    onProgressItemChanged: requestPaint()
    onGridItemChanged: requestPaint()
    onWorkersChanged: requestPaint()
    onFlowingChanged: requestPaint()
    onPhaseChanged: if (flowing && !MaterialTheme.reducedMotion) requestPaint()
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

    function pointAt(points, distance) {
        for (let index = 1; index < points.length; ++index) {
            const first = points[index - 1]
            const second = points[index]
            const length = Math.hypot(second.x - first.x, second.y - first.y)
            if (distance <= length && length > 0) {
                const ratio = Math.max(0, distance / length)
                return Qt.point(first.x + (second.x - first.x) * ratio, first.y + (second.y - first.y) * ratio)
            }
            distance -= length
        }
        return points[points.length - 1]
    }

    function trace(ctx, points) {
        ctx.beginPath()
        ctx.moveTo(points[0].x, points[0].y)
        for (let index = 1; index < points.length; ++index)
            ctx.lineTo(points[index].x, points[index].y)
    }

    function pipe(ctx, points, beginColor, endColor, active, offset) {
        const ink = MaterialTheme.rgba
        const first = points[0]
        const last = points[points.length - 1]
        const total = points.slice(1).reduce((length, point, index) =>
            length + Math.hypot(point.x - points[index].x, point.y - points[index].y), 0)
        if (total < 2)
            return

        const fluid = ctx.createLinearGradient(first.x, first.y, last.x, last.y)
        fluid.addColorStop(0, ink(beginColor, active ? .93 : .23))
        fluid.addColorStop(1, ink(endColor, active ? .96 : .38))
        trace(ctx, points)
        ctx.lineJoin = "round"
        ctx.lineCap = "round"
        ctx.lineWidth = 9.2
        ctx.strokeStyle = ink(endColor, active ? .47 : .13)
        ctx.stroke()
        ctx.lineWidth = 6
        ctx.strokeStyle = "rgba(7,19,37,0.74)"
        ctx.stroke()
        ctx.lineWidth = 3.8
        ctx.strokeStyle = fluid
        ctx.stroke()
        ctx.lineWidth = 1
        ctx.strokeStyle = MaterialTheme.mix(endColor, "#e2faff", .72, active ? .69 : .19)
        ctx.stroke()

        if (active && !MaterialTheme.reducedMotion) {
            // Individual water packets keep moving through the elbows.
            const interval = 38
            const movement = phase / (Math.PI * 2) * interval * 3
            for (let at = (movement + offset) % interval; at < total; at += interval) {
                const streak = []
                const length = Math.min(12, total - at)
                for (let step = 0; step < length; step += 2)
                    streak.push(pointAt(points, at + step))
                streak.push(pointAt(points, at + length))
                if (streak.length < 2)
                    continue
                trace(ctx, streak)
                ctx.lineWidth = 5.4
                ctx.strokeStyle = ink(endColor, .80)
                ctx.stroke()
                ctx.lineWidth = 1.9
                ctx.strokeStyle = MaterialTheme.mix(endColor, "#f5fdff", .76, .98)
                ctx.stroke()
            }
        }
    }

    function droplet(ctx, outlet, surfaceY, cellWidth, index) {
        const cycle = (phase / (Math.PI * 2) + index * .381966) % 1
        const fall = surfaceY - outlet.y
        const radius = Math.min(3.5, cellWidth * .12)
        if (fall < 3 || radius < 1)
            return

        ctx.save()
        // The drop separates from the outlet, accelerates, then breaks at the waterline.
        if (cycle < .69) {
            const flight = cycle / .69
            const y = outlet.y + fall * flight * flight
            const x = outlet.x
            const ink = ctx.createLinearGradient(x - radius, y - radius, x + radius, y + radius)
            ink.addColorStop(0, MaterialTheme.mix(connectionStart, "#eafdff", .58, 1))
            ink.addColorStop(.55, connectionStart)
            ink.addColorStop(1, connectionEnd)
            ctx.globalAlpha = Math.min(1, cycle * 22)
            ctx.beginPath()
            ctx.moveTo(x, y - radius * (1.15 + flight * .7))
            ctx.bezierCurveTo(x - radius * .36, y - radius, x - radius, y - radius * .15, x - radius, y + radius * .30)
            ctx.bezierCurveTo(x - radius, y + radius * 1.58, x + radius, y + radius * 1.58, x + radius, y + radius * .30)
            ctx.bezierCurveTo(x + radius, y - radius * .18, x + radius * .36, y - radius, x, y - radius * (1.15 + flight * .7))
            ctx.closePath()
            ctx.lineWidth = 3
            ctx.strokeStyle = MaterialTheme.rgba(connectionEnd, .40)
            ctx.stroke()
            ctx.lineWidth = .8
            ctx.strokeStyle = MaterialTheme.mix(connectionEnd, "#08192d", .49, .85)
            ctx.fillStyle = ink
            ctx.fill()
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(x - radius * .34, y + radius * .25, radius * .33, 0, Math.PI * 2)
            ctx.fillStyle = "rgba(238,253,255,0.87)"
            ctx.fill()
        } else {
            const splash = (cycle - .69) / .31
            const span = radius * (1 + splash * 1.45)
            ctx.globalAlpha = (1 - splash) * .79
            ctx.beginPath()
            ctx.moveTo(outlet.x - span, surfaceY)
            ctx.quadraticCurveTo(outlet.x, surfaceY - radius * (1 - splash), outlet.x + span, surfaceY)
            ctx.lineWidth = Math.max(.65, radius * .38)
            ctx.strokeStyle = MaterialTheme.mix(connectionEnd, "#f1fdff", .57, 1)
            ctx.stroke()
        }
        ctx.restore()
    }

    onPaint: {
        const ctx = getContext("2d")
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
        pipe(ctx, [inlet, upper, split, outlet], progressStart, progressEnd, flowing, 0)

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
        pipe(ctx, [split, Qt.point(gutter, rows[rows.length - 1].y)], progressEnd, connectionStart, active, 13)

        for (const row of rows) {
            const headerStart = Qt.point(gutter, row.y)
            const headerEnd = Qt.point(row.ports[row.ports.length - 1].point.x, row.y)
            pipe(ctx, [headerStart, headerEnd], connectionStart, connectionEnd, flowing && row.receiving, 20)
            for (let index = 0; index < row.ports.length; ++index) {
                const port = row.ports[index]
                const start = Qt.point(port.point.x, row.y)
                const receiving = flowing && port.receiving
                pipe(ctx, [start, port.point], connectionStart, connectionEnd, receiving, 29 + index * 3)
                if (receiving && !MaterialTheme.reducedMotion)
                    droplet(ctx, port.point, port.surface, port.width, port.index)
            }
        }
    }
}
