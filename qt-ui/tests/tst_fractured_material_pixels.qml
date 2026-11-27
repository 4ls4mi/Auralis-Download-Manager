import QtQuick
import QtTest
import "../qml" as App

TestCase {
    id: test
    name: "FracturedMaterialPixels"
    width: 440
    height: 236
    visible: true
    when: windowShown

    Rectangle {
        id: desktop
        anchors.fill: parent
        color: "#548459"

        App.FracturedPanel {
            id: titleShard
            x: 15
            y: 12
            width: 408
            height: 53
            edge: "header"
            face: "#49385d"
        }

        App.FracturedPanel {
            id: contentShard
            x: 20
            y: 86
            width: 407
            height: 134
            face: "#453653"
            mutedInk: "#e2d4ec"
        }
    }

    Component {
        id: windowFactory
        App.AuralisWindow { acrylicMode: true }
    }

    function takeSample() {
        const image = grabImage(desktop)
        return {
            gap: image.pixel(211, 75),
            perimeter: image.pixel(211, 229),
            interior: [image.pixel(78, 34), image.pixel(340, 41), image.pixel(77, 113),
                       image.pixel(214, 149), image.pixel(363, 184)]
        }
    }

    function distance(first, second) {
        let delta = 0
        for (let index = 0; index < first.length; ++index) {
            const a = first[index]
            const b = second[index]
            delta += Math.abs(a.r - b.r) + Math.abs(a.g - b.g) + Math.abs(a.b - b.b)
        }
        return delta / first.length
    }

    function test_finishChangesPanelsAndKeepsGapsClear_data() {
        return [{tag: "default-opacity", translucency: -1}, {tag: "full-opacity", translucency: 0}]
    }

    function test_finishChangesPanelsAndKeepsGapsClear(row) {
        const original = App.WindowAppearance.snapshot()
        try {
            App.MaterialTheme.current = "fractured-pearl"
            App.MaterialTheme.translucency = row.translucency
            App.MaterialTheme.fracturedFinish = "frosted"
            const window = createTemporaryObject(windowFactory, null)
            verify(window)
            const observed = []
            let previous = takeSample().interior
            for (const choice of App.MaterialTheme.fracturedFinishChoices) {
                App.MaterialTheme.fracturedFinish = choice.value
                compare(window.acrylicFinish, choice.value)
                compare(contentShard.finish, choice.value)
                let sample
                tryVerify(() => {
                    sample = takeSample()
                    return distance(previous, sample.interior) > .035
                }, 1000, choice.value + " changes the rendered shards")
                compare(sample.gap, desktop.color)
                compare(sample.perimeter, desktop.color)
                for (const earlier of observed)
                    verify(distance(earlier.interior, sample.interior) > .035, earlier.finish + " vs. " + choice.value)
                observed.push({finish: choice.value, interior: sample.interior})
                previous = sample.interior
            }
        } finally {
            App.WindowAppearance.applyBackup(original, true)
        }
    }
}
