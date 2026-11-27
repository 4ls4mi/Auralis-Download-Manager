import QtQuick

// This overlay never paints a track or a base fill. The host owns both.
Canvas {
    id: root
    property real amount: 0
    property real phase: 0
    property string animationStyle: "none"
    property string fillMask: ""
    readonly property real fraction: Number.isFinite(amount) ? Math.max(0, Math.min(1, amount)) : 0
    renderTarget: Canvas.Image
    onAmountChanged: requestPaint()
    onPhaseChanged: requestPaint()
    onAnimationStyleChanged: requestPaint()
    onFillMaskChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()
    onAvailableChanged: if (available) requestPaint()

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
        if (width <= 0 || height <= 0 || fraction <= 0 || animationStyle === "none" || !fillMask)
            return
        ctx.save()
        // Use the host's exact contour and pill gaps, then cap at received bytes.
        ctx.path = fillMask
        ctx.clip()
        ctx.beginPath()
        ctx.rect(0, 0, width * fraction, height)
        ctx.clip()
        motion(ctx, 0, 0, width, height, width * fraction)
        ctx.restore()
    }
    onPaint: {
        const ctx = getContext("2d")
        if (ctx) drawProgress(ctx)
    }
}
