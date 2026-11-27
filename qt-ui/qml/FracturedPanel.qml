pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import QtQuick.Window

Item {
    id: panel

    required property color face
    property color ink: MaterialTheme.controlTextInk(MaterialTheme.palette.ink, face)
    property color mutedInk: ink
    property string edge: "content"
    property real cornerRadius: 6
    property bool forceOpaque: false
    property real requestedOpacity: MaterialTheme.opacityFor(MaterialTheme.current)

    readonly property AuralisWindow panelWindow: Window.window as AuralisWindow
    readonly property bool nativePanelShape: panelWindow?.nativePanelShapeApplied === true
    property var outlineOverride: null
    readonly property var silhouette: outlineOverride || makeOutline(0, true)
    readonly property var panelVertices: silhouette.vertices
    readonly property string bevelPath: outlineOverride?.bevel || silhouette.path + " " + makeOutline(1.15, false).path
    readonly property string finish: panelWindow?.acrylicFinish || MaterialTheme.fracturedFinish
    readonly property var appearances: ({
        acrylic: {
            tint: "#393055", tintStrength: .18, light: "#e2d7ff", sheen: .26,
            shade: "#1a1127", depth: .29, lift: .12, angle: .24, shoulder: .25,
            opacity: 1.05, grain: .13
        },
        mica: {
            tint: "#4d546a", tintStrength: .55, light: "#a9bad7", sheen: .18,
            shade: "#272c40", depth: .20, lift: .025, angle: .9, shoulder: .5,
            opacity: 1.52, grain: 0
        },
        tinted: {
            tint: "#743950", tintStrength: .46, light: "#af708e", sheen: .06,
            shade: "#2c1525", depth: .16, lift: 0, angle: .12, shoulder: .40,
            opacity: 1.43, grain: 0
        },
        blurred: {
            tint: "#263e50", tintStrength: .42, light: "#9bacca", sheen: .15,
            shade: "#171c36", depth: .20, lift: .09, angle: .64, shoulder: .57,
            opacity: .83, grain: 0
        },
        translucent: {
            tint: "#171223", tintStrength: .44, light: "#b8cedd", sheen: .045,
            shade: "#180c21", depth: .14, lift: .025, angle: .13, shoulder: .28,
            opacity: .63, grain: 0
        },
        frosted: {
            tint: "#634d73", tintStrength: .32, light: "#f7e8ff", sheen: .21,
            shade: "#3c2d4c", depth: .16, lift: .115, angle: .36, shoulder: .58,
            opacity: 1.36, grain: .27
        },
        solid: {
            tintStrength: 0, sheen: 0, depth: 0, lift: 0, angle: .22, shoulder: .4,
            opacity: 1, grain: 0
        }
    })
    readonly property var appearance: appearances[finish] || appearances.frosted
    readonly property color baseFace: forceOpaque ? face : tone(face, appearance.tint, appearance.tintStrength)
    readonly property color upperFace: tone(baseFace, appearance.light, appearance.sheen)
    readonly property color lowerFace: tone(baseFace, appearance.shade, appearance.depth)
    readonly property color reflectedFace: tone(lowerFace, appearance.light, appearance.lift)
    readonly property real finishOpacity: MaterialTheme.translucency >= 0 ? requestedOpacity
        : Math.min(1, requestedOpacity * appearance.opacity)
    readonly property real faceOpacity: forceOpaque || finish === "solid" ? 1 : readableOpacity()
    property AuralisWindow registeredWindow: null

    // Each pair is the distance along an edge and its inward depth. Shared
    // rail/content rhythms keep the opening legible across different widths.
    readonly property var cuts: ({
        header: [
            [[.13, .25], [.24, 0], [.42, .65], [.53, .11], [.77, .38]],
            [[.23, .17], [.57, .48]],
            [[.15, .52], [.30, .04], [.44, .25], [.56, .91], [.72, .22], [.83, .38]],
            [[.18, .28], [.59, .35]]
        ],
        menu: [
            [[.15, .62], [.29, .19], [.51, .13], [.63, .52], [.79, .20]],
            [[.35, .19], [.59, .58]],
            [[.19, .24], [.38, .61], [.54, .18], [.72, .38], [.86, 0]],
            [[.26, .32], [.67, .50]]
        ],
        rail: [
            [[.18, .55], [.37, .16], [.54, .57], [.75, .25]],
            [[.14, .42], [.31, .18], [.47, .91], [.58, .26], [.73, .65], [.88, .12]],
            [[.18, .40], [.35, .12], [.58, .70], [.68, .26], [.85, .36]],
            [[.18, .60], [.28, .11], [.49, .19], [.61, .82], [.74, .15]]
        ],
        content: [
            [[.13, .43], [.24, .06], [.39, .79], [.51, .09], [.68, .37], [.82, .14]],
            [[.13, .36], [.24, .09], [.39, .75], [.53, .16], [.66, .64], [.84, .13]],
            [[.14, .18], [.26, .73], [.43, .12], [.56, .56], [.69, .08], [.85, .32]],
            [[.12, .88], [.27, .35], [.42, .74], [.53, .09], [.69, .82], [.86, .58]]
        ],
        footer: [
            [[.16, .30], [.28, .69], [.44, .10], [.58, .53], [.73, .06], [.86, .32]],
            [[.31, .52], [.65, .16]],
            [[.19, .42], [.31, .09], [.56, .58], [.72, .21], [.87, .36]],
            [[.37, .32], [.64, .14]]
        ],
        activity: [
            [[.16, .56], [.27, .11], [.46, .75], [.57, .24], [.73, .35]],
            [[.19, .58], [.30, .18], [.45, .67], [.62, .15], [.79, .40]],
            [[.15, .58], [.23, .23], [.42, .60], [.58, .13], [.72, .38]],
            [[.24, .37], [.42, .13], [.62, .66], [.77, .28]]
        ],
        banner: [
            [[.13, .37], [.32, .18], [.48, .66], [.64, .29], [.81, .09]],
            [[.20, .21], [.38, .60], [.65, .13]],
            [[.13, .44], [.32, .14], [.49, .57], [.61, .20], [.81, .61]],
            [[.25, .31], [.44, .72], [.70, .14]]
        ]
    })

    function moveRegistration() {
        if (registeredWindow === panelWindow)
            return
        registeredWindow?.unregisterAcrylicPanel(panel)
        registeredWindow = panelWindow
        registeredWindow?.registerAcrylicPanel(panel)
    }

    onPanelWindowChanged: moveRegistration()
    Component.onCompleted: moveRegistration()
    Component.onDestruction: registeredWindow?.unregisterAcrylicPanel(panel)

    function readableInk(color) {
        return MaterialTheme.contrastRatio(ink, color) >= 4.5
            && MaterialTheme.contrastRatio(mutedInk, color) >= 4.5
    }

    function tone(base, color, strength) {
        if (strength === 0)
            return base
        const grain = appearance.grain * .39 // Maximum opacity of one grain pixel.
        const readable = candidate => readableInk(MaterialTheme.mix(candidate, "#ffffff", grain, 1))
            && readableInk(MaterialTheme.mix(candidate, "#000000", grain, 1))
        const result = MaterialTheme.mix(base, color, strength, 1)
        if (readable(result))
            return result
        let low = 0
        let high = strength
        for (let step = 0; step < 5; ++step) {
            const middle = (low + high) / 2
            if (readable(MaterialTheme.mix(base, color, middle, 1)))
                low = middle
            else
                high = middle
        }
        return MaterialTheme.mix(base, color, low, 1)
    }

    function readableOpacity() {
        const tones = [upperFace, baseFace, lowerFace, reflectedFace]
        const backgrounds = ["#ffffff", "#000000"]
        const grain = appearance.grain * .39
        const samples = backgrounds.map(desktop => tones.map(color =>
            MaterialTheme.mix(color, desktop, grain, 1)))
        const readable = amount => samples.every((colors, index) => colors.every(color =>
            readableInk(MaterialTheme.mix(backgrounds[index], color, amount, 1))))
        if (readable(finishOpacity))
            return finishOpacity
        let low = finishOpacity
        let high = 1
        for (let step = 0; step < 7; ++step) {
            const middle = (low + high) / 2
            if (readable(middle))
                high = middle
            else
                low = middle
        }
        return high
    }

    function makeOutline(inset, sample) {
        const l = .68 + inset
        const t = l
        const r = width - l
        const b = height - t
        if (r - l < 1 || b - t < 1)
            return {path: "", vertices: []}

        const radius = Math.min(Math.max(1, cornerRadius - inset), (r - l) / 4, (b - t) / 4)
        const maximumDepth = edge === "rail" || edge === "activity" || edge === "content" ? 9 : 6
        const depth = Math.min(maximumDepth, (r - l) / 7, (b - t) / 7)
        const profile = cuts[edge] || cuts.content
        const first = Qt.point(l + radius, t)
        const vertices = sample ? [first] : []
        let cursor = first
        let path = "M " + first.x + " " + first.y
        const line = end => {
            path += " L " + end.x + " " + end.y
            cursor = end
            if (sample)
                vertices.push(end)
        }
        const curve = (control, end) => {
            path += " Q " + control.x + " " + control.y + " " + end.x + " " + end.y
            if (sample) {
                const segments = Math.max(3, Math.min(8, Math.ceil(
                    Math.hypot(end.x - cursor.x, end.y - cursor.y) / 9)))
                for (let step = 1; step <= segments; ++step) {
                    const u = step / segments
                    const v = 1 - u
                    vertices.push(Qt.point(v * v * cursor.x + 2 * v * u * control.x + u * u * end.x,
                                           v * v * cursor.y + 2 * v * u * control.y + u * u * end.y))
                }
            }
            cursor = end
        }
        const between = (a, b, fraction) => Qt.point(a.x + (b.x - a.x) * fraction, a.y + (b.y - a.y) * fraction)
        const side = (end, cuts, normalX, normalY) => {
            const start = cursor
            const knots = [start, ...cuts.map(cut => {
                const base = between(start, end, cut[0])
                const reach = depth * cut[1]
                return Qt.point(base.x + normalX * reach, base.y + normalY * reach)
            }), end]
            for (let index = 1; index < knots.length - 1; ++index) {
                const cusp = knots[index]
                line(between(knots[index - 1], cusp, .72))
                curve(cusp, between(cusp, knots[index + 1], .28))
            }
            line(end)
        }

        side(Qt.point(r - radius, t), profile[0], 0, 1)
        curve(Qt.point(r, t), Qt.point(r, t + radius))
        side(Qt.point(r, b - radius), profile[1], -1, 0)
        curve(Qt.point(r, b), Qt.point(r - radius, b))
        side(Qt.point(l + radius, b), profile[2], 0, -1)
        curve(Qt.point(l, b), Qt.point(l, b - radius))
        side(Qt.point(l, t + radius), profile[3], 1, 0)
        curve(Qt.point(l, t), first)
        return {path: path + " Z", vertices}
    }

    Shape {
        x: .18
        y: .62
        width: panel.width
        height: panel.height
        visible: !panel.nativePanelShape
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: 1.75
            strokeColor: "#4823142f"
            fillColor: "transparent"
            PathSvg { path: panel.silhouette.path }
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0; y1: 0
                x2: panel.width * panel.appearance.angle; y2: panel.height
                GradientStop { position: 0; color: MaterialTheme.rgba(panel.upperFace, panel.faceOpacity) }
                GradientStop { position: panel.appearance.shoulder; color: MaterialTheme.rgba(panel.baseFace, panel.faceOpacity) }
                GradientStop { position: .79; color: MaterialTheme.rgba(panel.lowerFace, panel.faceOpacity) }
                GradientStop { position: 1; color: MaterialTheme.rgba(panel.reflectedFace, panel.faceOpacity) }
            }
            PathSvg { path: panel.silhouette.path }
        }
    }

    Loader {
        anchors.fill: parent
        active: panel.appearance.grain > 0
        sourceComponent: Canvas {
            id: grainCanvas

            opacity: panel.appearance.grain
            antialiasing: true
            property var grainPattern: null
            readonly property var vertices: panel.panelVertices

            onVerticesChanged: requestPaint()
            onAvailableChanged: {
                grainPattern = null
                if (available)
                    requestPaint()
            }

            onPaint: {
                const painter = getContext("2d")
                painter.clearRect(0, 0, width, height)
                if (vertices.length < 3)
                    return

                if (!grainPattern) {
                    const tile = painter.createImageData(128, 128)
                    const pixels = tile.data
                    let seed = 0x2a9d5613
                    for (let offset = 0; offset < pixels.length; offset += 4) {
                        seed = (Math.imul(seed, 1664525) + 1013904223) | 0
                        const value = seed >>> 31 ? 255 : 0
                        pixels[offset] = value
                        pixels[offset + 1] = value
                        pixels[offset + 2] = value
                        pixels[offset + 3] = (seed >>> 23) % 100
                    }
                    grainPattern = painter.createPattern(tile, "repeat")
                }

                painter.beginPath()
                painter.moveTo(vertices[0].x, vertices[0].y)
                for (let index = 1; index < vertices.length; ++index)
                    painter.lineTo(vertices[index].x, vertices[index].y)
                painter.closePath()
                painter.fillStyle = grainPattern
                painter.fill()
            }
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillRule: ShapePath.OddEvenFill
            fillGradient: LinearGradient {
                x1: 0; y1: 0
                x2: panel.width * .30; y2: panel.height
                GradientStop { position: 0; color: MaterialTheme.mix(panel.face, "#d9fff4", .83, .91) }
                GradientStop { position: .35; color: MaterialTheme.mix(panel.face, "#e8c7ff", .57, .85) }
                GradientStop { position: .73; color: MaterialTheme.mix(panel.face, "#7d5f9d", .58, .88) }
                GradientStop { position: 1; color: MaterialTheme.mix(panel.face, "#e7c9f3", .71, .89) }
            }
            PathSvg { path: panel.bevelPath }
        }
    }
}
