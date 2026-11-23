import QtQuick
import "IndicatorLighting.js" as Lighting

Canvas {
    id: tubes

    property Item sourceItem
    property Item progressItem
    property Item gridItem
    property Repeater workers
    property bool flowing: false
    property string progressAnimation: "classic"
    property string connectionAnimation: "classic"
    property string progressLighting: "polished"
    property string connectionLighting: "polished"
    property real phase: 0
    property real slowPhase: phase
    property real progressPhase: phase
    property bool paintingPaused: false
    property color progressStart: MaterialTheme.palette.accent
    property color progressEnd: MaterialTheme.palette.secondary
    property color connectionStart: progressStart
    property color connectionEnd: progressEnd
    readonly property var progressStartTone: MaterialTheme.neonTone(progressStart)
    readonly property var progressEndTone: MaterialTheme.neonTone(progressEnd)
    readonly property var connectionStartTone: MaterialTheme.neonTone(connectionStart)
    readonly property var connectionEndTone: MaterialTheme.neonTone(connectionEnd)
    readonly property var progressFinish: Lighting.style(progressLighting)
    readonly property var connectionFinish: Lighting.style(connectionLighting)
    readonly property bool animateFlow: visible && flowing && !paintingPaused && !MaterialTheme.reducedMotion
    // The content cards reserve this lane for the vertical portion.
    property real gutter: 12
    readonly property real mainDiameter: 13
    readonly property real branchDiameter: 10
    readonly property real hoseDiameter: 9

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
    onPhaseChanged: if (animateFlow && (progressAnimation === "classic"
                       || connectionAnimation === "classic" || connectionAnimation === "water")) requestPaint()
    onSlowPhaseChanged: if (animateFlow && (progressAnimation === "jelly" || connectionAnimation === "jelly")) requestPaint()
    onProgressPhaseChanged: if (animateFlow && progressAnimation === "water") requestPaint()
    onProgressAnimationChanged: requestPaint()
    onConnectionAnimationChanged: requestPaint()
    onProgressFinishChanged: requestPaint()
    onConnectionFinishChanged: requestPaint()
    onProgressStartChanged: requestPaint()
    onProgressEndChanged: requestPaint()
    onConnectionStartChanged: requestPaint()
    onConnectionEndChanged: requestPaint()

    Connections {
        target: tubes.workers
        function onCountChanged() { tubes.requestPaint() }
        function onItemAdded() { tubes.requestPaint() }
        function onItemRemoved() { tubes.requestPaint() }
    }

    Connections {
        target: tubes.gridItem
        function onXChanged() { tubes.requestPaint() }
        function onYChanged() { tubes.requestPaint() }
        function onWidthChanged() { tubes.requestPaint() }
        function onHeightChanged() { tubes.requestPaint() }
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

    function rail(ctx, points, offset, screenAligned = false) {
        ctx.beginPath()
        for (let index = 0; index < points.length; ++index) {
            const point = points[index]
            const before = points[index - 1]
            const after = points[index + 1]
            const normalX = (before ? Math.sign(before.y - point.y) : 0) + (after ? Math.sign(point.y - after.y) : 0)
            const normalY = (before ? Math.sign(point.x - before.x) : 0) + (after ? Math.sign(after.x - point.x) : 0)
            // Fixed lighting keeps the lower edge lit even where the pipe travels left.
            const x = point.x + offset * Math.sign(screenAligned ? Math.abs(normalX) : normalX)
            const y = point.y + offset * Math.sign(screenAligned ? Math.abs(normalY) : normalY)
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

    function pipeRail(ctx, points, offset, width, firstColor, lastColor, alpha, screenAligned = false) {
        rail(ctx, points, offset, screenAligned)
        ctx.lineWidth = width
        ctx.strokeStyle = pipeGradient(ctx, points[0], points[points.length - 1], firstColor, lastColor, alpha)
        ctx.stroke()
    }

    function sweptReflection(ctx, points, firstTone, lastTone, diameter, active, crossed) {
        const first = points[0]
        const last = points[points.length - 1]
        const slant = diameter * 1.35
        const gradient = ctx.createLinearGradient(first.x - slant, first.y + slant,
            last.x + slant, last.y - slant)
        const strength = active ? .68 : .44
        const stops = crossed ? [0, .27, .50, .74, 1] : [0, .24, .45, .67, 1]
        const fades = crossed ? [.18, 1, .53, .20, .06] : [.12, .45, 1, .51, .14]
        for (let index = 0; index < stops.length; ++index)
            gradient.addColorStop(stops[index], MaterialTheme.mix(firstTone.edge, lastTone.edge,
                stops[index], strength * fades[index]))
        rail(ctx, points, -diameter * (crossed ? .23 : .10), true)
        ctx.lineWidth = diameter * (crossed ? .18 : .63)
        ctx.strokeStyle = gradient
        ctx.stroke()
        if (crossed) {
            const reflected = ctx.createLinearGradient(last.x - slant, last.y - slant,
                first.x + slant, first.y + slant)
            for (let index = 0; index < stops.length; ++index)
                reflected.addColorStop(stops[index], MaterialTheme.mix(lastTone.glow, firstTone.glow,
                    stops[index], strength * fades[index]))
            rail(ctx, points, diameter * .24, true)
            ctx.lineWidth = diameter * .16
            ctx.strokeStyle = reflected
            ctx.stroke()
        }
    }

    function patternedReflection(ctx, points, firstTone, lastTone, diameter, active, optic) {
        const facets = optic === 6
        const specks = optic === 8
        const spacing = diameter * (facets ? 1.65 : specks ? 3.20 : .92)
        const first = points[0]
        const last = points[points.length - 1]
        ctx.beginPath()
        for (let edge = 1; edge < points.length; ++edge) {
            const start = points[edge - 1]
            const end = points[edge]
            const dx = end.x - start.x
            const dy = end.y - start.y
            const length = Math.hypot(dx, dy)
            if (length < diameter * .45)
                continue
            const ux = dx / length
            const uy = dy / length
            const nx = Math.abs(uy) * diameter
            const ny = Math.abs(ux) * diameter
            const count = Math.max(1, Math.min(28, Math.round(length / spacing)))
            const step = length / count
            for (let index = 0; index < count; ++index) {
                const x = start.x + ux * step * (index + .5)
                const y = start.y + uy * step * (index + .5)
                if (facets) {
                    const side = (index + edge) % 2 ? -1 : 1
                    const inner = side * .12
                    const outer = side * .43
                    const bevel = step * .39
                    ctx.moveTo(x - ux * bevel + nx * outer, y - uy * bevel + ny * outer)
                    ctx.lineTo(x + ux * bevel + nx * outer, y + uy * bevel + ny * outer)
                    ctx.lineTo(x + ux * bevel * .38 + nx * inner, y + uy * bevel * .38 + ny * inner)
                    ctx.lineTo(x - ux * bevel * .45 + nx * inner, y - uy * bevel * .45 + ny * inner)
                    ctx.closePath()
                } else if (specks) {
                    const side = (index + edge) % 3 === 1 ? .24 : -.29
                    const radius = diameter * (index % 3 === 0 ? .113 : .073)
                    const pointX = x + nx * side
                    const pointY = y + ny * side
                    ctx.moveTo(pointX + radius, pointY)
                    ctx.arc(pointX, pointY, radius, 0, Math.PI * 2)
                } else {
                    ctx.moveTo(x - nx * .40, y - ny * .40)
                    ctx.quadraticCurveTo(x + ux * diameter * .34, y + uy * diameter * .34,
                        x + nx * .40, y + ny * .40)
                }
            }
        }
        if (facets || specks) {
            const brightness = specks ? (active ? .90 : .58) : (active ? .58 : .34)
            ctx.fillStyle = pipeGradient(ctx, first, last, firstTone.edge, lastTone.edge, brightness)
            ctx.fill()
        } else {
            ctx.lineWidth = diameter * .15
            ctx.strokeStyle = pipeGradient(ctx, first, last, firstTone.core, lastTone.core, .64)
            ctx.stroke()
            ctx.lineWidth = Math.max(.65, diameter * .068)
            ctx.strokeStyle = pipeGradient(ctx, first, last, firstTone.edge, lastTone.edge, active ? .66 : .39)
            ctx.stroke()
        }
    }

    function spectralReflection(ctx, points, firstTone, lastTone, diameter, active) {
        const first = points[0]
        const last = points[points.length - 1]
        const alpha = active ? .84 : .58
        const spectrum = ctx.createLinearGradient(first.x, first.y, last.x, last.y)
        spectrum.addColorStop(0, MaterialTheme.mix(firstTone.edge, "#65ffe6", .34, alpha))
        spectrum.addColorStop(.34, MaterialTheme.mix(firstTone.edge, "#ac89ff", .44, alpha))
        spectrum.addColorStop(.68, MaterialTheme.mix(lastTone.edge, "#ffad82", .40, alpha))
        spectrum.addColorStop(1, MaterialTheme.mix(lastTone.edge, "#89d8ff", .34, alpha))
        rail(ctx, points, -diameter * .34, true)
        ctx.lineWidth = Math.max(.9, diameter * .12)
        ctx.strokeStyle = spectrum
        ctx.stroke()
        pipeRail(ctx, points, diameter * .32, Math.max(.7, diameter * .08),
            lastTone.edge, firstTone.edge, active ? .45 : .27, true)
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

    function flowingPulse(ctx, points, total, firstTone, lastTone, style, offset, diameter, primary) {
        const water = style === "water"
        const jelly = style === "jelly"
        const cycle = (jelly ? slowPhase : water && primary ? progressPhase : phase) / (Math.PI * 2)
        const pulseCount = water && total >= 60 ? (primary ? 4 : 2) : 1
        const span = Math.min(total, water ? (primary ? 32 : 22) : jelly ? 44 + 6 * Math.sin(slowPhase) : 30)
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
                ctx.lineWidth = diameter * (water && primary ? .56 : jelly ? .44 : .32)
                const gradient = ctx.createLinearGradient(startX, startY, endX, endY)
                gradient.addColorStop(0, MaterialTheme.rgba(firstTone.glow, 0))
                gradient.addColorStop(jelly ? .43 : .72, MaterialTheme.rgba(lastTone.glow, primary && water ? .99 : .72))
                gradient.addColorStop(1, MaterialTheme.rgba(lastTone.glow, .08))
                ctx.strokeStyle = gradient
                ctx.stroke()
                ctx.lineWidth = diameter * (primary && water ? .21 : .13)
                gradient.addColorStop(jelly ? .59 : .84, MaterialTheme.rgba(lastTone.edge, .98))
                ctx.stroke()
            }
        }
    }

    function pipe(ctx, points, firstTone, lastTone, active, offset, animation, finish, diameter, primary = false) {
        const first = points[0]
        const last = points[points.length - 1]
        const total = points.slice(1).reduce((length, point, index) =>
            length + Math.hypot(point.x - points[index].x, point.y - points[index].y), 0)
        if (total < 2)
            return

        const optic = finish.optic || 0
        const frost = optic === 1
        const chrome = optic === 2
        const underlit = optic === 3
        const smoke = optic === 4

        trace(ctx, points)
        ctx.lineJoin = "round"
        ctx.lineCap = "butt"

        ctx.lineWidth = diameter + finish.haloWidth * diameter * .45
        ctx.strokeStyle = pipeGradient(ctx, first, last, firstTone.glow, lastTone.glow, (active ? .22 : .08) * finish.halo)
        ctx.stroke()
        ctx.lineWidth = diameter
        ctx.strokeStyle = frost
            ? MaterialTheme.mix(firstTone.body, lastTone.body, .5, .65)
            : MaterialTheme.mix(firstTone.core, lastTone.core, .5, smoke ? .96 : .89)
        ctx.stroke()
        ctx.lineWidth = diameter * (frost ? .89 : .74)
        const tintAlpha = frost ? .80 : underlit ? .46 : (smoke || optic >= 11) ? .31 : 1
        ctx.strokeStyle = pipeGradient(ctx, first, last, firstTone.glow, lastTone.glow,
            (active ? .63 : .32) * finish.reflection * tintAlpha)
        ctx.stroke()
        ctx.lineWidth = diameter * (.34 + .12 * finish.depth)
        ctx.strokeStyle = frost
            ? pipeGradient(ctx, first, last, firstTone.body, lastTone.body, .33)
            : pipeGradient(ctx, first, last, firstTone.core, lastTone.core, .62 + .28 * finish.depth)
        ctx.stroke()
        ctx.lineWidth = diameter * .12
        ctx.strokeStyle = animation === "classic" && optic !== 12
            ? currentGradient(ctx, first, last, firstTone, lastTone, total, active, offset)
            : pipeGradient(ctx, first, last, firstTone.glow, lastTone.glow, optic === 12 ? .14 : (active ? .70 : .23))
        ctx.stroke()

        if (frost) {
            pipeRail(ctx, points, -diameter * .19, diameter * .32,
                firstTone.edge, lastTone.edge, active ? .37 : .23, true)
            pipeRail(ctx, points, diameter * .24, diameter * .26,
                firstTone.glow, lastTone.glow, active ? .28 : .16, true)
        } else if (chrome) {
            const firstMirror = MaterialTheme.mix(firstTone.edge, "#f3faff", .63, 1)
            const lastMirror = MaterialTheme.mix(lastTone.edge, "#f3faff", .63, 1)
            pipeRail(ctx, points, -diameter * .37, Math.max(.8, diameter * .10),
                firstMirror, lastMirror, active ? .97 : .76, true)
            pipeRail(ctx, points, -diameter * .18, Math.max(.65, diameter * .07),
                firstTone.edge, lastTone.edge, active ? .84 : .57, true)
            pipeRail(ctx, points, diameter * .36, Math.max(.65, diameter * .08),
                firstMirror, lastMirror, active ? .57 : .38, true)
        } else if (underlit) {
            pipeRail(ctx, points, -diameter * .33, Math.max(.65, diameter * .08),
                firstTone.edge, lastTone.edge, active ? .32 : .22, true)
            pipeRail(ctx, points, diameter * .24, diameter * .33,
                firstTone.glow, lastTone.glow, active ? .69 : .41, true)
            pipeRail(ctx, points, diameter * .38, Math.max(.8, diameter * .09),
                firstTone.edge, lastTone.edge, active ? .96 : .65, true)
        } else if (smoke) {
            pipeRail(ctx, points, -diameter * .35, Math.max(.8, diameter * .09),
                firstTone.edge, lastTone.edge, active ? .75 : .60, true)
            pipeRail(ctx, points, diameter * .36, Math.max(.75, diameter * .09),
                firstTone.glow, lastTone.glow, active ? .58 : .43, true)
        } else if (optic === 5 || optic === 7) {
            sweptReflection(ctx, points, firstTone, lastTone, diameter, active, optic === 7)
        } else if (optic === 6 || optic === 8 || optic === 9) {
            patternedReflection(ctx, points, firstTone, lastTone, diameter, active, optic)
        } else if (optic === 10) {
            spectralReflection(ctx, points, firstTone, lastTone, diameter, active)
        } else if (optic === 11) {
            pipeRail(ctx, points, 0, diameter * .54,
                firstTone.glow, lastTone.glow, active ? .80 : .44)
            pipeRail(ctx, points, 0, diameter * .22,
                firstTone.edge, lastTone.edge, active ? .63 : .35)
        } else if (optic === 12) {
            pipeRail(ctx, points, -diameter * .42, Math.max(.83, diameter * .09),
                firstTone.edge, lastTone.edge, active ? .95 : .69, true)
            pipeRail(ctx, points, diameter * .42, Math.max(.83, diameter * .09),
                firstTone.glow, lastTone.glow, active ? .87 : .62, true)
        } else {
            pipeRail(ctx, points, -diameter * .31, Math.max(.8, diameter * .11),
                firstTone.edge, lastTone.edge, (active ? .82 : .38) * finish.reflection)
            pipeRail(ctx, points, diameter * .28, Math.max(.75, diameter * .09),
                firstTone.glow, lastTone.glow, active ? .55 : .28)
            if (finish.caustic > 0)
                pipeRail(ctx, points, diameter * .19, Math.max(.55, diameter * .06),
                    firstTone.edge, lastTone.edge, active ? .77 : .30)
        }
        // The hose bore stays lit. Its own droplet carries the visible motion.
        if (total >= 16 && active && animateFlow && animation !== "none")
            flowingPulse(ctx, points, total, firstTone, lastTone, animation, offset, diameter, primary)
    }

    function nozzle(ctx, outlet, active) {
        const bore = hoseDiameter * .58
        const collar = hoseDiameter * .62
        const first = connectionStartTone
        const last = connectionEndTone
        const optic = connectionFinish.optic || 0
        const darkCollar = optic === 4 || optic >= 11
        ctx.beginPath()
        ctx.ellipse(outlet.x - collar, outlet.y - 4, collar * 2, 5)
        if (optic === 3) {
            const lowerLight = ctx.createLinearGradient(outlet.x, outlet.y - 4, outlet.x, outlet.y + 1)
            lowerLight.addColorStop(0, MaterialTheme.rgba(first.core, .92))
            lowerLight.addColorStop(.62, MaterialTheme.rgba(first.body, .82))
            lowerLight.addColorStop(1, MaterialTheme.rgba(last.glow, active ? .98 : .65))
            ctx.fillStyle = lowerLight
        } else {
            ctx.fillStyle = pipeGradient(ctx, Qt.point(outlet.x - collar, outlet.y), Qt.point(outlet.x + collar, outlet.y),
                darkCollar ? first.body : first.glow, darkCollar ? last.body : last.glow, active ? .92 : .48)
        }
        ctx.fill()
        ctx.lineWidth = .8
        const rimAlpha = optic === 12 ? (active ? .96 : .68) : (active ? .84 : .48) * connectionFinish.reflection
        ctx.strokeStyle = optic === 2 ? MaterialTheme.mix(last.edge, "#f3faff", .63, active ? .97 : .76)
            : MaterialTheme.rgba(last.edge, rimAlpha)
        ctx.stroke()
        ctx.beginPath()
        ctx.ellipse(outlet.x - bore * .5, outlet.y - 1.45, bore, 2.55)
        ctx.fillStyle = optic === 11 ? MaterialTheme.mix(first.glow, last.glow, .5, active ? .92 : .60)
            : MaterialTheme.mix(first.core, last.core, .5, .94)
        ctx.fill()
    }

    function droplet(ctx, outlet, surfaceY, cellWidth, index) {
        const jelly = connectionAnimation === "jelly"
        const cycle = Lighting.dropCycle(phase, slowPhase, index, connectionAnimation)
        const fall = surfaceY - outlet.y
        const radius = Math.min(2.9, cellWidth * .09, fall * .38)
        if (fall < 2.5 || radius < .85 || cycle >= Lighting.dropContact)
            return

        const first = connectionStartTone
        const last = connectionEndTone
        const ink = MaterialTheme.rgba
        ctx.save()
        // End at the animated meniscus. The vessel paints the impact inside its clip.
        const flight = cycle / Lighting.dropContact
        const y = outlet.y + (fall - radius * 1.26) * flight * flight
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
        ctx.strokeStyle = ink(last.glow, .22 * connectionFinish.halo)
        ctx.stroke()
        ctx.fillStyle = liquid
        ctx.fill()
        ctx.lineWidth = .54
        ctx.strokeStyle = ink(last.edge, .73 * connectionFinish.reflection)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(x - radius * .40, y - radius * .14)
        ctx.quadraticCurveTo(x - radius * .63, y + radius * .16, x - radius * .42, y + radius * .44)
        ctx.lineCap = "round"
        ctx.lineWidth = .48
        ctx.strokeStyle = ink(first.edge, .73)
        ctx.stroke()
        ctx.restore()
    }

    function connectionRows() {
        if (!gridItem || !workers || workers.count === 0 || gridItem.width <= 0)
            return []
        // Each row has its own header and each receiving cell its own outlet.
        const rows = []
        for (let index = 0; index < workers.count; ++index) {
            const worker = workers.itemAt(index)
            if (!worker || worker.width <= 0 || !worker.visible)
                continue
            const x = Number.isFinite(worker.liquidX) ? worker.liquidX : worker.width * Lighting.outletPosition
            const port = worker.mapToItem(tubes, x, -.85)
            const headerY = port.y - 13
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
        return rows.sort((left, right) => left.y - right.y)
    }

    function progressOutlet() {
        return progressItem ? progressItem.mapToItem(tubes, Math.min(8, progressItem.width * .12), progressItem.height * .5)
            : Qt.point(0, 0)
    }

    onPaint: {
        if (paintingPaused || !visible)
            return
        const ctx = getContext("2d")
        if (!ctx)
            return
        ctx.reset()
        ctx.clearRect(0, 0, width, height)
        if (!sourceItem || !progressItem || sourceItem.width <= 0 || progressItem.width <= 0)
            return

        const inlet = sourceItem.mapToItem(tubes, -6, sourceItem.height * .5)
        const outlet = progressOutlet()
        if (inlet.x <= gutter || outlet.x <= gutter || outlet.y <= inlet.y)
            return

        const upper = Qt.point(gutter, inlet.y)
        const split = Qt.point(gutter, outlet.y)
        pipe(ctx, [inlet, upper, split, outlet], progressStartTone, progressEndTone,
            flowing, 0, progressAnimation, progressFinish, mainDiameter, true)

        const rows = connectionRows()
        if (!rows.length)
            return

        const active = flowing && rows.some(row => row.receiving)
        pipe(ctx, [split, Qt.point(gutter, rows[rows.length - 1].y)], progressEndTone, connectionStartTone,
            active, 13, connectionAnimation, connectionFinish, branchDiameter)

        for (const row of rows) {
            const headerStart = Qt.point(gutter, row.y)
            const headerEnd = Qt.point(Math.max(...row.ports.map(port => port.point.x)), row.y)
            pipe(ctx, [headerStart, headerEnd], connectionStartTone, connectionEndTone,
                flowing && row.receiving, 20, connectionAnimation, connectionFinish, branchDiameter)
            for (let index = 0; index < row.ports.length; ++index) {
                const port = row.ports[index]
                const start = Qt.point(port.point.x, row.y)
                const receiving = flowing && port.receiving
                pipe(ctx, [start, port.point], connectionStartTone, connectionEndTone,
                    receiving, 29 + index * 3, connectionAnimation, connectionFinish, hoseDiameter)
                if (receiving && animateFlow && connectionAnimation !== "none")
                    droplet(ctx, port.point, port.surface, port.width, port.index)
                nozzle(ctx, port.point, receiving)
            }
        }
    }
}
