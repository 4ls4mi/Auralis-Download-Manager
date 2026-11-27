pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import "TransferData.js" as Transfer

Flickable {
    id: dashboard
    objectName: mint ? "mintTransferDeck" : "darkStudioDashboard"
    required property bool mint
    required property var downloads
    required property var visuals
    required property var histories
    required property var totalSamples
    required property real totalSpeed
    required property string selectedId
    required property bool commandsAvailable
    required property bool animate

    signal transferSelected(string transferId)
    signal transferOpened(int transferId)
    signal transferRequested(string operation, var transfer)
    signal listRequested(string filter)
    signal addRequested()

    readonly property var colors: MaterialTheme.palette
    readonly property var recent: [...downloads].sort((a, b) => Number(b.id) - Number(a.id))
    readonly property var active: recent.filter(item => item.status === "Downloading")
    readonly property var completed: recent.filter(item => item.status === "Complete")
    readonly property var queued: recent.filter(item => item.status === "Queued")
    readonly property var inProgress: recent.filter(item => item.status !== "Complete")
    readonly property var selected: Transfer.find(downloads, selectedId) ?? active[0] ?? recent[0] ?? null
    readonly property var visual: selected ? visuals[selected.id] || ({}) : ({})
    readonly property bool running: selected?.status === "Downloading"
    readonly property var workers: (visual.connections || []).slice(0, 8)
    readonly property int blockSize: Math.round(23 * (WindowAppearance.connectionBlockSize || 100) / 100)
    readonly property color featureFace: colors.summaryFill || colors.roleFaces?.content || colors.background
    readonly property color featureInk: MaterialTheme.controlTextInk(colors.textOverride || colors.summaryInk || colors.ink,
                                                                     featureFace)
    property real connectionPhase: 0

    clip: true
    contentWidth: width
    contentHeight: body.implicitHeight
    flickableDirection: Flickable.VerticalFlick
    ScrollBar.vertical: Basic.ScrollBar {}

    FrameAnimation {
        running: dashboard.visible && !dashboard.mint && dashboard.running && dashboard.animate
            && dashboard.workers.length > 0 && WindowAppearance.connectionAnimation !== "none"
            && !MaterialTheme.reducedMotion
        property real lastFrame: -1
        onRunningChanged: lastFrame = -1
        onTriggered: {
            if (lastFrame < 0 || elapsedTime - lastFrame >= .033) {
                lastFrame = elapsedTime
                dashboard.connectionPhase = (elapsedTime / 2.2) % 1
            }
        }
    }

    component Panel: Basic.Frame {
        id: panel
        property string surfaceRole: "card"
        padding: 10
        background: GlassSurface { role: panel.surfaceRole; roundedPanel: true }
    }

    component PanelLabel: Label {
        color: dashboard.colors.ink
        font.pixelSize: TypographyScale.pixels(12)
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    component Readout: Panel {
        id: readout
        property string title
        property string value
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        contentItem: ColumnLayout {
            spacing: 3
            PanelLabel {
                Layout.fillWidth: true
                text: readout.title
                color: dashboard.colors.muted
            }
            NumeralLabel {
                Layout.fillWidth: true
                valueText: readout.value
                color: dashboard.colors.ink
                font.weight: Font.Bold
                font.pixelSize: TypographyScale.pixels(18)
                elide: Text.ElideRight
            }
        }
    }

    component FileRow: Basic.ItemDelegate {
        id: fileRow
        required property var modelData
        readonly property bool selectedRow: String(modelData.id) === String(dashboard.selected?.id)
        readonly property color face: selectedRow ? dashboard.featureFace
            : dashboard.colors.roleFaces?.field || dashboard.colors.background
        readonly property color rowInk: MaterialTheme.controlTextInk(dashboard.colors.textOverride ||
            (selectedRow ? dashboard.featureInk : dashboard.colors.ink), face)
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Accessible.name: modelData.file
        Accessible.description: Transfer.statusLabel(modelData.status)
        onClicked: dashboard.transferSelected(String(modelData.id))
        onDoubleClicked: dashboard.transferOpened(Number(modelData.id))
        contentItem: RowLayout {
            spacing: 7
            DashboardIcon {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                symbol: fileRow.modelData.status === "Complete" ? "complete" : "downloads"
                ink: fileRow.rowInk
            }
            PanelLabel {
                Layout.fillWidth: true
                text: fileRow.modelData.file
                color: fileRow.rowInk
            }
            NumeralLabel {
                valueText: fileRow.modelData.status === "Queued" ? qsTr("Queued")
                    : Math.round(Transfer.fraction(fileRow.modelData) * 100) + "%"
                color: fileRow.rowInk
                font.pixelSize: TypographyScale.pixels(11)
            }
        }
        background: GlassSurface {
            roundedPanel: true
            role: fileRow.selectedRow ? "summary" : "field"
            opacity: fileRow.selectedRow || fileRow.hovered || fileRow.visualFocus ? 1 : .46
        }
    }

    component SelectedPanel: Panel {
        id: selectedPanel
        property bool tinted: false
        readonly property color panelInk: tinted ? dashboard.featureInk : dashboard.colors.ink
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        surfaceRole: tinted ? "summary" : "card"
        contentItem: ColumnLayout {
            spacing: 6
            PanelLabel {
                Layout.fillWidth: true
                text: dashboard.selected ? Transfer.statusLabel(dashboard.selected.status) : qsTr("Selected transfer")
                color: selectedPanel.panelInk
            }
            PanelLabel {
                visible: selectedPanel.tinted || dashboard.recent.length <= 1
                Layout.fillWidth: true
                text: dashboard.selected?.file || qsTr("No downloads yet")
                color: selectedPanel.panelInk
                font.pixelSize: TypographyScale.pixels(selectedPanel.tinted ? 19 : 15)
            }
            GlassComboBox {
                visible: !selectedPanel.tinted && dashboard.recent.length > 1
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                model: dashboard.recent
                textRole: "file"
                currentIndex: dashboard.recent.findIndex(item => item.id === dashboard.selected?.id)
                Accessible.name: qsTr("Selected transfer")
                onActivated: index => dashboard.transferSelected(String(dashboard.recent[index].id))
            }
            NumeralLabel {
                visible: dashboard.selected !== null
                Layout.fillWidth: true
                valueText: dashboard.selected?.status === "Complete" ? Transfer.bytes(dashboard.selected.size)
                    : Transfer.rate(dashboard.running ? dashboard.selected.speed : 0)
                color: selectedPanel.panelInk
                font.pixelSize: TypographyScale.pixels(selectedPanel.tinted ? 28 : 21)
                font.weight: Font.Bold
                elide: Text.ElideRight
            }
            TransferGraph {
                visible: dashboard.selected !== null
                Layout.fillWidth: true
                Layout.preferredHeight: selectedPanel.tinted ? 72 : 42
                samples: dashboard.histories[String(dashboard.selected?.id)] || []
                flowActive: dashboard.animate && dashboard.running
                animationStyle: WindowAppearance.graphAnimation
                gridColor: Qt.alpha(selectedPanel.panelInk, .25)
                Accessible.name: qsTr("Selected transfer speed history")
            }
            PanelLabel {
                visible: dashboard.selected !== null
                Layout.fillWidth: true
                text: dashboard.running
                    ? qsTr("%1 left · %2 connections").arg(Transfer.timeLeft(dashboard.selected))
                        .arg(Number(dashboard.visual.active_connections || 0))
                    : Transfer.bytes(dashboard.selected?.size)
                color: selectedPanel.panelInk
            }
            GlassButton {
                visible: dashboard.selected === null
                enabled: dashboard.commandsAvailable
                Layout.fillWidth: true
                text: qsTr("Add URL…")
                onClicked: dashboard.addRequested()
            }
        }
    }

    component TransferControls: Panel {
        readonly property color controlInk: dashboard.mint ? dashboard.featureInk : dashboard.colors.ink
        id: transferControls
        visible: dashboard.selected !== null
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        surfaceRole: dashboard.mint ? "summary" : "card"
        contentItem: ColumnLayout {
            spacing: 5
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2
                    PanelLabel {
                        Layout.fillWidth: true
                        text: dashboard.selected?.file || ""
                        color: transferControls.controlInk
                    }
                    PanelLabel {
                        Layout.fillWidth: true
                        text: Transfer.statusLabel(dashboard.selected?.status)
                        color: transferControls.controlInk
                    }
                }
                GlassButton {
                    objectName: "dashboardTransferAction"
                    visible: dashboard.selected !== null && dashboard.selected.status !== "Complete"
                    enabled: dashboard.commandsAvailable
                    text: dashboard.running ? qsTr("Pause")
                        : dashboard.selected?.status === "Queued" ? qsTr("Start") : qsTr("Resume")
                    onClicked: dashboard.transferRequested(dashboard.running ? "pause" : "start", dashboard.selected)
                }
                GlassButton {
                    text: qsTr("Details")
                    onClicked: dashboard.transferOpened(Number(dashboard.selected.id))
                }
            }
            GlassProgress {
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                baseHeight: 12
                value: Transfer.fraction(dashboard.selected)
                transferState: dashboard.selected?.status || ""
                animated: dashboard.animate && dashboard.running
                animationStyle: WindowAppearance.progressAnimation
                startColor: MaterialTheme.progressColors[0]
                endColor: MaterialTheme.progressColors[1]
            }
        }
    }

    ColumnLayout {
        id: body
        width: Math.max(0, dashboard.width - (dashboard.contentHeight > dashboard.height ? 12 : 0))
        spacing: 7

        Loader {
            Layout.fillWidth: true
            sourceComponent: dashboard.mint ? deck : studio
        }
        TransferControls {}
    }

    Component {
        id: deck
        GridLayout {
            columns: width >= 400 ? 2 : 1
            columnSpacing: 8
            rowSpacing: 8

            SelectedPanel { tinted: true; Layout.alignment: Qt.AlignTop }
            Panel {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignTop
                contentItem: ColumnLayout {
                    spacing: 3
                    PanelLabel { Layout.fillWidth: true; text: qsTr("Transfers") }
                    PanelLabel {
                        visible: !dashboard.inProgress.length
                        Layout.fillWidth: true
                        text: qsTr("No unfinished transfers")
                        color: dashboard.colors.muted
                    }
                    Repeater { model: dashboard.inProgress.slice(0, 4); delegate: FileRow {} }
                    PanelLabel {
                        visible: dashboard.completed.length > 0
                        Layout.fillWidth: true
                        text: qsTr("Recently saved")
                    }
                    Repeater { model: dashboard.completed.slice(0, 2); delegate: FileRow {} }
                    GlassButton {
                        objectName: "dashboardAllDownloads"
                        Layout.fillWidth: true
                        text: qsTr("All downloads")
                        onClicked: dashboard.listRequested("all")
                    }
                }
            }
        }
    }

    Component {
        id: studio
        ColumnLayout {
            spacing: 7
            GridLayout {
                Layout.fillWidth: true
                columns: width >= 385 ? 3 : 1
                columnSpacing: 7
                rowSpacing: 5

                GlassButton {
                    Layout.fillWidth: true
                    text: qsTr("Transfers · %1").arg(dashboard.inProgress.length)
                    onClicked: dashboard.listRequested("unfinished")
                }
                GlassButton {
                    objectName: "dashboardQueuedTransfers"
                    Layout.fillWidth: true
                    text: qsTr("Queue · %1").arg(dashboard.queued.length)
                    accent: dashboard.colors.accent
                    filled: true
                    onClicked: dashboard.listRequested("queued")
                }
                GlassButton {
                    Layout.fillWidth: true
                    text: qsTr("Finished · %1").arg(dashboard.completed.length)
                    accent: dashboard.colors.positive
                    filled: true
                    onClicked: dashboard.listRequested("finished")
                }
            }
            GridLayout {
                Layout.fillWidth: true
                columns: width >= 540 ? 4 : 2
                columnSpacing: 7
                rowSpacing: 6
                Readout { title: qsTr("Total speed"); value: Transfer.rate(dashboard.totalSpeed) }
                Readout { title: qsTr("Downloading"); value: String(dashboard.active.length) }
                Readout {
                    title: qsTr("Active connections")
                    value: String(dashboard.active.reduce((sum, item) =>
                        sum + Number(dashboard.visuals[item.id]?.active_connections || 0), 0))
                }
                Readout {
                    title: qsTr("Completed size")
                    value: Transfer.bytes(dashboard.completed.reduce((sum, item) =>
                        sum + Number(item.size ?? item.downloaded ?? 0), 0))
                }
            }
            GridLayout {
                Layout.fillWidth: true
                columns: width >= 595 ? 3 : width >= 370 ? 2 : 1
                columnSpacing: 8
                rowSpacing: 7
                Panel {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignTop
                    contentItem: ColumnLayout {
                        PanelLabel { text: qsTr("Transfer speed") }
                        TransferGraph {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 76
                            samples: dashboard.totalSamples
                            animationStyle: WindowAppearance.graphAnimation
                            flowActive: dashboard.animate
                            Accessible.name: qsTr("Recent total transfer speed")
                        }
                    }
                }
                SelectedPanel { Layout.alignment: Qt.AlignTop }
                Panel {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignTop
                    surfaceRole: "connections"
                    contentItem: ColumnLayout {
                        PanelLabel { text: qsTr("Connections") }
                        PanelLabel {
                            visible: dashboard.workers.length === 0
                            Layout.fillWidth: true
                            text: qsTr("No connection data")
                            color: dashboard.colors.muted
                        }
                        Flow {
                            id: links
                            Layout.fillWidth: true
                            Layout.preferredHeight: childrenRect.height
                            spacing: 4
                            Repeater {
                                model: dashboard.workers
                                delegate: ConnectionWater {
                                    required property var modelData
                                    required property int index
                                    width: Math.min(links.width, Math.round(dashboard.blockSize * 1.4))
                                    height: dashboard.blockSize
                                    channelIndex: index
                                    connected: dashboard.running
                                    receiving: dashboard.running && modelData.state === "Receiving"
                                    interrupted: modelData.state === "Failed" || modelData.state === "Retrying"
                                    paused: !dashboard.running
                                    value: Transfer.assigned(modelData.id, dashboard.visual.segments, true)
                                    phase: dashboard.connectionPhase
                                    animationStyle: WindowAppearance.connectionAnimation
                                    shape: WindowAppearance.connectionShape === "material"
                                        ? "round" : WindowAppearance.connectionShape
                                    startColor: MaterialTheme.connectionColors[0]
                                    endColor: MaterialTheme.connectionColors[1]
                                    Accessible.name: qsTr("Connection %1").arg(index + 1)
                                }
                            }
                        }
                    }
                }
            }
            GlassButton {
                text: qsTr("All downloads")
                Layout.alignment: Qt.AlignRight
                onClicked: dashboard.listRequested("all")
            }
        }
    }
}
