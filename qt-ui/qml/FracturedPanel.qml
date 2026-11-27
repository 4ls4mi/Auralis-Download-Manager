pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

Shape {
    id: panel

    required property color face
    property string edge: "content"
    property real cornerRadius: 8
    readonly property real lip: Math.min(2.5, width / 24, height / 12)
    readonly property real curve: Math.max(.5, Math.min(cornerRadius, width / 4, height / 4))

    preferredRendererType: Shape.CurveRenderer

    function outline() {
        const w = width - .65
        const h = height - .65
        if (w < 2 || h < 2)
            return ""

        const r = curve
        const d = lip
        const top = edge === "header" ? "" : edge === "rail"
            ? `L ${w * .25} ${.65 + d} L ${w * .45} .65 L ${w * .71} ${.65 + d * .7}`
            : `L ${w * .17} ${.65 + d * .45} L ${w * .36} ${.65 + d} L ${w * .43} .65 L ${w * .72} ${.65 + d * .75}`
        const right = edge === "rail" || edge === "content"
            ? `L ${w - d * .5} ${h * .23} L ${w} ${h * .37} L ${w - d} ${h * .61} L ${w} ${h * .81}`
            : ""
        const bottom = edge === "footer" ? "" : edge === "header"
            ? `L ${w * .81} ${h - d} L ${w * .66} ${h} L ${w * .49} ${h - d} L ${w * .44} ${h} L ${w * .40} ${h} L ${w * .29} ${h - d} L ${w * .14} ${h - d * .4}`
            : `L ${w * .84} ${h - d * .8} L ${w * .69} ${h} L ${w * .52} ${h - d} L ${w * .39} ${h} L ${w * .21} ${h - d * .6}`
        const left = edge === "content" || edge === "activity"
            ? `L ${.65 + d} ${h * .77} L .65 ${h * .55} L ${.65 + d * .8} ${h * .33} L .65 ${h * .22}`
            : ""

        return `M ${r} .65 ${top} L ${w - r} .65 Q ${w} .65 ${w} ${r}
            ${right} L ${w} ${h - r} Q ${w} ${h} ${w - r} ${h}
            ${bottom} L ${r} ${h} Q .65 ${h} .65 ${h - r}
            ${left} L .65 ${r} Q .65 .65 ${r} .65 Z`
    }

    ShapePath {
        strokeWidth: 1
        strokeColor: Qt.lighter(panel.face, 1.22)
        fillGradient: LinearGradient {
            x1: 0; y1: 0
            x2: 0; y2: panel.height
            GradientStop { position: 0; color: Qt.lighter(panel.face, 1.10) }
            GradientStop { position: .48; color: panel.face }
            GradientStop { position: 1; color: Qt.darker(panel.face, 1.035) }
        }
        PathSvg { path: panel.outline() }
    }
}
