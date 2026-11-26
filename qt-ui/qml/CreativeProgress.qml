import QtQuick
import "IndicatorLighting.js" as Lighting

Canvas {
    id: root
    property string shape: "round"
    property string lightingStyle: "polished"
    property string animationStyle: "none"
    property bool overlayOnly: false
    property string fillMask: ""
    readonly property var finish: Lighting.style(lightingStyle)
    onShapeChanged: requestPaint()
    onLightingStyleChanged: requestPaint()
    onAnimationStyleChanged: requestPaint()
    onOverlayOnlyChanged: requestPaint()
    onFillMaskChanged: requestPaint()
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
        const r = ["square", "plain"].includes(shape) ? 0
            : layoutStyle === "frosted-cells" ? Math.min(2, w / 2, h / 2) : Math.max(0, Math.min(h / 2, w / 2))
        if (["prism", "ice", "chamfer"].includes(shape)) {
            const cut = Math.min(w / 3, h / 3)
            ctx.beginPath(); ctx.moveTo(x + cut, y); ctx.lineTo(x + w - cut, y)
            ctx.lineTo(x + w, y + cut); ctx.lineTo(x + w, y + h - cut)
            ctx.lineTo(x + w - cut, y + h); ctx.lineTo(x + cut, y + h)
            ctx.lineTo(x, y + h - cut); ctx.lineTo(x, y + cut); ctx.closePath()
            return
        }
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

    function motion(ctx, x, y, w, h, front) {
        if (animationStyle === "none" || front <= 0) return
        const time = phase / (Math.PI * 2)
        const center = x + (animationStyle === "elastic" ? .5 + .45 * Math.sin(phase) : time % 1) * w
        ctx.save()
        if (animationStyle === "heartbeat") {
            ctx.globalAlpha = .06 + .12 * Math.pow(Math.max(0, Math.sin(phase * 2)), 4)
            ctx.fillStyle = "#ffffff"; ctx.fillRect(x,y,front,h)
        } else if (animationStyle === "tide" || animationStyle === "water") {
            ctx.beginPath()
            for(let i=0;i<=48;i++) {
                const px=front*i/48, py=y+h*(.5+Math.sin(i*.25-phase)*.20)
                if(!i)ctx.moveTo(x+px,py);else ctx.lineTo(x+px,py)
            }
            ctx.strokeStyle="#70ffffff";ctx.lineWidth=Math.max(1,h*.12);ctx.stroke()
        } else if (animationStyle === "glints") {
            for(let i=0;i<12;i++) {
                const px=x+w*(i+.5)/12
                const glow=Math.max(0,Math.sin(phase+i*1.7))
                ctx.globalAlpha=glow*.6;ctx.fillStyle="#ffffff"
                ctx.beginPath();ctx.arc(px,y+h*.3,Math.max(.5,h*.08),0,Math.PI*2);ctx.fill()
            }
        } else if (animationStyle === "current") {
            ctx.strokeStyle="#90ffffff";ctx.lineWidth=Math.max(1,h*.06)
            for(let i=0;i<5;i++) { const px=x+((time+i/5)%1)*w
                ctx.beginPath();ctx.moveTo(px-h*.6,y+h*.5);ctx.lineTo(px,y+h*.5);ctx.stroke() }
        } else {
            const spread=Math.max(4,h*(animationStyle === "elastic" || animationStyle === "jelly" ? 2+Math.sin(phase)*.7 : 1.2))
            const band=ctx.createLinearGradient(center-spread,0,center+spread,0)
            band.addColorStop(0,"#00ffffff");band.addColorStop(.5,"#70ffffff");band.addColorStop(1,"#00ffffff")
            ctx.fillStyle=band;ctx.fillRect(x,y,front,h)
        }
        ctx.restore()
    }

    function drawProgress(ctx) {
        ctx.reset()
        ctx.clearRect(0, 0, width, height)
        if (width < 3 || height < 3) return
        const x = 2, y = Math.max(2, height * .12)
        const w = width - 4, h = Math.max(1, height - 2 * y)
        const front = w * fraction
        const orbit = layoutStyle === "orbit-marker" || layoutStyle === "filament-core" || layoutStyle === "checkpoints" || layoutStyle === "twin-rails"
        const trackH = orbit ? Math.max(2, h * .18) : h
        if (!overlayOnly) {
        capsule(ctx, x, y + (h - trackH) / 2, w, trackH)
        ctx.fillStyle = trackColor
        ctx.fill()
        ctx.strokeStyle = light ? "#65000000" : "#70ffffff"
        ctx.lineWidth = .7
        ctx.stroke()
        }
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
        if (overlayOnly) {
            if (fillMask) { ctx.path=fillMask;ctx.clip() }
            motion(ctx,x,y,w,h,front);ctx.restore();return
        }
        const segmented = ["jelly-beads", "prism-segments", "glass-tiles", "frosted-cells"].includes(layoutStyle)
        if (segmented) {
            const count = Math.max(1, Math.min(24, Math.floor(w / Math.max(14, h * 1.7))))
            const step = w / count, gap = layoutStyle === "glass-tiles" ? -2 : Math.min(4, step * .14)
            for (let i = 0; i < count; i++) {
                const left = x + i * step, span = step - gap
                if (layoutStyle !== "prism-segments") capsule(ctx, left, y + 1, span, Math.max(1, h - 2))
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
                gloss.addColorStop(0, layoutStyle === "frosted-cells" ? "#45ffffff" : "#c0ffffff")
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
        } else if (layoutStyle === "twin-rails") {
            for(let rail=0;rail<2;rail++) {
                ctx.strokeStyle=rail?endColor:startColor;ctx.lineWidth=Math.max(1,h*.1)
                ctx.beginPath();ctx.moveTo(x,y+h*(rail ? .7 : .3));ctx.lineTo(x+front,y+h*(rail ? .7 : .3));ctx.stroke()
            }
            ctx.strokeStyle="#70ffffff";ctx.lineWidth=.7
            for(let i=0;i<24;i++){const px=x+w*i/24;ctx.beginPath();ctx.moveTo(px,y+h*.3);ctx.lineTo(px,y+h*.7);ctx.stroke()}
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
                if (layoutStyle === "molten-glass" || layoutStyle === "tidal-ribbon") {
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
        if (layoutStyle === "checkpoints") {
            for(let i=0;i<10;i++){ctx.beginPath();ctx.arc(x+w*i/9,y+h/2,Math.max(1,h*.15),0,Math.PI*2);ctx.fillStyle=startColor;ctx.fill()}
        }
        // The selected lighting finish changes highlight depth without changing progress.
        const lighting=ctx.createLinearGradient(0,y,0,y+h)
        lighting.addColorStop(0,Qt.rgba(1,1,1,Math.min(.8,.12+(finish.reflection||0)*.22)))
        lighting.addColorStop(.5,"#00ffffff")
        lighting.addColorStop(1,Qt.rgba(0,0,0,Math.min(.8,(finish.depth||0)*.25)))
        ctx.fillStyle=lighting;ctx.fillRect(x,y,front,h)
        const optic=finish.optic || 0
        if (optic === 2) {
            const chrome=ctx.createLinearGradient(0,y,0,y+h)
            chrome.addColorStop(0,"#90ffffff");chrome.addColorStop(.43,"#10ffffff")
            chrome.addColorStop(.5,"#a010172b");chrome.addColorStop(.55,"#80ffffff");chrome.addColorStop(1,"#00000000")
            ctx.fillStyle=chrome;ctx.fillRect(x,y,front,h)
        } else if ([6,7,9,10].includes(optic)) {
            ctx.strokeStyle=optic === 10 ? "#70c0afff" : "#50ffffff"
            ctx.lineWidth=optic === 9 ? 1.3 : .7
            const step=optic === 9 ? 5 : h*1.3
            for(let px=x-h;px<x+front;px+=step) {
                ctx.beginPath();ctx.moveTo(px,y+h);ctx.lineTo(px+h,y);ctx.stroke()
                if(optic === 7){ctx.beginPath();ctx.moveTo(px,y);ctx.lineTo(px+h,y+h);ctx.stroke()}
            }
        } else if (optic === 3 || optic === 11 || optic === 12) {
            ctx.fillStyle=Qt.rgba(1,1,1,.12+(finish.halo||0)*.12)
            ctx.fillRect(x,y+h*.85,front,Math.max(1,h*.1))
        } else if (optic === 8) {
            ctx.fillStyle="#b0ffffff"
            for(let i=0;i<4;i++){ctx.beginPath();ctx.arc(x+front*(i+.5)/4,y+h*.25,Math.max(.5,h*.05),0,Math.PI*2);ctx.fill()}
        }
        motion(ctx,x,y,w,h,front)
        ctx.restore()
        if (layoutStyle === "orbit-marker") {
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
