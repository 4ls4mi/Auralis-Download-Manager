import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "TransferData.js" as TransferData

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
    required property bool torrent
    required property bool mixed
    required property bool chosen
    required property var colors
    required property var telemetry
    required property var speedSamples
    required property real indicatorWidth
    required property real timeWidth
    property bool cursorFocused: false
    property bool transferring: false
    property bool animationsAllowed: true
    property real waterPhase: 0
    readonly property bool studioChrome: colors.cleanStudio === true
    readonly property string fileSymbol: mixed ? "mixed" : torrent ? "peers"
        : studioChrome && (telemetry.is_video || /\.(mp4|mkv|mov|webm|avi|m4v)$/i.test(fileName)) ? "video" : "file"
    readonly property int connectionCount: torrent ? Number(telemetry.torrent?.peers || 0) : Number(telemetry.active_connections || 0)
    readonly property string connectionLabel: torrent
        ? (connectionCount === 1 ? qsTr("1 peer") : qsTr("%1 peers").arg(connectionCount))
        : (connectionCount === 1 ? qsTr("1 connection") : qsTr("%1 connections").arg(connectionCount))
    readonly property var workers: torrent ? [] : (telemetry.connections || [])
        .filter(connection => connection.state === "Receiving" || connection.state === "Connecting").slice(0, 4)
    NumberAnimation on waterPhase {
        from: 0
        to: Math.PI * 2
        duration: 1350
        loops: Animation.Infinite
        running: row.visible && row.animationsAllowed && row.transferring && row.workers.some(worker => worker.state === "Receiving")
            && !MaterialTheme.reducedMotion && WindowAppearance.connectionAnimation !== "none"
    }

    signal selected(int modifiers)
    signal opened()
    signal optionsRequested()

    implicitHeight: recoveryLabel.length ? 78 : colors.layout === "violetRail" ? 59 : 64
    Accessible.role: Accessible.ListItem
    Accessible.name: [fileName, sizeLabel, statusLabel, speedLabel, connectionLabel].filter(Boolean).join(", ")
    Accessible.selected: chosen
    Accessible.onPressAction: row.opened()

    Rectangle {
        anchors.fill: parent
        radius: row.colors.panelRadius || (row.studioChrome ? 5 : 8)
        color: row.chosen
            ? (row.studioChrome && row.colors.navigationFill
                ? row.colors.rowSelectionFill || row.colors.navigationFill
                : Qt.alpha(row.colors.accent, row.colors.light ? .22 : .20))
            : pointer.containsMouse ? Qt.alpha(row.studioChrome ? row.colors.ink : row.colors.accent,
                                               row.studioChrome ? .055 : .11) : "transparent"
        border.width: row.cursorFocused || (row.chosen && !row.studioChrome) ? 1 : 0
        border.color: row.studioChrome ? row.colors.menuRail || row.colors.accent
            : Qt.alpha(row.colors.accent, row.cursorFocused ? .9 : .66)

        Rectangle {
            visible: row.studioChrome && row.chosen
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.margins: 2
            width: 3
            radius: 1.5
            color: row.colors.menuRail || row.colors.accent
        }
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

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 11
        anchors.rightMargin: 11
        spacing: 9

        CheckBox {
            objectName: "downloadRowCheckBox"
            Layout.preferredWidth: 24
            Layout.preferredHeight: 27
            padding: 2
            checked: row.chosen
            Accessible.name: qsTr("Select %1").arg(row.fileName)
            onClicked: row.selected(Qt.ControlModifier)
            MouseArea {
                anchors.fill: parent
                onClicked: mouse => row.selected(Qt.ControlModifier | mouse.modifiers)
            }
        }
        DashboardIcon {
            symbol: row.fileSymbol
            ink: row.mixed ? row.colors.secondary
                : row.studioChrome && row.colors.light ? row.colors.ink : row.colors.accent
            Layout.preferredWidth: 21
            Layout.preferredHeight: 21
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 85
            spacing: 2
            Label {
                id: fileNameLabel
                Layout.fillWidth: true
                text: row.fileName
                textFormat: Text.PlainText
                font.family: row.Window.window?.fontFamilyForText?.(text) || ""
                elide: Text.ElideMiddle
                color: row.chosen ? row.colors.rowSelectionInk || row.colors.ink : row.colors.ink
                font.weight: Font.DemiBold
            }
            Label {
                Layout.fillWidth: true
                text: row.sizeLabel + (row.mixed ? "  ·  " + qsTr("Direct → Torrent") : row.torrent ? "  ·  " + qsTr("Torrent") : "")
                elide: Text.ElideRight
                color: row.colors.muted
                font.pixelSize: 11
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 5
                Rectangle {
                    Layout.preferredWidth: 6
                    Layout.preferredHeight: 6
                    radius: 3
                    color: row.statusInk
                }
                Label {
                    Layout.minimumWidth: 0
                    text: row.statusLabel
                    color: row.statusInk
                    elide: Text.ElideRight
                    font.pixelSize: 11
                }
                Label {
                    visible: row.speedLabel.length > 0
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: "·  " + row.speedLabel
                    color: row.colors.ink
                    elide: Text.ElideRight
                    font.pixelSize: 11
                }
                Item { visible: !row.speedLabel.length; Layout.fillWidth: true }
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
        RowLayout {
            Layout.fillWidth: false
            Layout.minimumWidth: row.indicatorWidth
            Layout.maximumWidth: row.indicatorWidth
            spacing: 7

            RowLayout {
                Layout.fillWidth: false
                Layout.preferredWidth: Math.floor(row.indicatorWidth * .49)
                Layout.minimumWidth: 71
                spacing: 4
                GlassProgress {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22
                    value: row.progress
                    animated: row.transferring && row.animationsAllowed
                    animationStyle: WindowAppearance.progressAnimation
                    shape: WindowAppearance.progressShape === "material"
                        ? (["bubble", "prism", "ice"].includes(profile.shape) ? profile.shape : "round") : WindowAppearance.progressShape
                    fillStyle: WindowAppearance.progressFill
                    startColor: MaterialTheme.progressColors[0]
                    endColor: MaterialTheme.progressColors[1]
                }
                Label {
                    Layout.preferredWidth: 30
                    text: Math.floor(row.progress * 100) + "%"
                    horizontalAlignment: Text.AlignRight
                    color: row.studioChrome && !row.colors.rowSelectionInk
                        ? row.colors.navigationInk || row.colors.accent : row.colors.ink
                    font.pixelSize: row.studioChrome ? 12 : 11
                    font.weight: row.studioChrome ? Font.Bold : Font.Normal
                }
            }

            ColumnLayout {
                Layout.fillWidth: false
                Layout.preferredWidth: Math.floor(row.indicatorWidth * .24)
                Layout.minimumWidth: 46
                spacing: 1
                RowLayout {
                    visible: row.workers.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 19
                    spacing: 1
                    Repeater {
                        model: row.workers.length
                        delegate: ConnectionWater {
                            required property int index
                            readonly property var worker: row.workers[index] || ({})
                            Layout.fillWidth: true
                            Layout.preferredWidth: 16
                            Layout.preferredHeight: 18
                            value: TransferData.assigned(worker.id, row.telemetry.segments)
                            receiving: row.transferring && worker.state === "Receiving"
                            phase: row.waterPhase
                            shape: WindowAppearance.connectionShape === "material"
                                ? (["bubble", "prism", "ice"].includes(profile.shape) ? profile.shape : "round") : WindowAppearance.connectionShape
                            fillStyle: WindowAppearance.connectionFill
                            animationStyle: WindowAppearance.connectionAnimation
                            startColor: MaterialTheme.connectionColors[0]
                            endColor: MaterialTheme.connectionColors[1]
                        }
                    }
                }
                Label {
                    Layout.fillWidth: true
                    color: row.colors.muted
                    text: row.connectionLabel
                    elide: Text.ElideRight
                    font.pixelSize: 10
                }
            }

            Loader {
                Layout.fillWidth: true
                Layout.preferredWidth: Math.max(25, row.indicatorWidth * .23)
                Layout.preferredHeight: 31
                active: row.speedSamples.length > 1 && row.speedSamples.some(sample => sample > 0)
                sourceComponent: TransferGraph {
                    samples: row.speedSamples
                    animationStyle: WindowAppearance.graphAnimation
                    flowActive: row.transferring && row.animationsAllowed
                    lineColor: MaterialTheme.graphColors[0]
                    endpointColor: MaterialTheme.graphColors[1]
                    gridColor: row.colors.divider
                    Accessible.name: qsTr("Recent transfer speed")
                }
            }
        }
        Label {
            Layout.preferredWidth: row.timeWidth
            Layout.minimumWidth: 0
            text: row.timeLabel
            elide: Text.ElideLeft
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
        color: (row.studioChrome && row.colors.surfaceLine) || row.colors.divider
    }

    PlainTextToolTip {
        visible: pointer.containsMouse && (fileNameLabel.truncated || row.torrent || row.recoveryLabel.length > 0)
        delay: 650
        text: row.fileName + (row.mixed ? "\n" + qsTr("Started directly and continued via BitTorrent")
            : row.torrent ? "\n" + qsTr("BitTorrent download") : "")
            + (row.recoveryLabel.length ? "\n" + row.recoveryLabel : "")
    }
}
