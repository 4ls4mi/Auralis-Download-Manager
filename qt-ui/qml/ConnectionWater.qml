import QtQuick
import QtQuick.Window
import "IndicatorLighting.js" as Lighting

Canvas {
    id: vessel

    property var value: null
    property bool receiving: false
    property bool interrupted: false
    property bool paused: false
    property real phase: 0
    // The progress window shares a separate, slower clock for Jelly. Other
    // callers can still feed a single phase for previews and dashboard rows.
    property real slowPhase: -1
    property string animationStyle: "classic"
    property string lightingStyle: WindowAppearance.connectionLighting || "polished"
    property bool connected: false
    property int channelIndex: 0
    property bool paintingPaused: false
    property string shape: "round"
    property string material: MaterialTheme.current
    property color startColor: profile.accent
    property color endColor: profile.secondary
    property color trackColor: profile.background
    readonly property var profile: MaterialTheme.profile(material)
    readonly property var startTone: MaterialTheme.neonTone(startColor)
    readonly property var endTone: MaterialTheme.neonTone(endColor)
    readonly property var lighting: Lighting.style(lightingStyle)
    readonly property int optic: lighting.optic || 0
    readonly property color frostTint: MaterialTheme.mix(startTone.edge, "#f1fbff", .51, 1)
    readonly property color smokedTint: MaterialTheme.mix(endTone.glow, "#070912", .87, 1)
    readonly property color stateRed: MaterialTheme.mix("#cc2038", profile.destructive, .25, 1)
    readonly property real amount: typeof value === "number" && Number.isFinite(value)
        ? Math.max(0, Math.min(1, value)) : 0
    readonly property real surfaceY: 1.7 + (height - 3.4) * (1 - amount)
    readonly property bool water: animationStyle === "water"
    readonly property bool jelly: animationStyle === "jelly"
    readonly property bool animating: visible && receiving && !paused && !paintingPaused
        && !MaterialTheme.reducedMotion && animationStyle !== "none"
        && (!Window.window || (Window.window.visible && Window.window.visibility !== Window.Minimized))
    readonly property bool movingLiquid: animating && amount > 0 && (amount < 1 || water || jelly)
    readonly property real waterPhase: !movingLiquid ? 0 : water ? phase * 2
        : jelly ? (slowPhase >= 0 ? slowPhase : jellyPhase) : phase
    readonly property real fillDepth: height - surfaceY
    readonly property real amplitude: receiving && amount > 0 && amount < 1
        ? Math.min(fillDepth * .26, height * (animationStyle === "none" ? 0 : !movingLiquid ? .026
            : water ? .092 : jelly ? .117 : .061)) : 0
    readonly property real meniscusY: surfaceY + Math.sin(waterPhase) * amplitude * (jelly ? .16 : .30)
    readonly property real landingX: width * Lighting.outletPosition
    readonly property real landingY: centerOfSurface(meniscusY, amplitude, waterPhase) + impactBend(landingX)
    readonly property real dropCycle: connected && animating && width >= 12 && height >= 14 && amount > 0
        ? Lighting.dropCycle(phase, slowPhase >= 0 ? slowPhase : jellyPhase, channelIndex, animationStyle) : -1
    readonly property real impactAge: dropCycle >= Lighting.dropContact
        ? (dropCycle - Lighting.dropContact) / (1 - Lighting.dropContact) : -1
    property real lastPhase: 0
    property real jellyPhase: 0

    property real baseWidth: 32
    property real baseHeight: 38
    readonly property real blockScale: (WindowAppearance.connectionBlockSize ?? 100) / 100
    implicitWidth: Math.round(baseWidth * blockScale)
    implicitHeight: Math.round(baseHeight * blockScale)
    Accessible.ignored: true

    onAvailableChanged: requestPaint()
    onPaintingPausedChanged: if (!paintingPaused) requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()
    onAnimationStyleChanged: requestPaint()
    onLightingStyleChanged: requestPaint()
    onImpactAgeChanged: if (visible && !paintingPaused) requestPaint()
    onWaterPhaseChanged: if (visible && !paintingPaused) requestPaint()
    onPhaseChanged: {
        if (slowPhase >= 0)
            return
        if (movingLiquid && jelly) {
            const turn = Math.PI * 2
            const advance = (phase - lastPhase + turn) % turn
            jellyPhase = (jellyPhase + advance / 3) % turn
        }
        lastPhase = phase
    }
    onReceivingChanged: requestPaint()
    onInterruptedChanged: requestPaint()
    onPausedChanged: requestPaint()
    onValueChanged: requestPaint()
    onShapeChanged: requestPaint()
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
            const upperLeft = shape === "ice" ? corner * .45 : corner
            const upperRight = shape === "prism" ? corner * 1.3 : corner
            const lowerRight = shape === "chamfer" ? corner : corner * .58
            const lowerLeft = shape === "ice" ? corner : corner * .62
            ctx.moveTo(left + upperLeft, top)
            ctx.lineTo(right - upperRight, top)
            ctx.lineTo(right, top + upperRight)
            ctx.lineTo(right, bottom - lowerRight)
            ctx.lineTo(right - lowerRight, bottom)
            ctx.lineTo(left + lowerLeft, bottom)
            ctx.lineTo(left, bottom - lowerLeft)
            ctx.lineTo(left, top + upperLeft)
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

    function centerOfSurface(y, amplitude, motion) {
        if (jelly)
            return y - amplitude * (.76 + .19 * Math.cos(motion))
        return y + Math.sin(motion) * amplitude * (water ? .48 : .65)
    }

    function impactBend(x) {
        if (impactAge < 0 || amount <= 0 || amount >= 1)
            return 0
        const age = impactAge
        const distance = Math.abs(x - landingX)
        const waveWidth = Math.max(1.25, width * .10)
        const front = (distance - age * width * .50) / waveWidth
        const pressure = Math.max(0, 1 - age * 5) * Math.exp(-Math.pow(distance / waveWidth, 2))
        const wave = Math.sin(front * 2.4) * Math.exp(-front * front * .49)
        const decay = Math.min(1, age * 10) * Math.pow(1 - age, 1.35)
        return Math.min(height * .13, fillDepth * .32) * decay * (pressure + wave)
    }

    function traceSurface(ctx, w, y, amplitude, offset = 0) {
        const motion = waterPhase + offset
        const sway = Math.sin(motion)
        const lift = Math.cos(motion)
        const bend = x => impactBend(x) * (offset === 0 ? 1 : .43)
        const centerY = centerOfSurface(y, amplitude, motion) + bend(landingX)
        ctx.beginPath()
        if (water) {
            ctx.moveTo(0, y + amplitude * lift * .43 + bend(0))
            ctx.bezierCurveTo(w * .15, y - amplitude * (.82 + sway * .56) + bend(w * .15),
                w * .34, y - amplitude * (.49 + lift * .56) + bend(w * .34), landingX, centerY)
            ctx.bezierCurveTo(w * .73, y + amplitude * (.86 - lift * .50) + bend(w * .73),
                w * .83, y - amplitude * (.12 - sway * .86) + bend(w * .83), w, y - amplitude * lift * .38 + bend(w))
        } else if (jelly) {
            const shoulder = w * (.19 + .08 * sway)
            ctx.moveTo(0, y + amplitude * (.26 - .39 * sway) + bend(0))
            ctx.bezierCurveTo(shoulder, y + amplitude * .49 + bend(shoulder),
                landingX - w * .23, centerY, landingX, centerY)
            ctx.bezierCurveTo(landingX + w * (.16 + .04 * sway), centerY,
                w * .87, y + amplitude * .55 + bend(w * .87), w, y + amplitude * (.25 + .35 * sway) + bend(w))
        } else {
            ctx.moveTo(0, y + bend(0))
            ctx.bezierCurveTo(w * .22, y - amplitude * lift + bend(w * .22),
                w * .36, y - amplitude + bend(w * .36),
                landingX, centerY)
            ctx.bezierCurveTo(w * .75, y + amplitude + bend(w * .75),
                w * .88, y + bend(w * .88), w, y - amplitude * .25 + bend(w))
        }
    }

    function paintLiquidVolume(ctx, w, h, surface, depth, amplitude) {
        const color = MaterialTheme.rgba
        const x = w * (.35 + .14 * Math.sin(waterPhase))
        const y = surface + depth * (jelly ? .22 : .33)
        const radius = Math.max(2, Math.min(w * .61, depth * 1.35))
        const reflection = ctx.createRadialGradient(x, y, 0, x, y, radius)
        reflection.addColorStop(0, color(startTone.edge, (jelly ? .47 : .55) * lighting.reflection))
        reflection.addColorStop(.35, color(startTone.glow, (jelly ? .25 : .42) * lighting.reflection))
        reflection.addColorStop(1, color(startTone.core, 0))
        ctx.fillStyle = reflection
        ctx.fillRect(0, 0, w, h)

        const shade = ctx.createLinearGradient(0, surface, 0, h)
        shade.addColorStop(0, color(startTone.edge, (water ? .26 : .16) * lighting.reflection))
        shade.addColorStop(.27, color(endTone.core, 0))
        shade.addColorStop(.65, color(endTone.body, (jelly ? .43 : .32) * lighting.depth))
        shade.addColorStop(.89, color(trackColor, .74 * lighting.depth))
        shade.addColorStop(1, color(endTone.edge, .34 * lighting.reflection))
        ctx.fillStyle = shade
        ctx.fillRect(0, 0, w, h)

        if (lighting.caustic && depth > 5 && w >= 10) {
            const strength = lighting.caustic
            const caustic = ctx.createLinearGradient(0, 0, w, 0)
            caustic.addColorStop(0, color(startTone.glow, 0))
            caustic.addColorStop(.18, color(startTone.edge, .57 * strength))
            caustic.addColorStop(.40, color(startTone.glow, .21 * strength))
            caustic.addColorStop(.62, color(endTone.edge, .77 * strength))
            caustic.addColorStop(1, color(endTone.glow, 0))
            const spread = Math.max(1.3, Math.min(depth * .18, h * .09))
            const refraction = Math.max(amplitude, spread * .92)
            traceSurface(ctx, w, surface + spread * 1.45, refraction, .95)
            ctx.lineWidth = Math.min(1.3, w * .06)
            ctx.strokeStyle = caustic
            ctx.stroke()
            if (depth > 12) {
                traceSurface(ctx, w, surface + spread * 2.8, refraction * 1.22, 3.05)
                ctx.lineWidth *= .72
                ctx.stroke()
            }
        }
    }

    function paintOptic(ctx, w, h, surface) {
        if (!optic)
            return
        if (optic >= 5) {
            paintShapedReflection(ctx, w, h, surface)
            return
        }
        const color = MaterialTheme.rgba
        const first = startTone
        const last = endTone
        const finish = ctx.createLinearGradient(0, surface, 0, Math.max(surface + .4, h - 1.7))
        switch (optic) {
        case 1:
            finish.addColorStop(0, color(frostTint, .75))
            finish.addColorStop(.29, color(frostTint, .63))
            finish.addColorStop(.66, color(last.edge, .42))
            finish.addColorStop(1, color(last.glow, .17))
            break
        case 2:
            finish.addColorStop(0, color(first.body, .55))
            finish.addColorStop(.15, color(first.edge, .88))
            finish.addColorStop(.23, color(frostTint, .95))
            finish.addColorStop(.29, color(first.core, .84))
            finish.addColorStop(.69, color(last.body, .75))
            finish.addColorStop(.78, color(last.edge, .83))
            finish.addColorStop(.87, color(last.core, .63))
            finish.addColorStop(1, color(last.edge, .43))
            break
        case 3:
            finish.addColorStop(0, color(first.core, .96))
            finish.addColorStop(.44, color(first.core, .88))
            finish.addColorStop(.64, color(first.body, .64))
            finish.addColorStop(.81, color(last.glow, .80))
            finish.addColorStop(.92, MaterialTheme.mix(last.edge, "#f1fbff", .34, .98))
            finish.addColorStop(1, color(last.glow, .87))
            break
        case 4:
            finish.addColorStop(0, color(smokedTint, .53))
            finish.addColorStop(.31, color(smokedTint, .92))
            finish.addColorStop(.83, color(smokedTint, .88))
            finish.addColorStop(1, color(last.body, .53))
            break
        }
        ctx.fillStyle = finish
        ctx.fillRect(0, 0, w, h)
    }

    function spectrum(tone, shift, alpha) {
        const hue = (Math.max(0, tone.hsvHue) + shift + 1) % 1
        const reflected = Qt.hsva(hue, .73, 1)
        return MaterialTheme.mix(tone, reflected, .42, alpha)
    }

    function diagonalSheen(ctx, w, top, depth, direction, tint, strength, spread) {
        const drift = Math.sin(waterPhase) * .13
        const start = w * (.12 + drift)
        const end = w * (1.02 + drift)
        const beam = ctx.createLinearGradient(start, top + depth * direction,
            end, top + depth * (1 - direction))
        beam.addColorStop(0, MaterialTheme.rgba(tint, 0))
        beam.addColorStop(.53 - spread, MaterialTheme.rgba(tint, 0))
        beam.addColorStop(.53, MaterialTheme.rgba(tint, strength))
        beam.addColorStop(.53 + spread, MaterialTheme.rgba(tint, 0))
        beam.addColorStop(1, MaterialTheme.rgba(tint, 0))
        ctx.fillStyle = beam
        ctx.fillRect(0, 0, w, height)
    }

    function radialSheen(ctx, x, y, radius, tint, strength) {
        const light = ctx.createRadialGradient(x, y, 0, x, y, radius)
        light.addColorStop(0, MaterialTheme.rgba(tint, strength))
        light.addColorStop(.38, MaterialTheme.rgba(tint, strength * .54))
        light.addColorStop(1, MaterialTheme.rgba(tint, 0))
        ctx.fillStyle = light
        ctx.fillRect(x - radius, y - radius, 2 * radius, 2 * radius)
    }

    function paintShapedReflection(ctx, w, h, surface) {
        const color = MaterialTheme.rgba
        const first = startTone
        const last = endTone
        const top = Math.max(1.7, surface)
        const bottom = h - 1.7
        const depth = Math.max(.7, bottom - top)
        const center = top + depth * .52
        switch (optic) {
        case 5:
            diagonalSheen(ctx, w, top, depth, 1, frostTint, .63, .45)
            break
        case 6: {
            const edgeX = w * (.46 + Math.sin(waterPhase) * .035)
            ctx.beginPath()
            ctx.moveTo(0, top)
            ctx.lineTo(w * .68, top)
            ctx.lineTo(edgeX, center)
            ctx.lineTo(w * .21, bottom)
            ctx.lineTo(0, bottom)
            ctx.closePath()
            ctx.fillStyle = color(first.glow, .44)
            ctx.fill()
            ctx.beginPath()
            ctx.moveTo(w * .68, top)
            ctx.lineTo(w, top + depth * .23)
            ctx.lineTo(w, bottom)
            ctx.lineTo(w * .21, bottom)
            ctx.lineTo(edgeX, center)
            ctx.closePath()
            ctx.fillStyle = color(last.core, .69)
            ctx.fill()
            ctx.beginPath()
            ctx.moveTo(w * .68, top)
            ctx.lineTo(edgeX, center)
            ctx.lineTo(w, bottom - depth * .19)
            ctx.strokeStyle = color(frostTint, .81)
            ctx.lineWidth = Math.max(.64, Math.min(1.65, w * .035))
            ctx.stroke()
            break
        }
        case 7:
            diagonalSheen(ctx, w, top, depth, 1, first.edge, .62, .22)
            diagonalSheen(ctx, w, top, depth, 0, last.edge, .73, .18)
            break
        case 8: {
            ctx.fillStyle = color(smokedTint, .62)
            ctx.fillRect(0, top, w, depth)
            const sparkle = w * .027 * Math.sin(waterPhase)
            const radius = Math.max(1.6, Math.min(w, depth) * .16)
            radialSheen(ctx, w * .21 + sparkle, top + depth * .24, radius, frostTint, 1)
            radialSheen(ctx, w * .73 - sparkle, top + depth * .68, radius * .67, last.edge, .91)
            radialSheen(ctx, w * .82 - sparkle, top + depth * .65, radius * .38, last.edge, .77)
            break
        }
        case 9: {
            const count = Math.max(2, Math.min(6, Math.round(w / 10)))
            const spacing = w / count
            const swing = Math.sin(waterPhase) * .11
            for (let index = 0; index < count; ++index) {
                const x = (index + .36) * spacing
                ctx.beginPath()
                ctx.moveTo(x, top - depth * .18)
                ctx.bezierCurveTo(x + spacing * (.73 + swing), top + depth * .34,
                    x + spacing * (.75 - swing), top + depth * .71, x - spacing * .11, bottom + 1)
                ctx.lineWidth = Math.max(1, spacing * .39)
                ctx.strokeStyle = color(last.core, .78)
                ctx.stroke()
                ctx.lineWidth = Math.max(.6, spacing * .11)
                ctx.strokeStyle = color(first.edge, .69)
                ctx.stroke()
            }
            break
        }
        case 10:
            diagonalSheen(ctx, w, top, depth, 0, spectrum(first.glow, .12, 1), .29, .30)
            break
        case 11: {
            const body = ctx.createLinearGradient(0, top, 0, bottom)
            body.addColorStop(0, color(first.core, .65))
            body.addColorStop(.42, color(first.core, 0))
            body.addColorStop(.76, color(last.core, 0))
            body.addColorStop(1, color(last.core, .82))
            ctx.fillStyle = body
            ctx.fillRect(0, top, w, depth)
            radialSheen(ctx, w * .52, center, Math.max(3, Math.min(w, depth) * .86), first.edge, .87)
            break
        }
        case 12:
            ctx.fillStyle = color(smokedTint, .76)
            ctx.fillRect(0, top, w, depth)
            break
        }
    }

    function paintImpact(ctx) {
        if (impactAge < 0)
            return
        const age = impactAge
        const spread = Math.min(width * .42, 15)
        const gap = Math.max(0, landingY - 1.7)
        const ink = MaterialTheme.rgba
        for (let ring = 0; ring < 2; ++ring) {
            const travel = age - ring * .19
            if (travel < 0)
                continue
            const energy = Math.pow(1 - travel, 1.5) * (1 - ring * .36) * Math.min(1, (1 - age) * 6)
            const y = Math.min(height - 2.2, landingY + Math.min(2.8, fillDepth * .30) * travel)
            const radius = Math.max(1, spread * (.13 + travel * .87))
            const perspective = Math.max(.58, radius * .27)
            ctx.beginPath()
            ctx.ellipse(landingX - radius, y - perspective, 2 * radius, 2 * perspective)
            ctx.lineWidth = Math.min(2.8, width * .10) * lighting.haloWidth
            ctx.strokeStyle = ink(endTone.glow, energy * .54)
            ctx.stroke()
            ctx.lineWidth = .96
            ctx.strokeStyle = ink(startTone.edge, energy * .93)
            ctx.stroke()
        }

        // The ring expands along the surface; small droplets briefly arc above it.
        if (age >= .67 || gap < 2)
            return
        const flight = age / .67
        const lift = Math.min(gap - 1, Math.min(height * .28, 11)) * 4 * flight * (1 - flight)
        const radiusOfDrop = Math.max(.65, Math.min(1.45, width * .045)) * (1 - flight * .46)
        ctx.fillStyle = ink(endTone.glow, (1 - flight) * .86)
        ctx.strokeStyle = ink(startTone.edge, (1 - flight) * .94)
        ctx.lineWidth = .5
        for (let side = -1; side <= 1; side += 2) {
            const x = landingX + side * spread * (.11 + flight * .52)
            const height = lift * (side < 0 ? .73 : 1)
            ctx.beginPath()
            ctx.ellipse(x - radiusOfDrop, landingY - height - radiusOfDrop,
                radiusOfDrop * 2, radiusOfDrop * (2.3 + flight * .28))
            ctx.fill()
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
        outline(ctx, w, h)
        if (paused) {
            ctx.fillStyle = stateRed
            ctx.fill()
            ctx.strokeStyle = MaterialTheme.mix(stateRed, "#ffa7b0", .39, .9)
            ctx.lineWidth = .85
            ctx.stroke()
            return
        }
        const track = ctx.createLinearGradient(0, 0, w, h)
        if (interrupted) {
            track.addColorStop(0, color(stateRed, .84))
            track.addColorStop(.67, MaterialTheme.mix(stateRed, "#610d28", .36, .88))
            track.addColorStop(1, MaterialTheme.mix(stateRed, "#400c23", .63, .92))
        } else {
            track.addColorStop(0, optic === 1 ? color(frostTint, .29) : color(profile.upper, profile.light ? .37 : .16))
            track.addColorStop(.30, optic === 4 ? color(smokedTint, .68) : color(trackColor, .16))
            track.addColorStop(.70, optic === 4 ? color(smokedTint, .73) : color(trackColor, .23))
            track.addColorStop(1, color(last.core, profile.light ? .53 : .37))
        }
        ctx.fillStyle = track
        ctx.fill()

        if (amount > 0) {
            ctx.save()
            ctx.clip()
            const surface = meniscusY

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
            liquid.addColorStop(.76, color(last.core, .99))
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
            paintLiquidVolume(ctx, w, h, surface, fillDepth, amplitude)
            paintOptic(ctx, w, h, surface)
            ctx.restore()

            if (amount < 1) {
                traceSurface(ctx, w, surface, amplitude)
                const glow = ctx.createLinearGradient(0, 0, w, 0)
                const upperLight = optic === 3 ? .43 : optic === 4 ? .52 : optic === 8 || optic === 11 ? .55 : 1
                const glowAlpha = Math.min(.98, (water ? .82 : receiving ? .65 : .48) * lighting.halo) * upperLight
                glow.addColorStop(0, color(first.glow, glowAlpha * .92))
                glow.addColorStop(1, color(last.glow, glowAlpha))
                ctx.lineWidth = Math.min(4.5, w * .16) * lighting.haloWidth
                ctx.strokeStyle = glow
                ctx.stroke()
                const edge = ctx.createLinearGradient(0, 0, w, 0)
                edge.addColorStop(0, color(optic === 1 ? frostTint : first.edge,
                    (.70 + .26 * lighting.reflection) * upperLight))
                if (water || jelly)
                    edge.addColorStop(.43 + Math.sin(waterPhase) * .13,
                        color(optic === 1 ? frostTint : profile.upper, (jelly ? .74 : .96) * upperLight))
                if (optic === 10) {
                    edge.addColorStop(.23, spectrum(first.edge, -.12, .96))
                    edge.addColorStop(.72, spectrum(last.edge, .11, .98))
                }
                edge.addColorStop(1, color(last.edge, .92 * upperLight))
                ctx.lineWidth = Math.min(optic === 12 || jelly ? 1.45 : 1.12, w * .075)
                ctx.strokeStyle = edge
                ctx.stroke()
            }
            paintImpact(ctx)
            ctx.restore()
        }

        outline(ctx, w, h)
        if (amount > 0) {
            const halo = ctx.createLinearGradient(0, Math.max(0, surfaceY - 2), 0, h)
            halo.addColorStop(0, color(first.glow, 0))
            const bottomLight = optic === 3 ? 1.8 : optic === 4 ? .55 : 1
            halo.addColorStop(.43, color(first.glow, (receiving ? .33 : .23) * lighting.halo))
            halo.addColorStop(1, color(last.glow, Math.min(1, (receiving ? .59 : .40) * lighting.halo * bottomLight)))
            ctx.lineWidth = 3.2 * lighting.haloWidth
            ctx.strokeStyle = halo
            ctx.stroke()
        }
        const rim = ctx.createLinearGradient(0, 0, w, h)
        rim.addColorStop(0, optic === 1 ? color(frostTint, .77) : color(profile.upper, profile.light ? .78 : .56))
        if (optic === 10 || optic === 12) {
            rim.addColorStop(.27, optic === 10 ? spectrum(first.edge, -.10, .98) : color(first.edge, .97))
            rim.addColorStop(.69, optic === 10 ? spectrum(last.edge, .13, .99) : color(last.edge, .87))
        } else {
            rim.addColorStop(.47, color(profile.upper, .19))
        }
        rim.addColorStop(1, color(amount > 0 ? last.edge : profile.upper,
            amount > 0 ? optic === 3 || optic === 12 ? 1 : optic === 4 ? .52 : .85 : .34))
        ctx.lineWidth = optic === 12 ? 1.15 : .8
        ctx.strokeStyle = interrupted ? MaterialTheme.mix(stateRed, "#ffa7b0", .35, .92) : rim
        ctx.stroke()
    }
}
