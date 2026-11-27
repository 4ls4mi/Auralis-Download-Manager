pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import "../qml" as App
import "../qml/FracturedAcrylicGeometry.js" as AcrylicGeometry

TestCase {
    name: "FracturedAcrylic"
    width: 920
    height: 720
    visible: true
    when: windowShown

    Rectangle {
        id: desktop
        anchors.fill: parent
        color: "#487b51"

        Repeater {
            model: ["header", "main", "playback", "effects"]
            delegate: App.FracturedAcrylicShape {
                required property string modelData
                readonly property var bounds: AcrylicGeometry.bounds[modelData]
                shard: modelData
                x: bounds.x
                y: bounds.y
                width: bounds.width
                height: bounds.height
                face: "#423252"
            }
        }
    }

    function test_nativeVerticesFollowTheTracedShards() {
        const names = ["header", "menu", "main", "playback", "effects", "appearance", "output", "toast"]
        compare(Object.keys(AcrylicGeometry.bounds).length, names.length)
        for (const name of names) {
            const bounds = AcrylicGeometry.bounds[name]
            const shape = AcrylicGeometry.shape(name)
            const outline = shape.outline.trim()
            verify(bounds, name + " bounds")
            verify(outline.startsWith("M") && outline.endsWith("Z"), name + " closed outline")
            verify(shape.lip.length > outline.length, name + " inner lip")
            verify(shape.bevel.length > outline.length, name + " inner bevel")
            verify(shape.vertices.length > 40, name + " native region vertices")
            for (const point of shape.vertices) {
                verify(Number.isFinite(point.x) && point.x > 0 && point.x < bounds.width, name + " vertex within width")
                verify(Number.isFinite(point.y) && point.y > 0 && point.y < bounds.height, name + " vertex within height")
            }
        }
    }

    function test_notchAndComplementaryGapsExposeDesktop() {
        tryVerify(() => {
            const image = grabImage(desktop)
            return image.pixel(250, 300) !== desktop.color
                && image.pixel(720, 308) !== desktop.color
                && image.pixel(700, 460) !== desktop.color
                && image.pixel(594, 234) === desktop.color
                && image.pixel(690, 419) === desktop.color
                && image.pixel(209, 205) === desktop.color
                && image.pixel(209, 225) !== desktop.color
        })
    }
}
