import QtQuick
import "ProgressArtwork.js" as Artwork
import "IndicatorLighting.js" as Lighting

// Fill-only artwork: the surrounding GlassProgress owns the material track.
Canvas {
    id: root
    property real amount: 0
    property string layoutStyle: "liquid-silk"
    property string animationStyle: "silk-laminar"
    property string shape: "round"
    property color startColor: "#9069f8"
    property color endColor: "#ba98ff"
    property string lightingStyle: "polished"
    property bool moving: false
    property real phase: 0
    property real lastTick: 0
    renderTarget: Canvas.Image
    onAmountChanged: requestPaint()
    onLayoutStyleChanged: requestPaint()
    onAnimationStyleChanged: requestPaint()
    onShapeChanged: requestPaint()
    onStartColorChanged: requestPaint()
    onEndColorChanged: requestPaint()
    onLightingStyleChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onAvailableChanged: if (available) requestPaint()
    onVisibleChanged: if (visible) requestPaint()
    onMovingChanged: { lastTick=Date.now(); requestPaint() }
    Timer {
        interval: 33
        repeat: true
        running: root.visible && root.moving && root.animationStyle !== "none" && root.amount > 0 && root.amount < 1
        onTriggered: {
            const now=Date.now()
            root.phase += Math.min(.1,Math.max(0,(now-root.lastTick)/1000))
            root.lastTick=now
            root.requestPaint()
        }
    }
    onPaint: {
        const ctx=getContext("2d")
        if (!ctx) return
        ctx.reset()
        ctx.clearRect(0,0,width,height)
        Artwork.draw(ctx,{width:width,height:height,amount:Number.isFinite(amount)?Math.max(0,Math.min(1,amount)):0,
            layout:layoutStyle,animation:animationStyle,phase:phase,shape:shape,
            startColor:String(startColor),endColor:String(endColor),finish:Lighting.style(lightingStyle)})
    }
}
