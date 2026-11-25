pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: bar

    required property var appearance
    required property real amount
    readonly property var colors: appearance.mdm
    readonly property string style: appearance.mdmProgress
    readonly property bool isLine: style === "line"

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: bar.isLine ? Math.min(4, bar.height) : Math.max(0, bar.height - 4)
        color: bar.colors.progressTrack
        radius: bar.isLine ? height / 2 : 0
        border.width: bar.isLine ? 0 : 1
        border.color: bar.colors.segmentBorder

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
