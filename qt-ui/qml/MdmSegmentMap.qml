import QtQuick

Canvas {
    id: map

    property var segments: []
    property real totalBytes: 0
    property var colors: MaterialTheme.palette.mdm
    property bool paintingPaused: false

    property real baseHeight: 15
    implicitHeight: Math.round(baseHeight * (WindowAppearance.connectionBlockSize ?? 100) / 100)
    renderTarget: Canvas.Image
    Accessible.role: Accessible.Graphic
    Accessible.name: qsTr("Downloaded byte ranges")

    onColorsChanged: requestPaint()
    onSegmentsChanged: requestPaint()
    onTotalBytesChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onVisibleChanged: if (visible) requestPaint()
    onAvailableChanged: if (available) requestPaint()
    onPaintingPausedChanged: if (!paintingPaused) requestPaint()

    function paintBands(ctx, bands, start, width) {
        for (let row = 0; row < bands.length; row++) {
            const top = 1 + Math.floor(row * (height - 2) / bands.length)
            const bottom = 1 + Math.floor((row + 1) * (height - 2) / bands.length)
            if (bottom > top) {
                ctx.fillStyle = bands[row]
                ctx.fillRect(start, top, width, bottom - top)
            }
        }
    }

    onPaint: {
        if (paintingPaused || !visible || !colors || width < 3 || height < 3)
            return
        const ctx = getContext("2d")
        const columns = Math.floor(width) - 2
        ctx.fillStyle = colors.segmentBorder
        ctx.fillRect(0, 0, width, height)
        paintBands(ctx, colors.segmentMissing, 1, columns)
        if (totalBytes > 0) {
            // A segment's cursor is the first byte that has not arrived.
            for (const segment of segments) {
                const start = Number(segment.start)
                const cursor = Math.min(totalBytes, Number(segment.end), Number(segment.cursor))
                if (!Number.isFinite(start) || !Number.isFinite(cursor) || start < 0 || start >= totalBytes)
                    continue
                const first = Math.floor(start * columns / totalBytes)
                const end = Math.floor(cursor * columns / totalBytes)
                if (end > first + 1)
                    paintBands(ctx, colors.segmentDone, first + 2, end - first - 1)
                paintBands(ctx, colors.segmentStart, first + 1, 1)
            }
        }
        ctx.fillStyle = colors.segmentCorner
        ctx.fillRect(0, 0, 1, 1)
        ctx.fillRect(width - 1, 0, 1, 1)
        ctx.fillRect(0, height - 1, 1, 1)
        ctx.fillRect(width - 1, height - 1, 1, 1)
    }
}
