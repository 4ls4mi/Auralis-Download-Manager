import QtQuick
import QtQuick3D

// Actual lit Qt Quick 3D geometry for small optical details. The window's
// backdrop remains in the native compositor beneath this transparent scene.
Item {
    id: reflection

    property color tint: "#92cfff"
    property color spectral: "#e4a1ff"
    property bool faceted: false
    property real polish: 0.7
    property real angle: -16

    View3D {
        anchors.fill: parent
        renderMode: View3D.Offscreen
        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Transparent
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.Medium
        }
        camera: OrthographicCamera {
            position: Qt.vector3d(0, 0, 240)
        }
        DirectionalLight {
            brightness: 2.2
            color: "#f3fcff"
            eulerRotation: Qt.vector3d(-40, -46, 0)
        }
        DirectionalLight {
            brightness: 1.5
            color: reflection.spectral
            eulerRotation: Qt.vector3d(25, 48, 0)
        }
        Model {
            source: reflection.faceted ? "#Cube" : "#Sphere"
            scale: Qt.vector3d(reflection.width / 124, reflection.height / 169, .11)
            eulerRotation: Qt.vector3d(9, reflection.faceted ? -22 : 5, reflection.angle)
            opacity: .61
            materials: PrincipledMaterial {
                baseColor: reflection.tint
                roughness: .43 - reflection.polish * .27
                metalness: reflection.faceted ? .24 : .05
                specularAmount: .78
                alphaMode: PrincipledMaterial.Blend
            }
        }
        Model {
            source: reflection.faceted ? "#Cube" : "#Sphere"
            position: Qt.vector3d(-reflection.width * .12, reflection.height * .15, 4)
            scale: Qt.vector3d(reflection.width / 278, reflection.height / 373, .038)
            eulerRotation: Qt.vector3d(0, 0, reflection.angle)
            opacity: .43
            materials: PrincipledMaterial {
                baseColor: "#f6ffff"
                roughness: .12
                metalness: .16
                specularAmount: .7
                alphaMode: PrincipledMaterial.Blend
            }
        }
    }
}
