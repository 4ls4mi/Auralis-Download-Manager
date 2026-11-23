import QtQuick
import QtQuick.Window

Canvas {
    id: vessel

    property var value: null
    property bool receiving: false
    property real phase: 0
    property string animationStyle: "classic"
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
    readonly property bool water: animationStyle === "water"
    readonly property bool jelly: animationStyle === "jelly"
    readonly property bool movingLiquid: visible && receiving && amount > 0 && !paintingPaused
        && !MaterialTheme.reducedMotion && animationStyle !== "none"
        && (!Window.window || (Window.window.visible && Window.window.visibility !== Window.Minimized))
    readonly property real waterPhase: !movingLiquid ? 0 : water ? phase * 2 : jelly ? jellyPhase : phase
    readonly property bool sculpted: fillStyle === "sculpted"
    property real lastPhase: 0
    property real jellyPhase: 0

    implicitWidth: 32
    implicitHeight: 38
    Accessible.ignored: true

    onAvailableChanged: requestPaint()
    onPaintingPausedChanged: if (!paintingPaused) requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()
    onAnimationStyleChanged: requestPaint()
    onWaterPhaseChanged: if (visible && !paintingPaused) requestPaint()
    onPhaseChanged: {
        if (movingLiquid && jelly) {
            const turn = Math.PI * 2
            const advance = (phase - lastPhase + turn) % turn
            jellyPhase = (jellyPhase + advance / 3) % turn
        }
        lastPhase = phase
    }
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

    function traceSurface(ctx, w, y, amplitude, offset = 0) {
        const motion = waterPhase + offset
        const sway = Math.sin(motion)
        const lift = Math.cos(motion)
        ctx.beginPath()
        if (water) {
            ctx.moveTo(0, y + amplitude * lift * .43)
            ctx.bezierCurveTo(w * .15, y - amplitude * (.82 + sway * .56),
                w * .30, y - amplitude * (.49 + lift * .56), w * .49, y + amplitude * sway * .48)
            ctx.bezierCurveTo(w * .67, y + amplitude * (.86 - lift * .50),
                w * .83, y - amplitude * (.12 - sway * .86), w, y - amplitude * lift * .38)
        } else if (jelly) {
            const crest = w * (.5 + .10 * sway)
            const crown = y - amplitude * (.76 + .19 * lift)
            ctx.moveTo(0, y + amplitude * (.26 - .39 * sway))
            ctx.bezierCurveTo(w * .19, y + amplitude * .49, crest - w * .23, crown, crest, crown)
            ctx.bezierCurveTo(crest + w * .19, crown, w * .87, y + amplitude * .55,
                w, y + amplitude * (.25 + .35 * sway))
        } else {
            ctx.moveTo(0, y)
            ctx.bezierCurveTo(w * .22, y - amplitude * lift, w * .36, y - amplitude,
                w * .53, y + sway * amplitude * .65)
            ctx.bezierCurveTo(w * .75, y + amplitude, w * .88, y, w, y - amplitude * .25)
        }
    }

    function paintLiquidVolume(ctx, w, h, surface, depth, amplitude) {
        const color = MaterialTheme.rgba
        const x = w * (.35 + .14 * Math.sin(waterPhase))
        const y = surface + depth * (jelly ? .22 : .33)
        const radius = Math.max(2, Math.min(w * .61, depth * 1.35))
        const reflection = ctx.createRadialGradient(x, y, 0, x, y, radius)
        reflection.addColorStop(0, color(startTone.edge, jelly ? .47 : .55))
        reflection.addColorStop(.35, color(startTone.glow, jelly ? .25 : .42))
        reflection.addColorStop(1, color(startTone.core, 0))
        ctx.fillStyle = reflection
        ctx.fillRect(0, 0, w, h)

        const shade = ctx.createLinearGradient(0, surface, 0, h)
        shade.addColorStop(0, color(startTone.edge, water ? .26 : .12))
        shade.addColorStop(.31, color(endTone.core, 0))
        shade.addColorStop(.68, color(endTone.body, jelly ? .15 : .06))
        shade.addColorStop(.93, color(trackColor, jelly ? .54 : .44))
        shade.addColorStop(1, color(endTone.edge, .34))
        ctx.fillStyle = shade
        ctx.fillRect(0, 0, w, h)

        if (water && depth > 5) {
            const caustic = ctx.createLinearGradient(0, 0, w, 0)
            caustic.addColorStop(0, color(startTone.glow, 0))
            caustic.addColorStop(.30, color(startTone.edge, .73))
            caustic.addColorStop(.68, color(endTone.edge, .50))
            caustic.addColorStop(1, color(endTone.glow, 0))
            traceSurface(ctx, w, surface + Math.min(depth * .31, h * .13), amplitude * .61, .95)
            ctx.lineWidth = Math.min(1.3, w * .06)
            ctx.strokeStyle = caustic
            ctx.stroke()
        }
    }

    onPaint: {
        if (paintingPaused || !visible)
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
            const styleHeight = animationStyle === "none" ? 0 : !movingLiquid ? .026
                : water ? .092 : jelly ? .117 : .061
            const amplitude = amount < 1 ? Math.min(depth * .26, h * styleHeight) : 0
            const surface = surfaceY + Math.sin(waterPhase) * amplitude * (jelly ? .16 : .30)

            // Clip both the dense liquid and its reflections to the moving meniscus.
            traceSurface(ctx, w, surface, amplitude)
            ctx.lineTo(w, h)
            ctx.lineTo(0, h)
            ctx.closePath()
            ctx.save()
            ctx.clip()

            const liquid = ctx.createLinearGradient(0, surface, w * .32, h)
            liquid.addColorStop(0, color(first.glow, .91))
            liquid.addColorStop(.17, color(first.body, .97))
            liquid.addColorStop(.46, color(first.core, 1))
            liquid.addColorStop(.76, color(last.core, sculpted ? .99 : .94))
            liquid.addColorStop(.94, color(last.body, .99))
            liquid.addColorStop(1, color(last.glow, .85))
            ctx.fillStyle = liquid
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
            if (water || jelly)
                paintLiquidVolume(ctx, w, h, surface, depth, amplitude)
            ctx.restore()

            if (amount < 1) {
                traceSurface(ctx, w, surface, amplitude)
                const glow = ctx.createLinearGradient(0, 0, w, 0)
                glow.addColorStop(0, color(first.glow, water ? .82 : receiving ? .65 : .44))
                glow.addColorStop(1, color(last.glow, water ? .87 : receiving ? .69 : .48))
                ctx.lineWidth = Math.min(4.5, w * .16)
                ctx.strokeStyle = glow
                ctx.stroke()
                const edge = ctx.createLinearGradient(0, 0, w, 0)
                edge.addColorStop(0, color(first.edge, .96))
                if (water || jelly)
                    edge.addColorStop(.43 + Math.sin(waterPhase) * .13, color(profile.upper, jelly ? .74 : .96))
                edge.addColorStop(1, color(last.edge, .92))
                ctx.lineWidth = Math.min(jelly ? 1.45 : 1.12, w * .075)
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
