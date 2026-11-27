import QtQuick
import "ProgressArtwork.js" as Artwork
import "ProgressStyles.js" as Styles

// This overlay never paints a track or a base fill. The host owns both.
Canvas {
    id: root
    property real amount: 0
    property real phase: 0
    property string animationStyle: "none"
    property string layoutStyle: "status-track"
    property color startColor: "#9069f8"
    property color endColor: "#ba98ff"
    property real clipFront: width*fraction
    property string fillMask: ""
    readonly property real fraction: Number.isFinite(amount) ? Math.max(0, Math.min(1, amount)) : 0
    renderTarget: Canvas.Image
    onAmountChanged: requestPaint()
    onPhaseChanged: if (!paintTimer.running) paintTimer.start()
    Timer { id: paintTimer; interval: 33; onTriggered: root.requestPaint() }
    onLayoutStyleChanged: requestPaint()
    onStartColorChanged: requestPaint()
    onEndColorChanged: requestPaint()
    onClipFrontChanged: requestPaint()
    onAnimationStyleChanged: requestPaint()
    onFillMaskChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()
    onAvailableChanged: if (available) requestPaint()

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
        ctx.rect(0, 0, clipFront, height)
        ctx.clip()
        Artwork.drawLegacy(ctx,{width:width,height:height,front:clipFront,layout:layoutStyle,animation:Styles.normalize(layoutStyle,animationStyle),phase:phase,startColor:String(startColor),endColor:String(endColor)})
        ctx.restore()
    }
    onPaint: {
        const ctx = getContext("2d")
        if (ctx) drawProgress(ctx)
    }
}
