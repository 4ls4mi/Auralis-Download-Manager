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
    readonly property bool nativeAcrylic: panelWindow?.acrylicApplied === true
    property var outlineOverride: null
    readonly property var silhouette: outlineOverride || makeOutline(0, true)
    readonly property var panelVertices: silhouette.vertices
    readonly property string bevelPath: outlineOverride?.bevel || silhouette.path + " " + makeOutline(1.15, false).path
    readonly property string finish: panelWindow?.acrylicFinish || MaterialTheme.fracturedFinish
    readonly property var appearances: ({
        acrylic: {light: "#c5b5e3", glow: .085, shade: .13, opacity: .92},
        mica: {light: "#adb2d7", glow: .075, shade: .035, opacity: .82},
        tinted: {light: face, glow: 0, shade: .11, opacity: 1.24},
        blurred: {light: "#aba8c9", glow: .055, shade: .045, opacity: .76},
        translucent: {light: face, glow: 0, shade: .015, opacity: .66},
        frosted: {light: "#e3d4f5", glow: .15, shade: .075, opacity: 1.02}
    })
    readonly property var appearance: appearances[finish] || appearances.frosted
    readonly property color upperFace: forceOpaque ? face : MaterialTheme.mix(face, appearance.light, appearance.glow, 1)
    readonly property color lowerFace: forceOpaque ? face : MaterialTheme.mix(face, "#251631", appearance.shade, 1)
    readonly property real finishOpacity: MaterialTheme.translucency >= 0 ? requestedOpacity
        : Math.min(1, requestedOpacity * appearance.opacity)
    readonly property real faceOpacity: forceOpaque || finish === "solid" || (finish === "mica" && !nativeAcrylic)
        ? 1 : readableOpacity()
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

    function readableOpacity() {
        const desktop = MaterialTheme.relativeLuminance(face) < .179 ? "#ffffff" : "#000000"
        const worstFace = desktop === "#ffffff" ? upperFace : lowerFace
        const readable = amount => {
            const color = MaterialTheme.mix(desktop, worstFace, amount, 1)
            return MaterialTheme.contrastRatio(ink, color) >= 4.5
                && MaterialTheme.contrastRatio(mutedInk, color) >= 4.5
        }
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
        visible: !panel.nativeAcrylic
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
                x2: panel.width * .22; y2: panel.height
                GradientStop { position: 0; color: MaterialTheme.rgba(panel.upperFace, panel.faceOpacity) }
                GradientStop { position: .40; color: MaterialTheme.rgba(panel.face, panel.faceOpacity) }
                GradientStop { position: .84; color: MaterialTheme.rgba(panel.lowerFace, panel.faceOpacity) }
                GradientStop { position: 1; color: MaterialTheme.rgba(panel.face, panel.faceOpacity) }
            }
            PathSvg { path: panel.silhouette.path }
        }

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
