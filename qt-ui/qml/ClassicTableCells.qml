pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

Row {
    id: row

    required property var columns
    required property var colors
    property var values: ({})
    property string fileIcon: ""
    property bool heading: false
    property bool selected: false
    property bool torrentSource: false
    signal sortRequested(string column)

    Repeater {
        model: row.columns
        delegate: Item {
            id: cell
            required property var modelData
            readonly property string key: modelData.key
            readonly property string value: String((row.heading ? modelData.label : row.values[key]) ?? "")
            readonly property color ink: row.selected ? row.colors.rowSelectionInk || row.colors.ink : row.colors.ink

            width: modelData.width
            height: row.height
            clip: true

            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: row.heading ? row.colors.mdm?.headerLine || row.colors.divider
                    : Qt.alpha(row.colors.divider, .56)
            }

            ClassicToolbarIcon {
                visible: !row.heading && cell.key === "file" && Boolean(row.fileIcon)
                iconName: visible ? row.fileIcon : ""
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: 14
                ink: cell.ink
            }

            Rectangle {
                visible: !row.heading && cell.key === "source" && Boolean(cell.value)
                x: 5
                width: Math.min(cell.width - 10, badge.implicitWidth + 13)
                height: Math.min(15, cell.height - 2)
                anchors.verticalCenter: parent.verticalCenter
                radius: height / 2
                color: row.torrentSource ? row.colors.accent : row.colors.positive
                Label {
                    id: badge
                    anchors.fill: parent
                    text: cell.value
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    color: MaterialTheme.controlTextInk(cell.ink, parent.color)
                    font.pixelSize: TypographyScale.pixels(10)
                }
            }

            Label {
                visible: row.heading || cell.key !== "source"
                anchors.fill: parent
                leftPadding: !row.heading && cell.key === "file" ? 22 : 5
                rightPadding: 3
                text: cell.value
                textFormat: Text.PlainText
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                color: cell.ink
                font.pixelSize: TypographyScale.pixels(11)
            }

            TapHandler {
                enabled: row.heading && ["file", "size", "status", "added"].includes(cell.key)
                onTapped: row.sortRequested(cell.key)
            }
        }
    }
}
