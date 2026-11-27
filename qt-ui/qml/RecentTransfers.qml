pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "TransferData.js" as TransferData

Frame {
    id: panel

    required property var downloads
    signal detailsRequested(var downloadId)

    readonly property var colors: MaterialTheme.palette
    readonly property var recent: visible ? downloads.slice()
        .sort((first, second) => Number(second.id) - Number(first.id)).slice(0, 8) : []
    padding: 8
    background: GlassSurface {
        role: "card"
        fracturedEdge: "activity"
    }

    ColumnLayout {
        anchors.fill: parent

        Label {
            text: qsTr("Recent downloads")
            color: panel.colors.ink
            font.pixelSize: TypographyScale.pixels(14)
            font.weight: Font.DemiBold
        }
        ListView {
            id: activity
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: panel.recent
            ScrollBar.vertical: ScrollBar {}
            delegate: GlassButton {
                id: transfer
                required property var modelData
                width: activity.width - (activity.ScrollBar.vertical.visible ? 9 : 0)
                padding: 6
                text: modelData.file
                Accessible.description: status.text
                onClicked: panel.detailsRequested(modelData.id)
                contentItem: ColumnLayout {
                    spacing: 1
                    Label {
                        Layout.fillWidth: true
                        text: transfer.text
                        textFormat: Text.PlainText
                        elide: Text.ElideMiddle
                        color: transfer.buttonInk
                    }
                    Label {
                        id: status
                        Layout.fillWidth: true
                        text: TransferData.statusLabel(transfer.modelData.status)
                        elide: Text.ElideRight
                        color: transfer.buttonInk
                        font.pixelSize: TypographyScale.pixels(11)
                    }
                }
            }
            Label {
                anchors.centerIn: parent
                width: parent.width - 8
                visible: activity.count === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: qsTr("No downloads yet")
                color: panel.colors.muted
            }
        }
    }
}
