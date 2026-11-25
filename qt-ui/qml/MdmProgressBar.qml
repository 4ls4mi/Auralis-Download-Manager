pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import "MaterialGeometry.js" as Geometry

Item {
    id: bar

    required property var appearance
    required property real amount
    property string shape: "material"
    property real thicknessScale: 1
    property var trackPaint: null
    readonly property var colors: appearance.mdm
    readonly property string style: appearance.mdmProgress
    readonly property bool isLine: style === "line"
    readonly property real trackHeight: isLine ? Math.min(4 * thicknessScale, height) : Math.max(0, height - 4)

    // Keep each MDM preset's original line/bar/block artwork unless the user
    // explicitly picks a different contour.
    Loader {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: bar.trackHeight
        active: bar.shape !== "material"
        sourceComponent: Shape {
            id: styled
            preferredRendererType: Shape.CurveRenderer
            readonly property real cap: height / 2
            readonly property real inset: bar.isLine ? 0 : 1
            readonly property string outline: Geometry.frame(0, 0, width, height, cap,
                bar.shape === "plain" ? "square" : bar.shape)
            readonly property string filled: fillPath()
            property LinearGradient gloss: LinearGradient {
                x2: 0
                y2: styled.height
                GradientStop { position: 0; color: MaterialTheme.mix(bar.colors.progressFill, bar.colors.gloss, .50, 1) }
                GradientStop { position: .5; color: bar.colors.progressFill }
                GradientStop { position: 1; color: MaterialTheme.mix(bar.colors.progressFill, bar.colors.segmentBorder, .15, 1) }
            }

            property LinearGradient trackTint: LinearGradient {
                x2: styled.width
                y2: 0
                GradientStop { position: 0; color: bar.trackPaint?.start ?? "transparent" }
                GradientStop { position: 1; color: bar.trackPaint?.end ?? "transparent" }
            }

            function fillPath() {
                const full = Math.max(0, width - inset * 2)
                const fillWidth = full * bar.amount
                const paintHeight = Math.max(0, height - inset * 2)
                const shape = bar.shape === "plain" ? "square" : bar.shape
                if (fillWidth <= 0 || paintHeight <= 0)
                    return ""
                if (bar.style !== "blocks")
                    return Geometry.frame(inset, inset, fillWidth, paintHeight, cap, shape)
                const paths = []
                for (let x = 0; x < fillWidth; x += 11)
                    paths.push(Geometry.frame(inset + x, inset, Math.min(9, fillWidth - x), paintHeight, cap, shape))
                return paths.join(" ")
            }

            ShapePath {
                strokeWidth: bar.isLine ? -1 : 1
                strokeColor: bar.trackPaint?.edge ?? bar.colors.segmentBorder
                fillColor: bar.colors.progressTrack
                fillGradient: bar.trackPaint ? styled.trackTint : null
                PathSvg { path: styled.outline }
            }
            ShapePath {
                strokeWidth: -1
                fillGradient: LinearGradient {
                    x2: 0
                    y2: styled.height
                    GradientStop { position: 0; color: bar.trackPaint?.upper ?? "transparent" }
                    GradientStop { position: .50; color: "transparent" }
                    GradientStop { position: 1; color: bar.trackPaint?.lower ?? "transparent" }
                }
                PathSvg { path: bar.trackPaint ? styled.outline : "" }
            }
            ShapePath {
                strokeWidth: -1
                fillColor: bar.colors.progressFill
                fillGradient: bar.style === "gloss" || bar.style === "blocks" ? styled.gloss : null
                PathSvg { path: styled.filled }
            }
        }
    }

    Rectangle {
        id: track
        visible: bar.shape === "material"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: bar.trackHeight
        color: bar.colors.progressTrack
        radius: bar.isLine ? height / 2 : 0
        border.width: bar.isLine ? 0 : 1
        border.color: bar.trackPaint?.edge ?? bar.colors.segmentBorder
        gradient: bar.trackPaint ? track.tint : null

        property Gradient tint: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: bar.trackPaint?.start ?? "transparent" }
            GradientStop { position: 1; color: bar.trackPaint?.end ?? "transparent" }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: track.border.width
            visible: Boolean(bar.trackPaint)
            radius: track.radius
            gradient: Gradient {
                GradientStop { position: 0; color: bar.trackPaint?.upper ?? "transparent" }
                GradientStop { position: .50; color: "transparent" }
                GradientStop { position: 1; color: bar.trackPaint?.lower ?? "transparent" }
            }
        }

        Item {
            id: fill
            x: track.border.width
            y: track.border.width
            width: Math.max(0, track.width - 2 * x) * bar.amount
            height: Math.max(0, track.height - 2 * y)
            clip: true

            Rectangle {
                anchors.fill: parent
                visible: bar.style === "bar" || bar.isLine
                color: bar.colors.progressFill
                radius: track.radius
            }

            Rectangle {
                anchors.fill: parent
                visible: bar.style === "gloss"
                gradient: Gradient {
                    GradientStop { position: 0; color: MaterialTheme.mix(bar.colors.progressFill, bar.colors.gloss, .55, 1) }
                    GradientStop { position: .5; color: bar.colors.progressFill }
                    GradientStop { position: 1; color: MaterialTheme.mix(bar.colors.progressFill, bar.colors.segmentBorder, .16, 1) }
                }
            }

            Row {
                id: blocks
                visible: bar.style === "blocks"
                spacing: 2
                Repeater {
                    model: blocks.visible ? Math.ceil(track.width / 11) : 0
                    delegate: Rectangle {
                        width: 9
                        height: fill.height
                        gradient: Gradient {
                            GradientStop { position: 0; color: MaterialTheme.mix(bar.colors.progressFill, bar.colors.gloss, .43, 1) }
                            GradientStop { position: .4; color: bar.colors.progressFill }
                            GradientStop { position: 1; color: MaterialTheme.mix(bar.colors.progressFill, bar.colors.segmentBorder, .12, 1) }
                        }
                    }
                }
            }
        }
    }
}
