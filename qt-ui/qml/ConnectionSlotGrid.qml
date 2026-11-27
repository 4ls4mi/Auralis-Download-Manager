import QtQuick

Canvas {
    id: grid

    required property int activeCount
    required property int configuredCount
    property color activeInk: MaterialTheme.connectionColors[0]
    property color idleInk: Qt.alpha(MaterialTheme.palette.ink, .18)
    property string shape: WindowAppearance.connectionShape
    readonly property int slotCount: Math.min(128, Math.max(activeCount, configuredCount))

    Accessible.ignored: true
    onActiveCountChanged: requestPaint()
    onSlotCountChanged: requestPaint()
    onActiveInkChanged: requestPaint()
    onIdleInkChanged: requestPaint()
    onShapeChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onAvailableChanged: if (available) requestPaint()
    onVisibleChanged: if (visible) requestPaint()

    onPaint: {
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (slotCount <= 0 || width <= 0 || height <= 0)
            return

        // This is a count summary. Individual worker progress remains in Download details.
        const rows = Math.min(4, Math.max(1, Math.ceil(slotCount / 8)))
        const columns = Math.ceil(slotCount / rows)
        const cellWidth = width / columns
        const cellHeight = height / rows
        const w = Math.max(.6, cellWidth * .80)
        const h = Math.max(.6, cellHeight * .76)
        const radius = shape === "square" || shape === "plain" ? 0 : Math.min(w, h) * (shape === "bubble" ? .45 : .2)
        for (let slot = 0; slot < slotCount; ++slot) {
            const x = (slot % columns) * cellWidth + (cellWidth - w) / 2
            const y = Math.floor(slot / columns) * cellHeight + (cellHeight - h) / 2
            ctx.fillStyle = slot < activeCount ? activeInk : idleInk
            if (radius) {
                ctx.beginPath()
                ctx.moveTo(x + radius, y)
                ctx.lineTo(x + w - radius, y)
                ctx.quadraticCurveTo(x + w, y, x + w, y + radius)
                ctx.lineTo(x + w, y + h - radius)
                ctx.quadraticCurveTo(x + w, y + h, x + w - radius, y + h)
                ctx.lineTo(x + radius, y + h)
                ctx.quadraticCurveTo(x, y + h, x, y + h - radius)
                ctx.lineTo(x, y + radius)
                ctx.quadraticCurveTo(x, y, x + radius, y)
                ctx.closePath()
                ctx.fill()
            } else {
                ctx.fillRect(x, y, w, h)
            }
        }
    }
}
