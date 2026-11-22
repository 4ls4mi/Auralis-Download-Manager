import QtQuick

Canvas {
    id: vessel

    property var value: null
    property bool receiving: false
    property real phase: 0
    property string shape: "round"
    property string fillStyle: "sculpted"
    property string material: MaterialTheme.current
    property color startColor: profile.accent
    property color endColor: profile.secondary
    property color trackColor: profile.background
    readonly property var profile: MaterialTheme.profile(material)
    readonly property real amount: typeof value === "number" && Number.isFinite(value)
        ? Math.max(0, Math.min(1, value)) : 0
    readonly property real surfaceY: 1.7 + (height - 3.4) * (1 - amount)
    readonly property real waterPhase: receiving && !MaterialTheme.reducedMotion ? phase : 0
    readonly property bool sculpted: fillStyle === "sculpted"

    implicitWidth: 32
    implicitHeight: 38
    Accessible.ignored: true

    onAvailableChanged: requestPaint()
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
        const w = width
        const h = height
        const ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, w, h)
        if (w < 5 || h < 5)
            return

        const color = MaterialTheme.rgba
        const frost = "rgba(235,250,255,0.86)"
        const track = ctx.createLinearGradient(0, 0, w, h)
        track.addColorStop(0, color(profile.upper, .30))
        track.addColorStop(.24, color(trackColor, .18))
        track.addColorStop(.69, color(trackColor, .18))
        track.addColorStop(1, color(endColor, .34))
        outline(ctx, w, h)
        ctx.fillStyle = track
        ctx.fill()

        if (amount > 0) {
            ctx.save()
            ctx.clip()

            const depth = h - surfaceY
            const amplitude = amount < 1 ? Math.min(depth * .30, receiving ? h * .087 : h * .037) : 0
            const surface = surfaceY + Math.sin(waterPhase) * amplitude * .3
            traceSurface(ctx, w, surface, amplitude)

            ctx.lineJoin = "round"
            const water = ctx.createLinearGradient(0, surfaceY, w * .32, h)
            water.addColorStop(0, color(endColor, .94))
            water.addColorStop(.28, color(startColor, .87))
            water.addColorStop(.70, color(startColor, sculpted ? .64 : .81))
            water.addColorStop(1, color(endColor, .89))
            ctx.save()
            ctx.lineTo(w, h)
            ctx.lineTo(0, h)
            ctx.closePath()
            ctx.fillStyle = water
            ctx.fill()
            ctx.restore()

            if (amount < 1) {
                traceSurface(ctx, w, surface, amplitude)
                ctx.lineWidth = sculpted ? 3.4 : 3
                ctx.strokeStyle = color(endColor, .66)
                ctx.stroke()
                ctx.lineWidth = 1.15
                ctx.strokeStyle = frost
                ctx.stroke()
            }

            // A narrow side reflection gives the moving liquid depth.
            const refraction = ctx.createLinearGradient(0, 0, w, 0)
            refraction.addColorStop(0, color(profile.upper, .42))
            refraction.addColorStop(.20, color(profile.upper, .06))
            refraction.addColorStop(.62, "transparent")
            refraction.addColorStop(1, color(endColor, .55))
            ctx.fillStyle = refraction
            ctx.fillRect(0, surfaceY + amplitude, w, depth)

            if (receiving && !MaterialTheme.reducedMotion && depth > 7) {
                for (let index = 0; index < 2; ++index) {
                    const rise = (waterPhase / (Math.PI * 2) + index * .54) % 1
                    const x = w * (.35 + index * .28 + .08 * Math.sin(rise * 6))
                    const y = h - 3 - rise * (depth - 4)
                    ctx.beginPath()
                    ctx.arc(x, y, index === 0 ? 1.65 : 1.1, 0, Math.PI * 2)
                    ctx.lineWidth = .8
                    ctx.strokeStyle = frost
                    ctx.stroke()
                }
            }
            ctx.restore()
        }

        outline(ctx, w, h)
        ctx.lineWidth = receiving ? 2.2 : 1.4
        ctx.strokeStyle = color(endColor, receiving ? .62 : .26)
        ctx.stroke()
        ctx.lineWidth = .8
        ctx.strokeStyle = color(profile.upper, amount > 0 ? .73 : .48)
        ctx.stroke()
    }
}
