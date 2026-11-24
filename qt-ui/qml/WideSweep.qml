pragma ComponentBehavior: Bound

import QtQuick

Canvas {
    id: sweep

    required property Item sidebar
    required property Item pane
    required property Item viewport
    required property Item geometryHost
    property Item footer
    property Item selectedRow
    property color selectedColor: MaterialTheme.palette.accent
    property bool backdropAvailable: MaterialTheme.backdropAvailable

    readonly property var profile: MaterialTheme.palette
    readonly property color railColor: profile.railFill || profile.roleFaces?.sidebar
        || profile.navigationFill || profile.background
    readonly property real surfaceOpacity: backdropAvailable && MaterialTheme.translucency >= 0
        ? Math.max(profile.opaque ? .78 : .42, MaterialTheme.opacityFor(MaterialTheme.current)) : 1
    opacity: surfaceOpacity
    readonly property Item scrollItem: viewport && viewport.contentItem
        && viewport.contentItem.contentY !== undefined ? viewport.contentItem : viewport
    property real selectedCenter: 0
    property bool selectionPending: false
    property bool positioned: false

    function bounds(item) {
        const point = item.mapToItem(sweep, 0, 0)
        return {left: point.x, right: point.x + item.width, top: point.y, bottom: point.y + item.height}
    }

    function updatePosition() {
        const animate = selectionPending
        selectionPending = false
        if (!visible || !selectedRow) {
            positioned = false
            movement.stop()
            requestPaint()
            return
        }
        const row = bounds(selectedRow)
        const center = (row.top + row.bottom) / 2
        movement.stop()
        if (animate && positioned && !MaterialTheme.reducedMotion
                && Math.abs(center - selectedCenter) >= 1) {
            movement.from = selectedCenter
            movement.to = center
            movement.start()
        } else {
            selectedCenter = center
        }
        positioned = true
        requestPaint()
    }

    function schedule(animate = false) {
        selectionPending = selectionPending || animate
        Qt.callLater(updatePosition)
    }

    // Ease the straight seam into the corner whenever the selected row is near an end.
    function shoulder(seam, edge, radius, viewportInset, center) {
        const direction = Math.sign(center - edge)
        const distance = Math.abs(center - edge)
        const length = 35
        const near = Math.max(0, Math.min(1, (radius + length + viewportInset - distance) / (radius * .75)))
        const blend = near * near * (3 - 2 * near)
        const join = Math.min(distance, Math.max(radius, distance - length)) * (1 - blend)
        const tangent = (distance - join) * .55
        const x = seam + radius * blend
        const y = edge + direction * join
        const handle = radius * (1 - blend) * 2 / 3
        return {
            blend, x, y,
            peakY: center - direction * tangent,
            shoulderX: x - tangent * blend,
            shoulderY: y + direction * tangent * (1 - blend),
            cornerX: x + handle * blend,
            cornerY: y - direction * handle * (1 - blend),
            edgeX: seam + radius - handle
        }
    }

    function paintSelection(ctx, left, seam, depth, top, bottom, bandTop, bandBottom) {
        const near = Math.max(left, seam - depth - 34)
        const far = seam + 45
        const upper = Math.max(top, bandTop - 16)
        const lower = Math.min(bottom, bandBottom + 16)
        ctx.beginPath()
        ctx.moveTo(left, bandTop)
        ctx.lineTo(near, bandTop)
        ctx.bezierCurveTo(seam - depth - 8, bandTop, seam - 6, upper, far, upper)
        ctx.lineTo(far, lower)
        ctx.bezierCurveTo(seam - 6, lower, seam - depth - 8, bandBottom, near, bandBottom)
        ctx.lineTo(left, bandBottom)
        ctx.closePath()

        const face = ctx.createLinearGradient(0, bandTop, 0, bandBottom)
        face.addColorStop(0, MaterialTheme.mix(selectedColor, profile.upper, .13, 1))
        face.addColorStop(.20, selectedColor)
        face.addColorStop(.64, selectedColor)
        face.addColorStop(1, MaterialTheme.mix(selectedColor, profile.shade, .19, 1))
        ctx.fillStyle = face
        ctx.fill()

        const shadow = ctx.createLinearGradient(near, 0, far, 0)
        shadow.addColorStop(0, Qt.alpha(profile.shade, 0))
        shadow.addColorStop(.55, Qt.alpha(profile.shade, .22))
        shadow.addColorStop(1, Qt.alpha(profile.shade, .35))
        ctx.fillStyle = shadow
        ctx.fill()
    }

    function paintPane(ctx, seam, right, top, bottom, rise, depth, viewportBottom, face) {
        const small = width < 560
        const topRadius = Math.max(1, Math.min(small ? 15 : 28, (right - seam) / 5, (bottom - top) / 4))
        const bottomRadius = Math.max(1, Math.min(small ? 19 : 40, (right - seam) / 4, (bottom - top) / 4))
        const shelfStart = seam + (right - seam) * .19
        const shelfEnd = Math.max(shelfStart, right - (small ? 70 : 125))
        ctx.beginPath()
        ctx.moveTo(seam + topRadius, top)
        ctx.lineTo(right, top)
        ctx.lineTo(right, bottom - rise)
        ctx.lineTo(shelfEnd, bottom - rise)
        ctx.bezierCurveTo(shelfEnd - (shelfEnd - shelfStart) * .44, bottom - rise,
            shelfStart + (shelfEnd - shelfStart) * .42, bottom, shelfStart, bottom)
        ctx.lineTo(seam + bottomRadius, bottom)
        if (depth > 0) {
            const lower = shoulder(seam, bottom, bottomRadius, Math.max(0, bottom - viewportBottom), selectedCenter)
            const upper = shoulder(seam, top, topRadius, 0, selectedCenter)
            if (lower.blend > 0) {
                ctx.bezierCurveTo(lower.edgeX, bottom, lower.cornerX, lower.cornerY, lower.x, lower.y)
            } else {
                ctx.quadraticCurveTo(seam, bottom, seam, bottom - bottomRadius)
                ctx.lineTo(lower.x, lower.y)
            }
            ctx.bezierCurveTo(lower.shoulderX, lower.shoulderY, seam - depth, lower.peakY,
                seam - depth, selectedCenter)
            ctx.bezierCurveTo(seam - depth, upper.peakY, upper.shoulderX, upper.shoulderY, upper.x, upper.y)
            if (upper.blend > 0) {
                ctx.bezierCurveTo(upper.cornerX, upper.cornerY, upper.edgeX, top, seam + topRadius, top)
            } else {
                ctx.lineTo(seam, top + topRadius)
                ctx.quadraticCurveTo(seam, top, seam + topRadius, top)
            }
        } else {
            ctx.quadraticCurveTo(seam, bottom, seam, bottom - bottomRadius)
            ctx.lineTo(seam, top + topRadius)
            ctx.quadraticCurveTo(seam, top, seam + topRadius, top)
        }
        ctx.closePath()
        ctx.fillStyle = face
        ctx.fill()
        ctx.strokeStyle = Qt.alpha(profile.surfaceLine || profile.divider || profile.edge, .82)
        ctx.lineWidth = 1
        ctx.stroke()
    }

    onPaint: {
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (!visible || !sidebar || !pane || !viewport || !geometryHost || pane.width < 12)
            return
        const nav = bounds(sidebar)
        const content = bounds(pane)
        const mirrored = nav.left > content.left
        const left = mirrored ? width - nav.right : nav.left
        const right = mirrored ? width - content.left : content.right
        const seam = mirrored ? width - (content.right + nav.left) / 2 : (content.left + nav.right) / 2
        const top = content.top
        const foot = footer && footer.visible ? bounds(footer) : null
        const bottom = foot ? Math.min(height, foot.top + (foot.bottom - foot.top) * .43) : content.bottom
        const rise = foot ? Math.min(width < 560 ? 18 : 27, Math.max(0, bottom - content.bottom)) : 0
        if (bottom - top < 12 || right - seam < 8)
            return

        const paneColor = profile.roleFaces?.content || profile.background
        const footerColor = profile.roleFaces?.footer || profile.background

        ctx.save()
        if (mirrored) {
            ctx.translate(width, 0)
            ctx.scale(-1, 1)
        }

        const base = ctx.createLinearGradient(left, top, right * .56, foot ? foot.bottom : bottom)
        base.addColorStop(0, railColor)
        base.addColorStop(.54, railColor)
        base.addColorStop(1, footerColor)
        ctx.fillStyle = base
        ctx.fillRect(left, top, right - left, (foot ? foot.top : bottom) - top)
        if (foot) {
            const footLeft = mirrored ? width - foot.right : foot.left
            ctx.fillRect(footLeft, foot.top, foot.right - foot.left, foot.bottom - foot.top)
        }

        const view = bounds(viewport)
        let depth = 0
        if (selectedRow && positioned) {
            const row = bounds(selectedRow)
            const rowTop = Math.max(row.top, view.top)
            const rowBottom = Math.min(row.bottom, view.bottom)
            const offset = selectedCenter - (row.top + row.bottom) / 2
            const bandTop = Math.max(top, view.top, rowTop + offset)
            const bandBottom = Math.min(bottom, view.bottom, rowBottom + offset)
            if (bandBottom > bandTop && row.bottom > row.top) {
                const fraction = (rowBottom - rowTop) / (row.bottom - row.top)
                depth = (width < 560 ? 13 : 27) * fraction
                    * Math.max(0, Math.min(1, (selectedCenter - top) / 20, (bottom - selectedCenter) / 20))
                if (depth > 0)
                    paintSelection(ctx, left, seam, depth, top, bottom, bandTop, bandBottom)
            }
        }

        paintPane(ctx, seam, right, top, bottom, rise, depth, view.bottom, paneColor)
        ctx.restore()
    }

    onSelectedRowChanged: schedule(true)
    onSelectedColorChanged: requestPaint()
    onSelectedCenterChanged: requestPaint()
    onVisibleChanged: schedule()
    onWidthChanged: schedule()
    onHeightChanged: schedule()
    onProfileChanged: requestPaint()
    Component.onCompleted: schedule()

    NumberAnimation {
        id: movement
        target: sweep
        property: "selectedCenter"
        duration: 330
        easing.type: Easing.InOutCubic
    }

    Connections {
        target: sweep.geometryHost
        function onXChanged() { sweep.schedule() }
        function onYChanged() { sweep.schedule() }
        function onWidthChanged() { sweep.schedule() }
        function onHeightChanged() { sweep.schedule() }
    }
    Connections {
        target: sweep.sidebar
        function onXChanged() { sweep.schedule() }
        function onWidthChanged() { sweep.schedule() }
        function onHeightChanged() { sweep.schedule() }
    }
    Connections {
        target: sweep.viewport
        function onHeightChanged() { sweep.schedule() }
    }
    Connections {
        target: sweep.scrollItem
        ignoreUnknownSignals: true
        function onContentYChanged() { sweep.schedule() }
    }
    Connections {
        target: sweep.selectedRow
        function onYChanged() { sweep.schedule() }
        function onHeightChanged() { sweep.schedule() }
    }
    Connections {
        target: sweep.footer
        function onYChanged() { sweep.schedule() }
        function onHeightChanged() { sweep.schedule() }
        function onVisibleChanged() { sweep.schedule() }
    }
}
