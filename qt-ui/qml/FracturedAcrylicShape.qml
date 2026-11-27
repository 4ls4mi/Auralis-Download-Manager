pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import "FracturedAcrylicGeometry.js" as Geometry

Item {
    id: panel

    required property string shard
    required property color face

    readonly property var geometry: Geometry.shape(shard)
    readonly property string edge: shard
    readonly property real cornerRadius: 0
    readonly property var panelVertices: geometry.vertices
    readonly property AuralisWindow panelWindow: Window.window as AuralisWindow
    readonly property real faceOpacity: panelWindow?.acrylicApplied === true
        ? MaterialTheme.opacityFor(MaterialTheme.current) : 1
    property AuralisWindow registeredWindow: null

    function moveRegistration() {
        if (registeredWindow === panelWindow)
            return
        registeredWindow?.unregisterAcrylicPanel(panel)
        registeredWindow = panelWindow
        registeredWindow?.registerAcrylicPanel(panel)
    }

    function faceAt(ink, mix) {
        return MaterialTheme.mix(face, ink, mix, faceOpacity)
    }

    onPanelWindowChanged: moveRegistration()
    Component.onCompleted: moveRegistration()
    Component.onDestruction: registeredWindow?.unregisterAcrylicPanel(panel)

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: panel.width * .2
                y1: 0
                x2: panel.width * .7
                y2: panel.height
                GradientStop { position: 0; color: panel.faceAt("#cfc3eb", .23) }
                GradientStop { position: .28; color: panel.faceAt("#a58ab8", .11) }
                GradientStop { position: .68; color: panel.faceAt("#261832", .13) }
                GradientStop { position: 1; color: panel.faceAt("#b194d5", .11) }
            }
            PathSvg { path: panel.geometry.outline }
        }

        ShapePath {
            fillRule: ShapePath.OddEvenFill
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0
                y1: 0
                x2: panel.width * .7
                y2: panel.height
                GradientStop { position: 0; color: "#40e3d7fe" }
                GradientStop { position: .33; color: "#289d7bb8" }
                GradientStop { position: .71; color: "#351e102e" }
                GradientStop { position: 1; color: "#3ec291db" }
            }
            PathSvg { path: panel.geometry.lip }
        }

        ShapePath {
            fillRule: ShapePath.OddEvenFill
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: panel.width * .22
                y1: 0
                x2: panel.width * .54
                y2: panel.height
                GradientStop { position: 0; color: "#fbddfff5" }
                GradientStop { position: .24; color: "#f0ebd2fb" }
                GradientStop { position: .47; color: "#eac8a0e6" }
                GradientStop { position: .75; color: "#ebdbb7ef" }
                GradientStop { position: 1; color: "#f2f3d2fc" }
            }
            PathSvg { path: panel.geometry.bevel }
        }
    }
}
