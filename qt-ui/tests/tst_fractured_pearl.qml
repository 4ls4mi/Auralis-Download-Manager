pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import "../qml" as App

TestCase {
    id: test
    name: "FracturedPearl"
    width: 400
    height: 140
    visible: true
    when: windowShown

    Rectangle {
        id: desktop
        width: 164
        height: 81
        color: "#487b51"

        App.FracturedPanel {
            width: 81
            height: parent.height
            face: "#3d423e"
            edge: "rail"
        }
        App.FracturedPanel {
            x: 83
            width: 81
            height: parent.height
            face: "#f5f3ed"
            edge: "content"
        }
    }

    Component {
        id: activity
        App.RecentTransfers {
            width: 192
            height: 136
            downloads: [
                {id: 9, file: "Image.png", status: "Complete"},
                {id: 11, file: "Video.mp4", status: "Downloading"},
                {id: 8, file: "Speech.wav", status: "Queued"}
            ]
        }
    }

    function test_seamExposesDesktop() {
        tryVerify(() => {
            const image = grabImage(desktop)
            return image.pixel(40, 40) !== desktop.color && image.pixel(82, 40) === desktop.color
                && image.pixel(123, 40) !== desktop.color
                && image.pixel(80, 49) === desktop.color
        })
    }

    function test_recentActivityUsesDownloadData() {
        const panel = createTemporaryObject(activity, test)
        verify(panel)
        compare(panel.recent.map(item => item.id), [11, 9, 8])
        compare(App.MaterialTheme.profile("fractured-pearl").layout, "fracturedPearl")
    }
}
