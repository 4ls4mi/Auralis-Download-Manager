import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: row
    required property string fileName
    required property string sizeLabel
    required property string statusLabel
    required property string speedLabel
    required property string timeLabel
    required property string recoveryLabel
    required property color statusInk
    required property real progress
    required property bool activeTransfer
    required property bool torrent
    required property bool mixed
    required property bool chosen
    required property var colors
    property bool compact: false
    signal selected(int modifiers)
    signal opened()
    signal optionsRequested()

    implicitHeight: recoveryLabel.length ? 78 : 60
    Accessible.role: Accessible.ListItem
    Accessible.name: fileName + ", " + statusLabel + ", " + sizeLabel
    Accessible.selected: chosen
    Accessible.onPressAction: row.opened()

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: row.chosen ? Qt.alpha(row.colors.accent, row.colors.light ? .22 : .20)
             : pointer.containsMouse ? Qt.alpha(row.colors.accent, .11) : "transparent"
        border.width: row.chosen ? 1 : 0
        border.color: Qt.alpha(row.colors.accent, .66)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 11
        anchors.rightMargin: 11
        spacing: 11

        DashboardIcon {
            symbol: row.mixed ? "mixed" : row.torrent ? "peers" : "file"
            ink: row.mixed ? row.colors.secondary : row.colors.accent
            Layout.preferredWidth: 21
            Layout.preferredHeight: 21
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 85
            spacing: 2
            Label {
                Layout.fillWidth: true
                text: row.fileName
                elide: Text.ElideMiddle
                color: row.colors.ink
                font.weight: Font.DemiBold
            }
            Label {
                Layout.fillWidth: true
                text: row.sizeLabel + (row.mixed ? "  ·  " + qsTr("Direct → Torrent") : row.torrent ? "  ·  " + qsTr("Torrent") : "")
                elide: Text.ElideRight
                color: row.colors.muted
                font.pixelSize: 11
            }
            Label {
                visible: row.recoveryLabel.length > 0
                Layout.fillWidth: true
                text: row.recoveryLabel
                elide: Text.ElideRight
                color: row.colors.caution
                font.pixelSize: 11
            }
        }
        Label {
            Layout.preferredWidth: row.compact ? 74 : 92
            text: row.statusLabel
            color: row.statusInk
            elide: Text.ElideRight
            font.pixelSize: 12
        }
        RowLayout {
            Layout.preferredWidth: row.compact ? 117 : 158
            spacing: 6
            GlassProgress {
                Layout.fillWidth: true
                Layout.preferredHeight: 15
                value: row.progress
                animated: row.activeTransfer
                shape: WindowAppearance.progressShape !== "material" ? WindowAppearance.progressShape :
                    ["bubble", "prism", "ice"].includes(profile.shape) ? profile.shape : "round"
                fillStyle: WindowAppearance.progressFill
            }
            Label {
                Layout.preferredWidth: 33
                text: Math.floor(row.progress * 100) + "%"
                horizontalAlignment: Text.AlignRight
                color: row.colors.ink
                font.pixelSize: 11
            }
        }
        Label {
            Layout.preferredWidth: row.compact ? 62 : 83
            text: row.speedLabel
            color: row.colors.ink
            horizontalAlignment: Text.AlignRight
            font.pixelSize: 12
        }
        Label {
            Layout.preferredWidth: row.compact ? 58 : 71
            text: row.timeLabel
            color: row.colors.muted
            horizontalAlignment: Text.AlignRight
            font.pixelSize: 12
        }
    }
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.bottom: parent.bottom
        height: 1
        color: row.colors.divider
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                row.optionsRequested()
            else
                row.selected(mouse.modifiers)
        }
        onDoubleClicked: mouse => {
            if (mouse.button === Qt.LeftButton)
                row.opened()
        }
    }
    ToolTip.visible: pointer.containsMouse && (torrent || recoveryLabel.length > 0)
    ToolTip.delay: 650
    ToolTip.text: fileName + (mixed ? "\n" + qsTr("Started directly and continued via BitTorrent") : torrent ? "\n" + qsTr("BitTorrent download") : "")
        + (recoveryLabel.length ? "\n" + recoveryLabel : "")
}
