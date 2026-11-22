import QtQuick

Canvas {
    id: vessel

    property var value: null
    property bool receiving: false
    property real phase: 0
    property bool paintingPaused: false
    property string shape: "round"
    property string fillStyle: "sculpted"
    property string material: MaterialTheme.current
    property color startColor: profile.accent
    property color endColor: profile.secondary
    property color trackColor: profile.background
    readonly property var profile: MaterialTheme.profile(material)
    readonly property var startTone: MaterialTheme.neonTone(startColor)
    readonly property var endTone: MaterialTheme.neonTone(endColor)
    readonly property real amount: typeof value === "number" && Number.isFinite(value)
        ? Math.max(0, Math.min(1, value)) : 0
    readonly property real surfaceY: 1.7 + (height - 3.4) * (1 - amount)
    readonly property real waterPhase: receiving && !MaterialTheme.reducedMotion ? phase : 0
    readonly property bool sculpted: fillStyle === "sculpted"

    implicitWidth: 32
    implicitHeight: 38
    Accessible.ignored: true

    onAvailableChanged: requestPaint()
    onPaintingPausedChanged: if (!paintingPaused) requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onWaterPhaseChanged: requestPaint()
    onReceivingChanged: requestPaint()
    onValueChanged: requestPaint()
    onShapeChanged: requestPaint()
    onFillStyleChanged: requestPaint()
    onProfileChanged: requestPaint()
    onStartColorChanged: requestPaint()
    onEndColorChanged: requestPaint()
    onTrackColorChanged: requestPaint()

    Connections {
        target: MaterialTheme
        function onReducedMotionChanged() { vessel.requestPaint() }
    }

    function outline(ctx, w, h) {
        const left = 1.7
        const top = 1.7
        const right = w - left
        const bottom = h - top
        const corner = Math.min(w, h) * .19
        ctx.beginPath()
        if (shape === "square" || shape === "plain") {
            ctx.rect(left, top, right - left, bottom - top)
        } else if (["prism", "ice", "chamfer"].includes(shape)) {
            ctx.moveTo(left + corner, top)
            ctx.lineTo(right - corner, top)
            ctx.lineTo(right, top + corner)
            ctx.lineTo(right, bottom - corner)
            ctx.lineTo(right - corner, bottom)
            ctx.lineTo(left + corner, bottom)
            ctx.lineTo(left, bottom - corner)
            ctx.lineTo(left, top + corner)
        } else if (shape === "bubble") {
            const middle = w * .5
            ctx.moveTo(middle, top)
            ctx.bezierCurveTo(right + corner * .2, top, right, h * .35, right, h * .52)
            ctx.bezierCurveTo(right, bottom, right - corner, bottom, middle, bottom)
            ctx.bezierCurveTo(left + corner, bottom, left, bottom, left, h * .52)
            ctx.bezierCurveTo(left, h * .35, left - corner * .2, top, middle, top)
        } else {
            ctx.moveTo(left + corner, top)
            ctx.lineTo(right - corner, top)
            ctx.quadraticCurveTo(right, top, right, top + corner)
            ctx.lineTo(right, bottom - corner)
            ctx.quadraticCurveTo(right, bottom, right - corner, bottom)
            ctx.lineTo(left + corner, bottom)
            ctx.quadraticCurveTo(left, bottom, left, bottom - corner)
            ctx.lineTo(left, top + corner)
            ctx.quadraticCurveTo(left, top, left + corner, top)
        }
        ctx.closePath()
    }

    function traceSurface(ctx, w, y, amplitude) {
        ctx.beginPath()
        ctx.moveTo(0, y)
        ctx.bezierCurveTo(w * .22, y - amplitude * Math.cos(waterPhase), w * .36, y - amplitude,
                          w * .53, y + Math.sin(waterPhase) * amplitude * .65)
        ctx.bezierCurveTo(w * .75, y + amplitude, w * .88, y, w, y - amplitude * .25)
    }

    onPaint: {
        if (paintingPaused)
            return
        const w = width
        const h = height
        const ctx = getContext("2d")
        if (!ctx)
            return
        ctx.reset()
        ctx.clearRect(0, 0, w, h)
        if (w < 5 || h < 5)
            return

        const color = MaterialTheme.rgba
        const first = startTone
        const last = endTone
        const track = ctx.createLinearGradient(0, 0, w, h)
        track.addColorStop(0, color(profile.upper, profile.light ? .37 : .16))
        track.addColorStop(.30, color(trackColor, .16))
        track.addColorStop(.70, color(trackColor, .23))
        track.addColorStop(1, color(last.core, profile.light ? .53 : .37))
        outline(ctx, w, h)
        ctx.fillStyle = track
        ctx.fill()

        if (amount > 0) {
            ctx.save()
            ctx.clip()
            const depth = h - surfaceY
            const amplitude = amount < 1 ? Math.min(depth * .26, receiving ? h * .061 : h * .026) : 0
            const surface = surfaceY + Math.sin(waterPhase) * amplitude * .3

            // Clip both the dense liquid and its reflections to the moving meniscus.
            traceSurface(ctx, w, surface, amplitude)
            ctx.lineTo(w, h)
            ctx.lineTo(0, h)
            ctx.closePath()
            ctx.save()
            ctx.clip()

            const water = ctx.createLinearGradient(0, surface, w * .32, h)
            water.addColorStop(0, color(first.glow, .91))
            water.addColorStop(.17, color(first.body, .97))
            water.addColorStop(.46, color(first.core, 1))
            water.addColorStop(.76, color(last.core, sculpted ? .99 : .94))
            water.addColorStop(.94, color(last.body, .99))
            water.addColorStop(1, color(last.glow, .85))
            ctx.fillStyle = water
            ctx.fillRect(0, 0, w, h)

            const refraction = ctx.createLinearGradient(0, 0, w, 0)
            refraction.addColorStop(0, color(first.glow, .40))
            refraction.addColorStop(.045, color(first.edge, .43))
            refraction.addColorStop(.13, color(first.glow, .18))
            refraction.addColorStop(.23, "transparent")
            refraction.addColorStop(.76, "transparent")
            refraction.addColorStop(.91, color(last.glow, .27))
            refraction.addColorStop(1, color(last.body, .65))
            ctx.fillStyle = refraction
            ctx.fillRect(0, 0, w, h)
            ctx.restore()

            if (amount < 1) {
                traceSurface(ctx, w, surface, amplitude)
                const glow = ctx.createLinearGradient(0, 0, w, 0)
                glow.addColorStop(0, color(first.glow, receiving ? .65 : .44))
                glow.addColorStop(1, color(last.glow, receiving ? .69 : .48))
                ctx.lineWidth = Math.min(4.5, w * .16)
                ctx.strokeStyle = glow
                ctx.stroke()
                const edge = ctx.createLinearGradient(0, 0, w, 0)
                edge.addColorStop(0, color(first.edge, .96))
                edge.addColorStop(1, color(last.edge, .92))
                ctx.lineWidth = Math.min(1.12, w * .075)
                ctx.strokeStyle = edge
                ctx.stroke()
            }
            ctx.restore()
        }

        outline(ctx, w, h)
        if (amount > 0) {
            const halo = ctx.createLinearGradient(0, Math.max(0, surfaceY - 2), 0, h)
            halo.addColorStop(0, color(first.glow, 0))
            halo.addColorStop(.43, color(first.glow, receiving ? .33 : .23))
            halo.addColorStop(1, color(last.glow, receiving ? .59 : .40))
            ctx.lineWidth = 3.2
            ctx.strokeStyle = halo
            ctx.stroke()
        }
        const rim = ctx.createLinearGradient(0, 0, w, h)
        rim.addColorStop(0, color(profile.upper, profile.light ? .78 : .56))
        rim.addColorStop(.47, color(profile.upper, .19))
        rim.addColorStop(1, color(amount > 0 ? last.edge : profile.upper, amount > 0 ? .85 : .34))
        ctx.lineWidth = .8
        ctx.strokeStyle = rim
        ctx.stroke()
    }
}
