import QtQuick
import QtTest
import "../qml" as App

TestCase {
    id: test
    name: "FracturedBand"
    width: 720
    height: 140
    visible: true
    when: windowShown

    Rectangle {
        anchors.fill: parent
        color: "#236d69"

        App.FracturedBand {
            id: header
            width: parent.width
            height: 56
            edge: "header"
            face: "#483455"
            forceOpaque: true
            cuts: [{x: 350, slant: -52, gap: 12}]
        }
        App.FracturedBand {
            id: footer
            width: parent.width
            y: 70
            height: 64
            edge: "footer"
            face: "#483455"
            forceOpaque: true
            cuts: [{x: 130, slant: 0, gap: 12}, {x: 360, slant: 105, gap: 15}, {x: 590, slant: 0, gap: 12}]
        }
        App.FracturedBand {
            id: narrow
            visible: false
            width: 120
            height: 56
            face: "#483455"
            cuts: [{x: 21, slant: -74, gap: 24}]
        }
    }

    function test_titleAndFooterHaveClearGaps() {
        compare(header.pieceCount, 2)
        compare(footer.pieceCount, 4)
        tryVerify(() => {
            const image = grabImage(test)
            const background = image.pixel(3, 65)
            return image.pixel(364, 13) === background
                && image.pixel(333, 44) === background
                && image.pixel(310, 24) !== background
                && image.pixel(400, 24) !== background
                && image.pixel(130, 103) === background
                && image.pixel(360, 102) === background
                && image.pixel(590, 102) === background
                && image.pixel(255, 102) !== background
                && image.pixel(460, 102) !== background
        })
    }

    function test_narrowBandKeepsAnUsablePanel() {
        compare(narrow.pieceCount, 1)
    }
}
