import QtQuick
import QtTest
import "../qml" as App

TestCase {
    id: test
    name: "GlassDashboard"
    width: 860
    height: 730
    visible: true
    when: windowShown

    property string previousMaterial
    property var previousCustomizations
    property string lastFilter: ""
    property string lastOperation: ""
    property int lastTransfer: 0

    function init() {
        previousMaterial = App.MaterialTheme.current
        previousCustomizations = App.MaterialTheme.materialCustomizations
        lastFilter = ""
        lastOperation = ""
        lastTransfer = 0
        failOnWarning(/Binding loop|TypeError|ReferenceError/)
    }

    function cleanup() {
        App.MaterialTheme.materialCustomizations = previousCustomizations
        App.MaterialTheme.current = previousMaterial
    }

    Component {
        id: preview
        App.GlassDashboard {
            width: 770
            height: 620
            mint: App.MaterialTheme.palette.layout === "mintDeck"
            downloads: [
                {id: 1, file: "Archive.zip", status: "Downloading", size: 1024, downloaded: 512, speed: 128},
                {id: 2, file: "Manual.pdf", status: "Queued", size: 256, downloaded: 0, speed: 0},
                {id: 3, file: "Guide.pdf", status: "Complete", size: 512, downloaded: 512, speed: 0}
            ]
            visuals: ({1: {active_connections: 1, connections: [{id: 0, state: "Receiving"}]}})
            histories: ({1: [64, 96, 128]})
            totalSamples: [64, 96, 128]
            totalSpeed: 128
            selectedId: ""
            commandsAvailable: true
            animate: false
            onListRequested: filter => test.lastFilter = filter
            onTransferRequested: (operation, transfer) => {
                test.lastOperation = operation
                test.lastTransfer = transfer.id
            }
        }
    }

    Component {
        id: sidebar
        App.GlassSurface { role: "sidebar"; roundedPanel: true; width: 120; height: 120 }
    }

    function test_mintRoutesActionsToSelectedTransfer() {
        App.MaterialTheme.current = "mint-transfer-deck"
        const panel = createTemporaryObject(preview, test)
        verify(panel !== null)
        compare(panel.objectName, "mintTransferDeck")
        compare(panel.selected.id, 1)
        const command = findChild(panel, "dashboardTransferAction")
        verify(command !== null)
        mouseClick(command)
        compare(lastOperation, "pause")
        compare(lastTransfer, 1)
        panel.selectedId = "2"
        compare(command.text, "Start")
        mouseClick(command)
        compare(lastOperation, "start")
        compare(lastTransfer, 2)
        mouseClick(findChild(panel, "dashboardAllDownloads"))
        compare(lastFilter, "all")
    }

    function test_studioQueueAndSidebarOverride() {
        App.MaterialTheme.current = "dark-studio"
        const panel = createTemporaryObject(preview, test)
        verify(panel !== null)
        compare(panel.objectName, "darkStudioDashboard")
        mouseClick(findChild(panel, "dashboardQueuedTransfers"))
        compare(lastFilter, "queued")

        const rail = createTemporaryObject(sidebar, test)
        verify(rail !== null)
        verify(rail.frostedStudioLayer)
        App.MaterialTheme.materialCustomizations = {"dark-studio": {sidebar: "#d2af89", text: "#191519"}}
        compare(rail.flatFace, Qt.color("#d2af89"))
        verify(!rail.frostedStudioLayer)

        panel.width = 330
        panel.height = 150
        tryVerify(() => panel.contentHeight > panel.height)
        compare(panel.contentWidth, panel.width)
    }
}
