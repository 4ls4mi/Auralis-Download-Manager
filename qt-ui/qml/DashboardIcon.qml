pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

Item {
    id: icon
    property string symbol: ""
    property bool bold: false
    property bool solid: false
    property bool relief: false
    property color ink: "#ffffff"
    property color surface: "#252a32"
    property real sheen: 0
    implicitWidth: 22
    implicitHeight: 22
    readonly property real glyphScale: Math.min(width, height) / 24
    readonly property real lineWidth: bold ? 2.2 : 1.75
    readonly property string glyph: paths[symbol] || ""
    readonly property color shadow: MaterialTheme.mix(ink, surface, .77, 1)
    readonly property color highlight: MaterialTheme.mix(ink, "#ffffff", .30, 1)

    readonly property var paths: ({
        app: "M4 4 H20 V20 H4 Z M12 6 V15 M8 11 L12 15 L16 11",
        studioMark: "M2 15 C5 15 6 6 10 6 C14 6 15 18 18 18 C20 18 21 12 22 12",
        add: "M12 4 V20 M4 12 H20",
        torrent: "M5 3 H14 L19 8 V21 H5 Z M14 3 V8 H19 M10 8 V17 M8 10 L10 8 L12 10 M8 15 L10 17 L12 15",
        start: "M8 4 L20 12 L8 20 Z",
        stop: "M6 6 H18 V18 H6 Z",
        pause: "M8 5 V19 M16 5 V19",
        remove: "M4 7 H20 M9 7 V4 H15 V7 M6 7 L7 20 H17 L18 7 M10 10 V16 M14 10 V16",
        check: "M9 6 H20 M9 12 H20 M9 18 H20 M3 5 L4 6 L6 4 M3 11 L4 12 L6 10 M3 17 L4 18 L6 16",
        settings: "M10 3 H14 L14.8 5.8 L16.5 6.8 L19.4 6 L21.4 9.5 L19.2 11.2 V12.8 L21.4 14.5 L19.4 18 L16.5 17.2 L14.8 18.2 L14 21 H10 L9.2 18.2 L7.5 17.2 L4.6 18 L2.6 14.5 L4.8 12.8 V11.2 L2.6 9.5 L4.6 6 L7.5 6.8 L9.2 5.8 Z M15.1 12 A3.1 3.1 0 1 0 8.9 12 A3.1 3.1 0 1 0 15.1 12 Z",
        clock: "M21 12 A9 9 0 1 0 3 12 A9 9 0 1 0 21 12 Z M12 6 V12 L16 14",
        downloads: "M4 14 V20 H20 V14 M12 3 V15 M7 10 L12 15 L17 10",
        activity: "M2 12 H6 L9 5 L13 19 L16 12 H22",
        complete: "M21 12 A9 9 0 1 0 3 12 A9 9 0 1 0 21 12 Z M7 12 L10.5 15.5 L17 9",
        folder: "M3 6 H9 L11 8 H21 V19 H3 Z",
        queue: "M3 6 H21 M3 12 H16 M3 18 H11",
        file: "M5 3 H14 L19 8 V21 H5 Z M14 3 V8 H19",
        video: "M3.5 8 H20.5 V20.5 H3.5 Z M3.5 8 L5.5 3.5 H20.5 L18.5 8 M8 3.5 L10.5 8 M13.5 3.5 L16 8 M10 11.5 L15 14.5 L10 17.5 Z",
        search: "M17 10 A7 7 0 1 0 3 10 A7 7 0 1 0 17 10 Z M15 15 L21 21",
        move: "M12 3 V21 M3 12 H21 M9 6 L12 3 L15 6 M9 18 L12 21 L15 18 M6 9 L3 12 L6 15 M18 9 L21 12 L18 15",
        tray: "M12 3 V12 M8 8 L12 12 L16 8 M4 11 V19 H20 V11 M4 15 H8 L10 17 H14 L16 15 H20",
        minimize: "M4 12 H20",
        maximize: "M6 6 H18 V18 H6 Z",
        restore: "M9 6 H18 V15 M6 9 H15 V18 H6 Z",
        close: "M6 6 L18 18 M18 6 L6 18",
        peers: "M12 3 L21 18 H3 Z M12 3 V13 M3 18 L12 13 L21 18",
        mixed: "M4 4 H10 V10 H4 Z M10 7 H17 L20 10 L17 13 M17 10 V16 H21 V21 H16 V16",
        details: "M21 12 A9 9 0 1 0 3 12 A9 9 0 1 0 21 12 Z M12 11 V17 M12 7 V8",
        refresh: "M19 9 A8 8 0 1 0 19 16 M19 3 V9 H13",
        keys: "M3 5 H21 V18 H3 Z M6 9 H7 M10 9 H11 M14 9 H15 M17 9 H18 M7 14 H17",
        web: "M21 12 A9 9 0 1 0 3 12 A9 9 0 1 0 21 12 Z M3 12 H21 M12 3 Q4 12 12 21 Q20 12 12 3",
        chevron: "M6 9 L12 15 L18 9"
    })

    Loader {
        anchors.fill: parent
        active: icon.relief
        sourceComponent: Item {
            Shape {
                anchors.centerIn: parent
                width: 24
                height: 24
                scale: icon.glyphScale
                transform: Translate { x: .35; y: .78 }
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: icon.shadow
                    fillColor: icon.solid ? icon.shadow : "transparent"
                    strokeWidth: icon.lineWidth + .45
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: icon.glyph }
                }
            }
        }
    }

    Shape {
        anchors.centerIn: parent
        width: 24
        height: 24
        scale: icon.glyphScale
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: icon.ink
            fillGradient: icon.relief && icon.solid ? icon.beveledFill : null
            fillColor: icon.solid ? icon.ink : "transparent"
            strokeWidth: icon.relief && icon.solid ? 1.4 : icon.lineWidth
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: icon.glyph }
        }
    }

    readonly property LinearGradient beveledFill: LinearGradient {
        x1: 6
        y1: 4
        x2: 18
        y2: 20
        GradientStop { position: 0; color: icon.highlight }
        GradientStop { position: .40; color: icon.ink }
        GradientStop { position: 1; color: MaterialTheme.mix(icon.ink, icon.shadow, .43, 1) }
    }

    Loader {
        anchors.fill: parent
        active: icon.relief
        sourceComponent: Item {
            Shape {
                anchors.centerIn: parent
                width: 24
                height: 24
                scale: icon.glyphScale
                transform: Translate { x: -.16; y: -.42 }
                opacity: .26 + .32 * icon.sheen
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: icon.highlight
                    strokeWidth: .72
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: icon.glyph }
                }
            }
        }
    }
}
