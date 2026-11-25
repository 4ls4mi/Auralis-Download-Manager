pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import "ClassicIconResources.js" as Assets
import "ClassicIconFallback.js" as Original

Item {
    id: root

    required property string iconName
    property color ink: MaterialTheme.palette.ink
    readonly property var palette: MaterialTheme.palette
    readonly property string setName: palette.mdmIconSet || ""
    readonly property string iconStyle: palette.mdmIconStyle || "color"
    readonly property color disabledInk: palette.mdm?.iconDisabled || palette.muted
    readonly property color visibleInk: enabled ? ink : disabledInk
    readonly property real physicalSize: Math.max(width, height) * Screen.devicePixelRatio
    readonly property int rasterSize: Math.max(1, Math.round(physicalSize))
    readonly property string asset: themedAsset()
    readonly property bool symbolicPng: asset.endsWith("-symbolic.png")
    readonly property bool symbolicSvg: typeof Assets.paths[asset] === "string"
    readonly property string themedUrl: themedSource()
    readonly property bool themedReady: symbolicPng ? tintedPng.ready : rawIcon.status === Image.Ready
    readonly property var treeIcons: ({
        "cat-all": "folder",
        "cat-compressed": "page_white_zip",
        "cat-documents": "page_white",
        "cat-music": "music",
        "cat-programs": "application_xp",
        "cat-video": "film",
        "cat-torrents": "page_white",
        "cat-unfinished": "folder_page",
        "cat-finished": "folder_go",
        "cat-queues": "page_white_stack",
        "cat-folder": "folder",
        "cat-folder-open": "folder_go"
    })
    readonly property var captionGlyphs: ({
        "ui-minimize": "minimize",
        "ui-maximize": "maximize",
        "ui-restore": "maximize",
        "ui-close": "close",
        "ui-to-tray": "tray"
    })

    readonly property string fallbackUrl: originalIcon()

    implicitWidth: 24
    implicitHeight: 24

    function themedAsset() {
        if (!setName)
            return ""

        const base = "themes/" + setName + "/icons/"
        let best = ""
        for (const size of [16, 24, 32, 48]) {
            for (const extension of [".png", "-symbolic.png", ".svg", "-symbolic.svg"]) {
                const path = base + size + "/" + iconName + extension
                if (Assets.paths[path]) {
                    best = path
                    const stretch = extension.endsWith(".png") ? 1.0625 : 1.25
                    if (physicalSize <= size * stretch)
                        return best
                    break
                }
            }
        }
        return best
    }

    function themedSource() {
        if (!asset)
            return ""
        const source = Assets.paths[asset]
        if (typeof source !== "string")
            return "qrc:/auralis/classic/" + asset

        const currentInk = String(visibleInk)
        const tinted = source.replace(
            /((?:fill|stroke|stop-color|color)(?:\s*=\s*["']|\s*:\s*))(#[0-9a-f]{8}\b|#[0-9a-f]{6}\b|#[0-9a-f]{3}\b|black\b|white\b|gray\b|grey\b)/gi,
            (part, token, original) => {
                if (!original.startsWith("#"))
                    return token + currentInk
                const digits = original.length === 4 ? 1 : 2
                const red = parseInt(original.substr(1, digits), 16)
                const green = parseInt(original.substr(1 + digits, digits), 16)
                const blue = parseInt(original.substr(1 + digits * 2, digits), 16)
                const maxSpread = digits === 1 ? 1 : 24
                return Math.max(red, green, blue) - Math.min(red, green, blue) <= maxSpread
                    ? token + currentInk : part
            })
        const drawing = tinted.replace(/<svg\b[^>]*>/, opening => /\sfill\s*=/.test(opening)
            ? opening : opening.replace("<svg", '<svg fill="' + currentInk + '"'))
        return "data:image/svg+xml," + encodeURIComponent(drawing)
    }

    function originalIcon() {
        const icon = Original.outlines[iconName]
        if (icon) {
            const first = !enabled ? disabledInk : iconStyle === "mono" ? ink
                : iconStyle === "accent" ? palette.accent : icon[0]
            const last = !enabled ? (palette.mdm?.iconDisabledEnd || disabledInk)
                : iconStyle === "color" ? icon[1] : first
            const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24"'
                + ' fill="none" stroke="url(#g)" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">'
                + '<defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="2" y1="2" x2="22" y2="22">'
                + '<stop offset="0" stop-color="' + first + '"/><stop offset="1" stop-color="' + last + '"/>'
                + '</linearGradient></defs>' + icon[2] + '</svg>'
            return "data:image/svg+xml," + encodeURIComponent(svg)
        }

        const treeIcon = treeIcons[iconName] || (iconName.startsWith("cat-") ? "folder" : "")
        return treeIcon ? "qrc:/auralis/classic/icons/silk/" + treeIcon + ".png" : ""
    }

    Image {
        id: rawIcon
        anchors.fill: parent
        source: root.symbolicPng ? "" : root.themedUrl
        sourceSize: Qt.size(root.rasterSize, root.rasterSize)
        fillMode: Image.PreserveAspectFit
        opacity: root.enabled || root.symbolicSvg ? 1 : 0.45
        visible: status === Image.Ready
    }

    Canvas {
        id: tintedPng
        anchors.fill: parent
        readonly property string sourceUrl: root.symbolicPng ? root.themedUrl : ""
        property string loadedUrl: ""
        property bool ready: false
        visible: sourceUrl.length > 0
        renderStrategy: Canvas.Immediate

        function prepare() {
            ready = false
            if (!available)
                return
            if (loadedUrl && loadedUrl !== sourceUrl)
                unloadImage(loadedUrl)
            loadedUrl = sourceUrl
            if (loadedUrl) {
                if (!isImageLoaded(loadedUrl))
                    loadImage(loadedUrl)
                requestPaint()
            }
        }

        onSourceUrlChanged: prepare()
        onAvailableChanged: prepare()
        onImageLoaded: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        Connections {
            target: root
            function onVisibleInkChanged() { tintedPng.requestPaint() }
        }

        onPaint: {
            const context = getContext("2d")
            const w = Math.round(width)
            const h = Math.round(height)
            context.clearRect(0, 0, w, h)
            if (!loadedUrl || !isImageLoaded(loadedUrl) || w < 1 || h < 1)
                return

            context.drawImage(loadedUrl, 0, 0, w, h)
            context.globalCompositeOperation = "source-in"
            context.fillStyle = root.visibleInk
            context.fillRect(0, 0, w, h)
            context.globalCompositeOperation = "source-over"
            ready = true
        }
    }

    Image {
        anchors.fill: parent
        source: root.themedReady ? "" : root.fallbackUrl
        sourceSize: Qt.size(root.rasterSize, root.rasterSize)
        fillMode: Image.PreserveAspectFit
        visible: status === Image.Ready
        opacity: !root.enabled && root.iconName.startsWith("cat-") ? 0.45 : 1
    }

    DashboardIcon {
        anchors.fill: parent
        visible: !root.themedReady && !root.fallbackUrl
        symbol: root.captionGlyphs[root.iconName] || "file"
        ink: root.visibleInk
    }
}
