pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import "FractureGeometry.js" as Geometry

Item {
    id: band

    required property color face
    property color ink: MaterialTheme.controlTextInk(MaterialTheme.palette.ink, face)
    property color mutedInk: ink
    property string edge: "header"
    property var cuts: []
    property bool forceOpaque: false
    property bool maskEnabled: false
    readonly property Item maskSource: mask
    readonly property var pieces: enabled ? Geometry.shards(width, height, cuts, edge) : []
    readonly property int pieceCount: pieces.length

    Repeater {
        model: band.pieces
        FracturedPanel {
            required property var modelData
            anchors.fill: parent
            edge: band.edge
            face: band.face
            ink: band.ink
            mutedInk: band.mutedInk
            forceOpaque: band.forceOpaque
            outlineOverride: modelData
        }
    }

    Shape {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: band.maskEnabled
        layer.smooth: true
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillColor: "white"
            PathSvg { path: band.maskEnabled ? band.pieces.map(piece => piece.path).join(" ") : "" }
        }
    }
}
