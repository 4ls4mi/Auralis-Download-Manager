import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Window
import "TransferData.js" as TransferData

ApplicationWindow {
    id: root
    objectName: "mainWindow"
    title: qsTr("Auralis Download Manager")
    width: 1120
    height: 735
    minimumWidth: 740
    minimumHeight: 524
    visible: !engine.startHidden
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint

    readonly property var colors: MaterialTheme.palette
    palette.window: colors.background
    palette.windowText: colors.ink
    palette.base: colors.background
    palette.text: colors.ink
    palette.button: colors.background
    palette.buttonText: colors.ink
    palette.highlight: Qt.alpha(colors.accent, .46)
    palette.highlightedText: colors.ink
    palette.placeholderText: colors.muted
    readonly property var downloads: engine.dashboard.downloads || []
    readonly property var queues: engine.dashboard.queues || []
    readonly property var categories: engine.dashboard.categories || []
    readonly property var visualById: {
        const byId = {}
        for (const transfer of (engine.visuals.downloads || []))
            byId[transfer.id] = transfer
        return byId
    }
    readonly property var counts: {
        let active = 0, stopped = 0, completed = 0
        for (const entry of downloads) {
            if (entry.status === "Downloading") ++active
            if (entry.status === "Stopped") ++stopped
            if (entry.status === "Complete") ++completed
        }
        return {all: downloads.length, downloading: active, stopped: stopped,
                unfinished: downloads.length - completed, finished: completed}
    }
    readonly property var currentQueue: {
        if (filterType === "queue")
            return queues.find(queue => queue.name === filterKey) || null
        return queues.length ? queues[0] : null
    }
    readonly property bool compact: width < 920
    readonly property int layoutInset: visibility === Window.Maximized ? 0 : 8
    readonly property bool online: engine.ready
    readonly property string filterTitle: filterType === "category"
        ? ((categories.find(category => category.key === filterKey) || {}).name || filterKey)
        : filterType === "queue" ? filterKey
        : ((statusFilters.find(filter => filter.key === filterKey) || {}).label || qsTr("All Downloads"))
    readonly property var statusFilters: [
        {key: "all", label: qsTr("All Downloads"), icon: "downloads"},
        {key: "downloading", label: qsTr("Downloading"), icon: "activity"},
        {key: "stopped", label: qsTr("Stopped"), icon: "pause"},
        {key: "unfinished", label: qsTr("Unfinished"), icon: "clock"},
        {key: "finished", label: qsTr("Finished"), icon: "complete"}
    ]
    readonly property var recoveryLabels: ({
        "searching": qsTr("Searching for a matching torrent"),
        "matched": qsTr("Review torrent match"),
        "no-match": qsTr("No verified torrent match"),
        "search-failed": qsTr("Torrent search failed"),
        "preparing": qsTr("Preparing torrent recovery"),
        "handoff-failed": qsTr("Torrent recovery failed")
    })

    property string filterType: "status"
    property string filterKey: "all"
    property string searchTerm: ""
    property int sortOrder: 0
    property bool showSidebar: true
    property var chosenIds: []
    property string selectionAnchor: ""
    readonly property var chosenItems: downloads.filter(item => chosenIds.includes(String(item.id)))
    readonly property var currentItem: chosenItems.find(item => String(item.id) === selectionAnchor) || chosenItems[0] || null
    property var detailWindows: ({})
    property var graphValues: []
    property var recoveryDismissed: ({})
    property bool busy: false
    property string actionError: ""
    readonly property var recoveryNotice: downloads.find(item => {
        const visual = visualById[item.id]
        if (!visual || recoveryDismissed[item.id] === visual.recovery_stage)
            return false
        return (visual.recovery_auto_search && ["matched", "preparing"].includes(visual.recovery_stage))
            || (visual.recovery_stage === "handed-off" && visual.recovery_handoff_available && item.status === "Downloading")
    }) || null

    function statusText(status) {
        const labels = {Queued: qsTr("Queued"), Downloading: qsTr("Downloading"), Stopped: qsTr("Paused"),
                        Complete: qsTr("Completed"), Error: qsTr("Failed")}
        return labels[status] || status
    }

    function statusColor(status) {
        switch (status) {
        case "Downloading": return colors.accent
        case "Complete": return colors.positive
        case "Stopped": return colors.caution
        case "Error": return colors.destructive
        default: return colors.muted
        }
    }

    function matchesFilter(item, queueIds, terms) {
        if (filterType === "category" && item.category !== filterKey)
            return false
        if (filterType === "queue" && !queueIds.has(Number(item.id)))
            return false
        if (filterType === "status") {
            switch (filterKey) {
            case "downloading": if (item.status !== "Downloading") return false; break
            case "stopped": if (item.status !== "Stopped") return false; break
            case "unfinished": if (item.status === "Complete") return false; break
            case "finished": if (item.status !== "Complete") return false; break
            }
        }
        const haystack = [item.file, item.url, item.path, item.category].join(" ").toLocaleLowerCase()
        return terms.every(word => haystack.includes(word))
    }

    function synchronizeRows() {
        if (!rows)
            return
        const terms = searchTerm.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean)
        const queueIds = new Set(filterType === "queue" && currentQueue ? currentQueue.ids.map(Number) : [])
        const shown = downloads.filter(item => matchesFilter(item, queueIds, terms))
        shown.sort((a, b) => {
            switch (sortOrder) {
            case 1: return Number(a.id) - Number(b.id)
            case 2: return String(a.file).localeCompare(String(b.file)) || Number(b.id) - Number(a.id)
            case 3: return Number(b.size || 0) - Number(a.size || 0) || Number(b.id) - Number(a.id)
            case 4: return String(a.status).localeCompare(String(b.status)) || Number(b.id) - Number(a.id)
            default: return Number(b.id) - Number(a.id)
            }
        })
        for (let index = 0; index < shown.length; ++index) {
            const entry = shown[index]
            const record = {
                transferId: String(entry.id),
                file: String(entry.file),
                status: String(entry.status),
                bytes: Number(entry.downloaded || 0),
                length: entry.size === null || entry.size === undefined ? -1 : Number(entry.size),
                transferSpeed: Number(entry.speed || 0)
            }
            let match = index
            while (match < rows.count && rows.get(match).transferId !== record.transferId)
                ++match
            if (match === rows.count) {
                rows.insert(index, record)
            } else {
                if (match !== index)
                    rows.move(match, index, 1)
                rows.set(index, record)
            }
        }
        if (rows.count > shown.length)
            rows.remove(shown.length, rows.count - shown.length)
        const existing = new Set(downloads.map(item => String(item.id)))
        const visibleIds = new Set(shown.map(item => String(item.id)))
        chosenIds = chosenIds.filter(id => visibleIds.has(id))
        if (!visibleIds.has(selectionAnchor))
            selectionAnchor = ""
        for (const id in detailWindows) {
            if (!existing.has(id)) {
                detailWindows[id].destroy()
                delete detailWindows[id]
            }
        }
    }

    function chooseFilter(type, key) {
        filterType = type
        filterKey = key
        chosenIds = []
        selectionAnchor = ""
        list.currentIndex = -1
        synchronizeRows()
        list.positionViewAtBeginning()
    }

    function selectRow(index, modifiers) {
        if (index < 0 || index >= rows.count)
            return
        const key = rows.get(index).transferId
        list.currentIndex = index
        list.forceActiveFocus()
        if ((modifiers & Qt.ShiftModifier) && selectionAnchor) {
            let start = 0
            while (start < rows.count && rows.get(start).transferId !== selectionAnchor)
                ++start
            if (start < rows.count) {
                const range = []
                for (let i = Math.min(start, index); i <= Math.max(start, index); ++i)
                    range.push(rows.get(i).transferId)
                chosenIds = range
                return
            }
        }
        if (modifiers & Qt.ControlModifier)
            chosenIds = chosenIds.includes(key) ? chosenIds.filter(id => id !== key) : chosenIds.concat([key])
        else
            chosenIds = [key]
        selectionAnchor = key
    }

    function selectEveryRow() {
        const ids = []
        for (let index = 0; index < rows.count; ++index)
            ids.push(rows.get(index).transferId)
        chosenIds = ids
        if (ids.length)
            selectionAnchor = ids[0]
    }

    function request(command, refresh, callback) {
        if (!online || busy)
            return
        busy = true
        actionError = ""
        engine.request(command, (response, error) => {
            busy = false
            const failure = error || (response && response.error)
            if (failure) {
                actionError = String(failure)
                return
            }
            if (response && response.skipped && response.skipped.length)
                actionError = response.skipped.map(item => item.why).join(" · ")
            if (refresh)
                engine.refresh()
            if (callback)
                callback(response)
        })
    }

    function eligible(operation, items) {
        return items.filter(item => operation === "start" ? item.status !== "Downloading" && item.status !== "Complete"
                            : operation === "pause" ? item.status === "Downloading" : item.status !== "Downloading")
    }

    function transferAction(operation, items) {
        const ids = eligible(operation, items).map(item => Number(item.id))
        if (ids.length)
            request({action: operation, ids: ids}, true)
    }

    function itemAction(operation, item, value) {
        if (item)
            request({action: "glass-item", ids: [Number(item.id)], category: operation, queue: value || null}, true)
    }

    function confirmRemoval(items, alsoDelete) {
        const eligibleItems = eligible("remove", items)
        if (!eligibleItems.length)
            return
        removeDialog.entries = eligibleItems
        deleteFiles.checked = alsoDelete
        removeDialog.open()
    }

    function chooseAdd(torrent) {
        addDialog.torrentMode = torrent
        addDialog.open()
    }

    function addDownload() {
        if (online && !busy) {
            if (!visible)
                show()
            if (visibility === Window.Minimized)
                showNormal()
            raise()
            requestActivate()
            chooseAdd(false)
        }
    }

    function showSettings() {
        settingsWindow.show()
        settingsWindow.raise()
        settingsWindow.requestActivate()
    }

    function showBrowserSettings() {
        settingsWindow.showCategory("Browser Integration")
    }

    function showDownload(id) {
        const key = String(id)
        let details = detailWindows[key]
        if (!details) {
            details = detailsFactory.createObject(root, {downloadId: Number(id)})
            if (!details) {
                actionError = qsTr("The download window could not open.")
                return
            }
            detailWindows[key] = details
        }
        details.show()
        details.raise()
        details.requestActivate()
    }

    function toggleMaximized() {
        if (visibility === Window.Maximized)
            showNormal()
        else
            showMaximized()
    }

    onClosing: function(event) {
        if (!engine.trayAvailable) {
            event.accepted = false
            engine.requestQuit()
        }
    }
    onSearchTermChanged: synchronizeRows()
    onSortOrderChanged: synchronizeRows()
    Component.onCompleted: {
        synchronizeRows()
        engine.refresh()
    }

    Connections {
        target: engine
        function onOperationFailed(message) {
            root.actionError = message
        }
        function onDashboardChanged() {
            root.graphValues = root.graphValues.slice(-64).concat([Number(engine.dashboard.speed || 0)])
            if (root.filterType === "queue" && !root.currentQueue)
                root.chooseFilter("status", "all")
            else if (root.filterType === "category" && !root.categories.some(c => c.key === root.filterKey))
                root.chooseFilter("status", "all")
            else
                root.synchronizeRows()
        }
    }

    ListModel { id: rows }
    SettingsWindow { id: settingsWindow }
    UpdateNotice {
        backend: engine
        anchorWindow: root
        onDetailsRequested: update => settingsWindow.showUpdate(update)
    }
    AddDownloadDialog { id: addDialog; parent: root.contentItem }
    Component { id: detailsFactory; DownloadWindow {} }
    GalleryDownloadDialog {
        id: galleryDialog
        parent: root.contentItem
        onHelpersRequested: settingsWindow.showCategory("Advanced")
    }
    BatchDownloadDialog { id: batchDialog; parent: root.contentItem }
    EnginePrompts {
        id: enginePrompts
        popupParent: root.contentItem
        onShowProgressRequested: downloadId => root.showDownload(downloadId)
        onQuitRequested: engine.requestQuit()
    }

    Action {
        id: addUrl
        text: qsTr("Add URL…")
        shortcut: "Ctrl+N"
        enabled: root.online && !root.busy
        onTriggered: root.chooseAdd(false)
    }
    Action {
        id: addTorrent
        text: qsTr("Add torrent…")
        shortcut: "Ctrl+O"
        enabled: root.online && !root.busy
        onTriggered: root.chooseAdd(true)
    }
    Action {
        id: resumeTransfers
        text: qsTr("Resume")
        enabled: root.online && !root.busy && root.eligible("start", root.chosenItems).length > 0
        onTriggered: root.transferAction("start", root.chosenItems)
    }
    Action {
        id: pauseTransfers
        text: qsTr("Pause")
        enabled: root.online && !root.busy && root.eligible("pause", root.chosenItems).length > 0
        onTriggered: root.transferAction("pause", root.chosenItems)
    }
    Action {
        id: stopAll
        text: qsTr("Pause all")
        enabled: root.online && !root.busy && root.counts.downloading > 0
        onTriggered: root.request({action: "glass-bulk", category: "stop-all"}, true)
    }
    Action {
        id: removeSelection
        text: qsTr("Remove…")
        enabled: root.online && !root.busy && root.eligible("remove", root.chosenItems).length > 0
        onTriggered: root.confirmRemoval(root.chosenItems, false)
    }
    Action {
        id: removeCompleted
        text: qsTr("Remove completed…")
        enabled: root.online && !root.busy && root.counts.finished > 0
        onTriggered: root.confirmRemoval(root.downloads.filter(item => item.status === "Complete"), false)
    }
    Action {
        id: settingsAction
        text: qsTr("Settings")
        shortcut: "Ctrl+,"
        onTriggered: root.showSettings()
    }
    Action {
        id: schedulerAction
        text: qsTr("Scheduler")
        onTriggered: settingsWindow.showCategory("Scheduler")
    }
    Action {
        id: startQueue
        text: qsTr("Start queue")
        enabled: root.online && !root.busy && root.currentQueue !== null && !root.currentQueue.running
        onTriggered: root.request({action: "start_queue", queue: root.currentQueue.name}, true)
    }
    Action {
        id: stopQueue
        text: qsTr("Stop queue")
        enabled: root.online && !root.busy && root.currentQueue !== null && root.currentQueue.running
        onTriggered: root.request({action: "stop_queue", queue: root.currentQueue.name}, true)
    }
    Action {
        id: detailsAction
        text: qsTr("Download details")
        enabled: root.currentItem !== null
        onTriggered: root.showDownload(root.currentItem.id)
    }
    Action {
        id: openWith
        text: qsTr("Open with…")
        enabled: root.online && !root.busy && root.currentItem !== null && root.currentItem.status === "Complete"
        onTriggered: root.itemAction("open-with", root.currentItem)
    }
    Action {
        id: moveFile
        text: qsTr("Move or rename…")
        shortcut: "Ctrl+M"
        enabled: root.online && !root.busy && root.currentItem !== null && root.currentItem.status !== "Downloading"
                 && (root.currentItem.status === "Complete" || !root.currentItem.downloaded)
        onTriggered: {
            moveDialog.entry = root.currentItem
            moveDialog.open()
        }
    }
    Action {
        id: restartFile
        text: qsTr("Redownload from the start…")
        enabled: {
            const item = root.currentItem
            const visual = item ? root.visualById[item.id] : null
            return root.online && !root.busy && item !== null && item.status !== "Downloading"
                && Boolean(visual) && !visual.is_torrent && !visual.is_video && !["searching", "preparing"].includes(visual.recovery_stage)
        }
        onTriggered: {
            restartDialog.entry = root.currentItem
            restartDialog.open()
        }
    }
    Action {
        id: findAction
        text: qsTr("Find a download")
        shortcut: "Ctrl+F"
        onTriggered: searchField.forceActiveFocus()
    }
    Action {
        id: refreshAction
        text: qsTr("Refresh")
        shortcut: StandardKey.Refresh
        onTriggered: engine.refresh()
    }

    Dialog {
        id: removeDialog
        title: qsTr("Remove downloads")
        parent: root.contentItem
        anchors.centerIn: parent
        width: Math.min(440, root.width - 40)
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        property var entries: []
        onAccepted: root.transferAction(deleteFiles.checked ? "delete" : "remove", entries)
        ColumnLayout {
            anchors.fill: parent
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: removeDialog.entries.length === 1
                    ? qsTr("Remove %1 from the download list?").arg(removeDialog.entries[0].file)
                    : qsTr("Remove %1 downloads from the list?").arg(removeDialog.entries.length)
            }
            CheckBox { id: deleteFiles; text: qsTr("Also delete the downloaded files") }
        }
    }

    Dialog {
        id: restartDialog
        property var entry: null
        title: qsTr("Redownload from the start")
        parent: root.contentItem
        anchors.centerIn: parent
        width: Math.min(458, root.width - 40)
        modal: true
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: if (entry) root.itemAction("redownload", entry)
        Label {
            width: parent.width
            wrapMode: Text.WordWrap
            text: restartDialog.entry ? qsTr("Download %1 again? Saved progress will be discarded. A finished file is replaced after the new download completes.").arg(restartDialog.entry.file) : ""
        }
    }

    Dialog {
        id: shortcutsDialog
        title: qsTr("Keyboard shortcuts")
        parent: root.contentItem
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Close
        Label {
            text: qsTr("Ctrl+N   Add URL\nCtrl+O   Add torrent\nCtrl+F   Search downloads\nCtrl+,   Open Settings\nF5          Refresh\nEnter    Show selected download\nDelete  Remove selected downloads")
            lineHeight: 1.25
        }
    }

    FileDialog {
        id: moveDialog
        title: qsTr("Move or rename download")
        fileMode: FileDialog.SaveFile
        property var entry: null
        onAccepted: {
            const fileUrl = decodeURIComponent(selectedFile.toString())
            const path = fileUrl.startsWith("file:///") ? fileUrl.slice(7).replace(/^\/(?=[A-Za-z]:\/)/, "") : fileUrl.slice(5)
            root.itemAction("move", entry, path)
        }
    }

    Menu {
        id: contextMenu
        MenuItem { action: detailsAction }
        MenuItem {
            text: qsTr("Open")
            enabled: root.currentItem !== null && root.currentItem.status === "Complete"
            onTriggered: root.openPicked(false)
        }
        MenuItem {
            text: qsTr("Open folder")
            enabled: root.currentItem !== null
            onTriggered: root.openPicked(true)
        }
        MenuItem { action: openWith }
        MenuItem { action: moveFile }
        MenuItem { action: restartFile }
        MenuSeparator {}
        MenuItem { action: resumeTransfers }
        MenuItem { action: pauseTransfers }
        Menu {
            id: queueMenu
            title: qsTr("Add to queue")
            enabled: root.currentItem !== null && root.queues.length > 0
            Instantiator {
                model: root.queues
                delegate: MenuItem {
                    required property var modelData
                    text: modelData.name
                    onTriggered: root.itemAction("queue-add", root.currentItem, modelData.name)
                }
                onObjectAdded: (index, object) => queueMenu.insertItem(index, object)
                onObjectRemoved: (index, object) => queueMenu.removeItem(object)
            }
        }
        MenuItem {
            text: qsTr("Remove from queue")
            enabled: root.currentItem !== null && root.queues.some(q => q.ids.includes(root.currentItem.id))
            onTriggered: root.itemAction("queue-remove", root.currentItem)
        }
        MenuSeparator {}
        MenuItem { action: removeSelection }
    }

    function openPicked(folder) {
        if (!currentItem || (!folder && currentItem.status !== "Complete"))
            return
        const item = currentItem
        request({query: "glass-move-status", ids: [Number(item.id)]}, false, result => {
            if (!result || result.moved_away || !result.path) {
                actionError = qsTr("The downloaded file could not be located.")
                return
            }
            const opened = folder ? engine.openFolder(String(result.path)) : engine.openPath(String(result.path))
            if (!opened)
                actionError = folder ? qsTr("The download folder could not be opened.") : qsTr("The downloaded file could not be opened.")
        })
    }

    background: WindowBackdrop { hostWindow: root; target: "main" }

    component LibraryButton: Button {
        id: libraryButton
        property string symbol: ""
        property string count: ""
        property color accent: root.colors.accent

        hoverEnabled: true
        leftPadding: 7
        rightPadding: 7
        topPadding: 3
        bottomPadding: 3
        contentItem: RowLayout {
            spacing: 7
            DashboardIcon {
                symbol: libraryButton.symbol
                ink: libraryButton.accent
                Layout.preferredWidth: 17
                Layout.preferredHeight: 17
            }
            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: libraryButton.text
                color: root.colors.ink
                font.pixelSize: 12
            }
            Label {
                visible: libraryButton.count.length > 0
                text: libraryButton.count
                color: root.colors.muted
                font.pixelSize: 11
            }
        }
        background: Loader {
            active: libraryButton.hovered || libraryButton.checked || libraryButton.visualFocus
            sourceComponent: GlassSurface {
                role: "button"
                accent: libraryButton.accent
                emphasis: libraryButton.checked ? .32 : .13
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: 5
                    color: "transparent"
                    border.width: 1
                    border.color: root.colors.ink
                    visible: libraryButton.visualFocus
                }
            }
        }
    }

    component LibraryScrollBar: ScrollBar {
        id: grip
        implicitWidth: 7
        padding: 1
        minimumSize: .08
        policy: ScrollBar.AsNeeded
        contentItem: Rectangle {
            implicitWidth: 5
            radius: width / 2
            color: root.colors.secondary
            opacity: grip.pressed ? .96 : grip.active ? .82 : .58
        }
        background: Item {}
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.layoutInset
        spacing: 7

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 43
            GlassSurface { anchors.fill: parent; role: "title" }
            MouseArea {
                objectName: "titleDragArea"
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.rightMargin: captionActions.width + 6
                z: 1
                acceptedButtons: Qt.LeftButton
                property point origin
                property bool moving: false
                onPressed: mouse => {
                    origin = Qt.point(mouse.x, mouse.y)
                    moving = false
                }
                onPositionChanged: mouse => {
                    if (pressed && !moving && Math.abs(mouse.x - origin.x) + Math.abs(mouse.y - origin.y) >= 6) {
                        moving = true
                        root.startSystemMove()
                    }
                }
                onDoubleClicked: root.toggleMaximized()
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 6
                spacing: 8
                DashboardIcon {
                    symbol: "app"
                    ink: root.colors.accent
                    Layout.preferredWidth: 23
                    Layout.preferredHeight: 23
                }
                Label {
                    Layout.fillWidth: true
                    text: root.title
                    color: root.colors.ink
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Rectangle {
                    Layout.preferredWidth: 7
                    Layout.preferredHeight: 7
                    radius: width / 2
                    color: root.online ? root.colors.positive : root.colors.caution
                }
                Label {
                    text: root.online ? qsTr("Connected") : qsTr("Offline")
                    color: root.colors.muted
                    font.pixelSize: 12
                }
                RowLayout {
                    id: captionActions
                    spacing: 4
                    Repeater {
                        model: [
                            {symbol: "minimize", label: qsTr("Minimize"), accent: root.colors.caution, click: () => root.showMinimized()},
                            {symbol: root.visibility === Window.Maximized ? "restore" : "maximize",
                             label: root.visibility === Window.Maximized ? qsTr("Restore") : qsTr("Maximize"),
                             accent: root.colors.secondary, click: () => root.toggleMaximized()},
                            {symbol: "close", label: qsTr("Close"), accent: root.colors.destructive, click: () => root.close()}
                        ]
                        delegate: GlassButton {
                            id: captionButton
                            required property var modelData
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 29
                            text: modelData.label
                            accent: modelData.accent
                            contentItem: DashboardIcon { symbol: captionButton.modelData.symbol; ink: captionButton.accent }
                            ToolTip.text: text
                            ToolTip.visible: hovered
                            onClicked: modelData.click()
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 31
            GlassSurface { anchors.fill: parent; role: "menu" }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 6
                spacing: 2
                GlassButton {
                    id: taskMenuButton
                    text: qsTr("Tasks")
                    onClicked: taskMenu.open()
                    Menu {
                        id: taskMenu
                        y: taskMenuButton.height
                        MenuItem { action: addUrl }
                        MenuItem { action: addTorrent }
                        MenuSeparator {}
                        MenuItem { text: qsTr("Download video from a page…"); enabled: root.online; onTriggered: enginePrompts.video.presentLookup() }
                        MenuItem { text: qsTr("Download a gallery…"); enabled: root.online; onTriggered: galleryDialog.present() }
                        MenuItem { text: qsTr("Batch download…"); enabled: root.online; onTriggered: batchDialog.present() }
                        MenuItem { text: qsTr("Link grabber…"); enabled: root.online; onTriggered: enginePrompts.links.present() }
                        MenuSeparator {}
                        MenuItem { text: qsTr("Hide in system tray"); enabled: Boolean(engine.trayAvailable); onTriggered: root.hide() }
                        MenuItem { text: qsTr("Exit"); onTriggered: engine.requestQuit() }
                    }
                }
                GlassButton {
                    id: fileMenuButton
                    text: qsTr("File")
                    onClicked: fileMenu.open()
                    Menu {
                        id: fileMenu
                        y: fileMenuButton.height
                        MenuItem { action: detailsAction }
                        MenuItem { text: qsTr("Open"); enabled: root.currentItem !== null && root.currentItem.status === "Complete"; onTriggered: root.openPicked(false) }
                        MenuItem { text: qsTr("Open folder"); enabled: root.currentItem !== null; onTriggered: root.openPicked(true) }
                        MenuItem { action: openWith }
                        MenuItem { action: moveFile }
                        MenuItem { action: restartFile }
                        MenuSeparator {}
                        MenuItem { action: removeSelection }
                    }
                }
                GlassButton {
                    id: downloadMenuButton
                    text: qsTr("Downloads")
                    onClicked: downloadMenu.open()
                    Menu {
                        id: downloadMenu
                        y: downloadMenuButton.height
                        MenuItem { action: resumeTransfers }
                        MenuItem { action: pauseTransfers }
                        MenuItem { action: stopAll }
                        MenuItem { action: removeCompleted }
                        MenuSeparator {}
                        MenuItem { action: startQueue }
                        MenuItem { action: stopQueue }
                        MenuItem { action: schedulerAction }
                    }
                }
                GlassButton {
                    id: viewMenuButton
                    text: qsTr("View")
                    onClicked: viewMenu.open()
                    Menu {
                        id: viewMenu
                        y: viewMenuButton.height
                        MenuItem { action: refreshAction }
                        MenuItem { action: findAction }
                        MenuItem { text: root.showSidebar ? qsTr("Hide sidebar") : qsTr("Show sidebar"); onTriggered: root.showSidebar = !root.showSidebar }
                        MenuSeparator {}
                        MenuItem { text: qsTr("Appearance"); onTriggered: settingsWindow.showCategory("Appearance") }
                    }
                }
                GlassButton {
                    id: helpMenuButton
                    text: qsTr("Help")
                    onClicked: helpMenu.open()
                    Menu {
                        id: helpMenu
                        y: helpMenuButton.height
                        MenuItem { text: qsTr("Keyboard shortcuts"); onTriggered: shortcutsDialog.open() }
                        MenuItem { text: qsTr("Browser integration"); onTriggered: settingsWindow.showCategory("Browser Integration") }
                        MenuItem { text: qsTr("Project guide"); onTriggered: Qt.openUrlExternally("https://github.com/4ls4mi/Auralis-Download-Manager#guides-and-recovery") }
                    }
                }
                Item { Layout.fillWidth: true }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 51
            GlassSurface { anchors.fill: parent; role: "toolbar" }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 7
                anchors.rightMargin: 7
                spacing: root.compact ? 4 : 7
                Repeater {
                    model: [
                        {command: addUrl, icon: "add", color: root.colors.positive},
                        {command: addTorrent, icon: "torrent", color: Qt.tint(root.colors.positive, Qt.alpha(root.colors.caution, .55))},
                        {command: resumeTransfers, icon: "start", color: root.colors.accent},
                        {command: pauseTransfers, icon: "stop", color: root.colors.caution},
                        {command: stopAll, icon: "pause", color: Qt.tint(root.colors.caution, Qt.alpha(root.colors.destructive, .30))},
                        {command: removeSelection, icon: "remove", color: root.colors.destructive},
                        {command: removeCompleted, icon: "check", color: Qt.tint(root.colors.destructive, Qt.alpha(root.colors.secondary, .35))},
                        {command: settingsAction, icon: "settings", color: root.colors.secondary},
                        {command: schedulerAction, icon: "clock", color: Qt.tint(root.colors.accent, Qt.alpha(root.colors.positive, .35))},
                        {command: startQueue, icon: "start", color: Qt.tint(root.colors.accent, Qt.alpha(root.colors.secondary, .50))},
                        {command: stopQueue, icon: "pause", color: Qt.tint(root.colors.caution, Qt.alpha(root.colors.secondary, .37))}
                    ]
                    delegate: GlassButton {
                        id: actionButton
                        required property var modelData
                        Layout.preferredWidth: root.compact ? 41 : 54
                        Layout.preferredHeight: 36
                        action: modelData.command
                        accent: modelData.color
                        contentItem: DashboardIcon {
                            symbol: actionButton.modelData.icon
                            ink: actionButton.accent
                        }
                        ToolTip.visible: hovered
                        ToolTip.text: text
                        ToolTip.delay: 420
                    }
                }
                Item { Layout.fillWidth: true }
            }
        }

        Frame {
            visible: root.recoveryNotice !== null
            Layout.fillWidth: true
            padding: 6
            background: GlassSurface { role: "card" }
            RowLayout {
                anchors.fill: parent
                Label {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 80
                    elide: Text.ElideRight
                    color: root.colors.ink
                    text: !root.recoveryNotice ? "" : (root.visualById[root.recoveryNotice.id].recovery_stage === "handed-off"
                        ? qsTr("Downloading via BitTorrent · %1").arg(root.recoveryNotice.file)
                        : qsTr("Torrent match found · %1").arg(root.recoveryNotice.file))
                }
                GlassButton {
                    text: qsTr("View details")
                    accent: root.colors.accent
                    onClicked: if (root.recoveryNotice) root.showDownload(root.recoveryNotice.id)
                }
                GlassButton {
                    text: qsTr("Dismiss")
                    onClicked: {
                        const item = root.recoveryNotice
                        if (item)
                            root.recoveryDismissed = Object.assign({}, root.recoveryDismissed, {[item.id]: root.visualById[item.id].recovery_stage})
                    }
                }
            }
        }

        RowLayout {
            Layout.fillHeight: true
            Layout.minimumHeight: 155
            Layout.fillWidth: true
            spacing: 7

            Frame {
                visible: root.showSidebar
                Layout.preferredWidth: root.compact ? 151 : 184
                Layout.fillHeight: true
                padding: 6
                background: GlassSurface { role: "sidebar" }
                ScrollView {
                    id: libraryScroll
                    anchors.fill: parent
                    clip: true
                    contentWidth: availableWidth
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ScrollBar.vertical: LibraryScrollBar {}
                    Column {
                        width: libraryScroll.availableWidth
                        spacing: 3
                        Repeater {
                            model: root.statusFilters
                            delegate: LibraryButton {
                                required property var modelData
                                width: parent.width
                                height: 34
                                text: modelData.label
                                symbol: modelData.icon
                                count: String(root.counts[modelData.key])
                                checked: root.filterType === "status" && root.filterKey === modelData.key
                                accent: checked ? root.colors.caution : root.colors.accent
                                onClicked: root.chooseFilter("status", modelData.key)
                            }
                        }
                        Label {
                            text: qsTr("Categories")
                            color: root.colors.muted
                            leftPadding: 8
                            topPadding: 9
                            bottomPadding: 4
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Repeater {
                            model: root.categories.filter(category => category.key !== "General")
                            delegate: LibraryButton {
                                required property var modelData
                                width: parent.width
                                height: 29
                                text: modelData.name
                                symbol: "folder"
                                checked: root.filterType === "category" && root.filterKey === modelData.key
                                accent: root.colors.secondary
                                onClicked: root.chooseFilter("category", modelData.key)
                            }
                        }
                        Label {
                            visible: root.queues.length > 0
                            text: qsTr("Queues")
                            color: root.colors.muted
                            leftPadding: 8
                            topPadding: 9
                            bottomPadding: 4
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Repeater {
                            model: root.queues
                            delegate: LibraryButton {
                                required property var modelData
                                width: parent.width
                                height: 29
                                text: modelData.name
                                symbol: "queue"
                                count: String(modelData.ids.length)
                                checked: root.filterType === "queue" && root.filterKey === modelData.name
                                accent: modelData.running ? root.colors.positive : root.colors.caution
                                onClicked: root.chooseFilter("queue", modelData.name)
                            }
                        }
                    }
                }
            }

            Frame {
                Layout.fillHeight: true
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                padding: 9
                background: GlassSurface { role: "content" }
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 5
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Label {
                                Layout.fillWidth: true
                                text: root.filterTitle
                                color: root.colors.ink
                                font.pixelSize: root.compact ? 17 : 22
                                font.weight: Font.Bold
                                elide: Text.ElideRight
                            }
                            Label {
                                Layout.fillWidth: true
                                text: qsTr("%1 of %2 downloads").arg(rows.count).arg(root.downloads.length)
                                color: root.colors.muted
                                font.pixelSize: 11
                            }
                        }
                        ComboBox {
                            id: sortSelector
                            Layout.preferredWidth: root.compact ? 115 : 132
                            model: [qsTr("Newest first"), qsTr("Oldest first"), qsTr("Name"), qsTr("Size"), qsTr("Status")]
                            currentIndex: root.sortOrder
                            onActivated: index => root.sortOrder = index
                            Accessible.name: qsTr("Sort downloads")
                        }
                        TextField {
                            id: searchField
                            objectName: "downloadSearch"
                            Layout.preferredWidth: root.compact ? 133 : 206
                            placeholderText: qsTr("Search downloads…")
                            color: root.colors.ink
                            placeholderTextColor: root.colors.muted
                            leftPadding: 10
                            selectByMouse: true
                            onTextChanged: root.searchTerm = text
                            Keys.onEscapePressed: clear()
                            background: GlassSurface { role: "field" }
                            Accessible.name: qsTr("Search downloads")
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.chosenItems.length > 1
                        Label {
                            text: qsTr("%1 selected").arg(root.chosenItems.length)
                            color: root.colors.ink
                        }
                        GlassButton { action: resumeTransfers; accent: root.colors.positive }
                        GlassButton { action: pauseTransfers; accent: root.colors.caution }
                        GlassButton { action: removeSelection; accent: root.colors.destructive }
                        GlassButton { text: qsTr("Clear"); onClicked: { root.chosenIds = []; root.selectionAnchor = "" } }
                        Item { Layout.fillWidth: true }
                    }
                    Item {
                        Layout.preferredHeight: 30
                        Layout.fillWidth: true
                        GlassSurface { anchors.fill: parent; role: "field" }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 11
                            anchors.rightMargin: 11
                            spacing: 11
                            Label { Layout.fillWidth: true; Layout.minimumWidth: 117; text: qsTr("File name"); color: root.colors.muted; font.weight: Font.DemiBold }
                            Label { Layout.preferredWidth: root.compact ? 74 : 92; text: qsTr("Status"); color: root.colors.muted; font.weight: Font.DemiBold }
                            Label { Layout.preferredWidth: root.compact ? 117 : 158; text: qsTr("Progress"); color: root.colors.muted; font.weight: Font.DemiBold }
                            Label { Layout.preferredWidth: root.compact ? 62 : 83; horizontalAlignment: Text.AlignRight; text: qsTr("Speed"); color: root.colors.muted; font.weight: Font.DemiBold }
                            Label { Layout.preferredWidth: root.compact ? 58 : 71; horizontalAlignment: Text.AlignRight; text: qsTr("Time left"); color: root.colors.muted; font.weight: Font.DemiBold }
                        }
                    }
                    ListView {
                        id: list
                        objectName: "downloadList"
                        Layout.fillHeight: true
                        Layout.fillWidth: true
                        clip: true
                        spacing: 2
                        model: rows
                        currentIndex: -1
                        focus: true
                        keyNavigationEnabled: false
                        reuseItems: true
                        Accessible.role: Accessible.List
                        Accessible.name: qsTr("Downloads list")
                        ScrollBar.vertical: LibraryScrollBar {}
                        delegate: DashboardRow {
                            id: downloadRow
                            required property int index
                            required property string transferId
                            required property string file
                            required property string status
                            required property real bytes
                            required property real length
                            required property real transferSpeed
                            readonly property var visual: root.visualById[transferId] || ({})
                            width: ListView.view.width - (list.contentHeight > list.height ? 8 : 0)
                            height: implicitHeight
                            colors: root.colors
                            compact: root.compact
                            fileName: file
                            sizeLabel: TransferData.bytes(bytes) + (length >= 0 ? " / " + TransferData.bytes(length) : "")
                            statusLabel: root.statusText(status)
                            statusInk: root.statusColor(status)
                            speedLabel: status === "Downloading" ? TransferData.rate(transferSpeed) : "—"
                            timeLabel: TransferData.timeLeft({status: status, size: length, downloaded: bytes, speed: transferSpeed})
                            progress: length > 0 ? Math.min(1, bytes / length) : status === "Complete" ? 1 : 0
                            activeTransfer: status === "Downloading"
                            torrent: visual.is_torrent === true
                            mixed: visual.direct_recovery === true
                            chosen: root.chosenIds.includes(transferId)
                            recoveryLabel: root.recoveryLabels[visual.recovery_stage] || ""
                            onSelected: modifiers => root.selectRow(index, modifiers)
                            onOpened: root.showDownload(transferId)
                            onOptionsRequested: {
                                if (!root.chosenIds.includes(transferId))
                                    root.selectRow(index, Qt.NoModifier)
                                contextMenu.popup()
                            }
                        }
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                                const direction = event.key === Qt.Key_Up ? -1 : 1
                                const next = Math.min(rows.count - 1, Math.max(0, currentIndex + direction))
                                root.selectRow(next, event.modifiers)
                                if (next >= 0)
                                    positionViewAtIndex(next, ListView.Contain)
                                event.accepted = true
                            } else if (event.matches(StandardKey.SelectAll)) {
                                root.selectEveryRow()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Delete && removeSelection.enabled) {
                                root.confirmRemoval(root.chosenItems, (event.modifiers & Qt.ShiftModifier) !== 0)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (root.currentItem)
                                    root.showDownload(root.currentItem.id)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Menu && root.currentItem) {
                                contextMenu.popup()
                                event.accepted = true
                            } else if (event.key === Qt.Key_Escape) {
                                root.chosenIds = []
                                root.selectionAnchor = ""
                                event.accepted = true
                            }
                        }
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            visible: rows.count === 0
                            DashboardIcon { symbol: "folder"; ink: root.colors.muted; Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: 31; Layout.preferredHeight: 31 }
                            Label {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.online ? qsTr("No downloads in this view") : qsTr("Connecting to Auralis…")
                                color: root.colors.ink
                                font.weight: Font.DemiBold
                            }
                            GlassButton {
                                Layout.alignment: Qt.AlignHCenter
                                visible: root.online && root.downloads.length === 0
                                action: addUrl
                                accent: root.colors.positive
                            }
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 55
            GlassSurface { anchors.fill: parent; role: "footer" }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 11
                anchors.rightMargin: 9
                spacing: 13
                Repeater {
                    model: [
                        {title: qsTr("Total speed"), value: TransferData.rate(engine.dashboard.speed || 0)},
                        {title: qsTr("Active"), value: String(root.counts.downloading)},
                        {title: qsTr("Completed"), value: String(root.counts.finished)}
                    ]
                    delegate: ColumnLayout {
                        required property var modelData
                        spacing: 2
                        Label { text: modelData.title; color: root.colors.muted; font.pixelSize: 11 }
                        Label { text: modelData.value; color: root.colors.ink; font.weight: Font.DemiBold }
                    }
                }
                TransferGraph {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 85
                    Layout.preferredHeight: 35
                    samples: root.graphValues
                    lineColor: root.colors.accent
                    endpointColor: root.colors.secondary
                    gridColor: root.colors.divider
                    Accessible.name: qsTr("Recent total transfer speed")
                }
                Label {
                    Layout.preferredWidth: Math.min(240, Math.ceil(implicitWidth))
                    text: root.actionError || (root.online ? qsTr("Auralis %1").arg(engine.version) : engine.status || qsTr("Offline"))
                    color: root.actionError ? root.colors.destructive : root.colors.muted
                    elide: Text.ElideRight
                    font.pixelSize: 11
                    ToolTip.visible: statusHover.hovered && text.length > 20
                    ToolTip.text: text
                    HoverHandler { id: statusHover }
                }
            }
        }
    }

    Repeater {
        model: [
            {edges: Qt.TopEdge, horizontal: true, trailing: false},
            {edges: Qt.BottomEdge, horizontal: true, trailing: true},
            {edges: Qt.LeftEdge, horizontal: false, trailing: false},
            {edges: Qt.RightEdge, horizontal: false, trailing: true}
        ]
        delegate: MouseArea {
            required property var modelData
            z: 5
            visible: root.visibility !== Window.Maximized
            width: modelData.horizontal ? root.width - 10 : 5
            height: modelData.horizontal ? 5 : root.height - 10
            x: modelData.horizontal ? 5 : modelData.trailing ? root.width - width : 0
            y: modelData.horizontal ? modelData.trailing ? root.height - height : 0 : 5
            cursorShape: modelData.horizontal ? Qt.SizeVerCursor : Qt.SizeHorCursor
            onPressed: root.startSystemResize(modelData.edges)
        }
    }
    Repeater {
        model: [
            {edges: Qt.TopEdge | Qt.LeftEdge, right: false, bottom: false, cursor: Qt.SizeFDiagCursor},
            {edges: Qt.TopEdge | Qt.RightEdge, right: true, bottom: false, cursor: Qt.SizeBDiagCursor},
            {edges: Qt.BottomEdge | Qt.LeftEdge, right: false, bottom: true, cursor: Qt.SizeBDiagCursor},
            {edges: Qt.BottomEdge | Qt.RightEdge, right: true, bottom: true, cursor: Qt.SizeFDiagCursor}
        ]
        delegate: MouseArea {
            required property var modelData
            z: 6
            visible: root.visibility !== Window.Maximized
            width: 7
            height: 7
            x: modelData.right ? root.width - width : 0
            y: modelData.bottom ? root.height - height : 0
            cursorShape: modelData.cursor
            onPressed: root.startSystemResize(modelData.edges)
        }
    }
}
