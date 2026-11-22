import QtQuick
import QtQuick.Shapes

Item {
    id: icon
    property string symbol: ""
    property color ink: "#ffffff"
    implicitWidth: 22
    implicitHeight: 22

    readonly property var paths: ({
        app: "M4 4 H20 V20 H4 Z M12 6 V15 M8 11 L12 15 L16 11",
        add: "M12 4 V20 M4 12 H20",
        torrent: "M6 3 H14 L19 8 V20 H5 V3 Z M14 3 V8 H19 M10 8 V17 M8 10 L10 8 L12 10 M8 15 L10 17 L12 15",
        start: "M8 4 L20 12 L8 20 Z",
        stop: "M6 6 H18 V18 H6 Z",
        pause: "M8 5 V19 M16 5 V19",
        remove: "M4 7 H20 M9 7 V4 H15 V7 M6 7 L7 20 H17 L18 7 M10 10 V16 M14 10 V16",
        check: "M9 6 H20 M9 12 H20 M9 18 H20 M3 5 L4 6 L6 4 M3 11 L4 12 L6 10 M3 17 L4 18 L6 16",
        settings: "M10 3 H14 L15 6 L18 7 L21 6 L22 9 L20 12 L21 15 L22 16 L20 19 L17 18 L14 20 L13 22 H10 L9 19 L6 18 L3 19 L2 16 L4 13 L3 10 L2 8 L4 5 L7 6 Z M15.5 12 A3.5 3.5 0 1 0 8.5 12 A3.5 3.5 0 1 0 15.5 12 Z",
        clock: "M21 12 A9 9 0 1 0 3 12 A9 9 0 1 0 21 12 Z M12 6 V12 L16 14",
        downloads: "M4 14 V20 H20 V14 M12 3 V15 M7 10 L12 15 L17 10",
        activity: "M2 12 H6 L9 5 L13 19 L16 12 H22",
        complete: "M21 12 A9 9 0 1 0 3 12 A9 9 0 1 0 21 12 Z M7 12 L10.5 15.5 L17 9",
        folder: "M3 6 H9 L11 8 H21 V19 H3 Z",
        queue: "M3 6 H21 M3 12 H16 M3 18 H11",
        file: "M5 3 H14 L19 8 V21 H5 Z M14 3 V8 H19",
        search: "M17 10 A7 7 0 1 0 3 10 A7 7 0 1 0 17 10 Z M15 15 L21 21",
        minimize: "M6 12 H18",
        maximize: "M6 6 H18 V18 H6 Z",
        restore: "M9 6 H18 V15 M6 9 H15 V18 H6 Z",
        close: "M6 6 L18 18 M18 6 L6 18",
        peers: "M12 3 L21 18 H3 Z M12 3 V13 M3 18 L12 13 L21 18",
        mixed: "M4 4 H10 V10 H4 Z M10 7 H17 L20 10 L17 13 M17 10 V16 H21 V21 H16 V16",
        chevron: "M6 9 L12 15 L18 9"
    })

    Shape {
        anchors.centerIn: parent
        width: 24
        height: 24
        scale: Math.min(icon.width, icon.height) / 24
        ShapePath {
            strokeColor: icon.ink
            fillColor: "transparent"
            strokeWidth: 1.65
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: icon.paths[icon.symbol] || "" }
        }
    }
}
