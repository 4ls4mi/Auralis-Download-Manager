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
    visible: !engine.startHidden || !engine.trayAvailable
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
    property string focusedTransferId: ""
    readonly property var chosenItems: {
        return downloads.filter(item => chosenSet.has(String(item.id)))
    }
    readonly property var currentItem: chosenItems.find(item => String(item.id) === focusedTransferId) || chosenItems[0] || null
    readonly property var chosenSet: new Set(chosenIds)
    readonly property int indicatorColumnWidth: compact ? 207 : 330
    readonly property int timeColumnWidth: compact ? 57 : 72
    readonly property int listGutter: list.contentHeight > list.height ? 8 : 0
    property var detailWindows: ({})
    property var hiddenProgressIds: []
    readonly property bool minimizeToTray: enginePrompts.settings.minimize_to_tray !== false
    readonly property bool closeToTray: enginePrompts.settings.close_to_tray !== false
    readonly property bool progressMinimizeToTray: enginePrompts.settings.progress_minimize_to_tray === undefined
        ? minimizeToTray : enginePrompts.settings.progress_minimize_to_tray !== false
    readonly property var hiddenProgressItems: {
        const entries = []
        for (const item of downloads) {
            if (!hiddenProgressIds.includes(String(item.id)) || item.status === "Complete")
                continue
            const visual = visualById[item.id] || {}
            const percentage = item.size > 0 ? (100 * TransferData.fraction(item)).toFixed(1) + "%" : qsTr("Size unknown")
            const summary = item.status === "Downloading"
                ? qsTr("%1 · %2 · %3").arg(percentage).arg(TransferData.rate(item.speed)).arg(TransferData.timeLeft(item))
                : qsTr("%1 · %2").arg(statusText(item.status)).arg(percentage)
            const transport = visual.torrent ? qsTr("%1 peers").arg(visual.torrent.peers)
                : visual.active_connections === undefined ? "" : qsTr("%1 connections").arg(visual.active_connections)
            const resume = visual.resumable === true ? qsTr("Can resume")
                : visual.resumable === false ? qsTr("Resume unavailable") : ""
            const details = [summary, transport, resume].filter(Boolean).join(" · ")
            entries.push({id: item.id, name: item.file, summary: summary, details: details})
        }
        return entries
    }

    onHiddenProgressItemsChanged: {
        if (engine.trayAvailable)
            engine.setProgressTrayItems(hiddenProgressItems)
    }

    property var graphValues: []
    property var transferSpeedHistory: ({})
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
        const remaining = chosenIds.filter(id => visibleIds.has(id))
        if (remaining.length !== chosenIds.length)
            chosenIds = remaining
        if (!visibleIds.has(selectionAnchor))
            selectionAnchor = ""
        if (!visibleIds.has(focusedTransferId))
            focusedTransferId = ""
        list.currentIndex = rowIndex(focusedTransferId)
        for (const id in detailWindows) {
            if (!existing.has(id)) {
                detailWindows[id].destroy()
                delete detailWindows[id]
                forgetHiddenProgress(id)
            }
        }
    }

    function chooseFilter(type, key) {
        filterType = type
        filterKey = key
        clearSelection()
        focusedTransferId = ""
        synchronizeRows()
        list.positionViewAtBeginning()
    }

    function rowIndex(id) {
        if (id) {
            for (let index = 0; index < rows.count; ++index) {
                if (rows.get(index).transferId === id)
                    return index
            }
        }
        return -1
    }

    function focusRow(index) {
        focusedTransferId = rows.get(index).transferId
        list.currentIndex = index
        list.forceActiveFocus()
    }

    function selectRow(index, modifiers) {
        if (index < 0 || index >= rows.count)
            return
        const previousFocus = focusedTransferId
        focusRow(index)
        const key = focusedTransferId
        const extend = (modifiers & Qt.ControlModifier) !== 0
        if (modifiers & Qt.ShiftModifier) {
            const start = rowIndex(selectionAnchor || previousFocus)
            if (start >= 0) {
                if (!selectionAnchor)
                    selectionAnchor = rows.get(start).transferId
                const range = []
                for (let i = Math.min(start, index); i <= Math.max(start, index); ++i)
                    range.push(rows.get(i).transferId)
                chosenIds = extend ? Array.from(new Set(chosenIds.concat(range))) : range
                return
            }
        }
        chosenIds = extend ? (chosenSet.has(key) ? chosenIds.filter(id => id !== key) : chosenIds.concat(key)) : [key]
        selectionAnchor = key
    }

    function clearSelection() {
        chosenIds = []
        selectionAnchor = ""
    }

    function selectEveryRow() {
        const ids = []
        for (let index = 0; index < rows.count; ++index)
            ids.push(rows.get(index).transferId)
        chosenIds = ids
        if (ids.length) {
            focusRow(Math.max(0, list.currentIndex))
            selectionAnchor = focusedTransferId
        }
    }

    function recordTransferSpeeds() {
        const histories = {}
        for (const item of downloads) {
            const id = String(item.id)
            const previous = transferSpeedHistory[id]
            if (item.status === "Downloading")
                histories[id] = (previous || []).slice(-29).concat([Math.max(0, Number(item.speed) || 0)])
            else if (previous)
                histories[id] = previous
        }
        transferSpeedHistory = histories
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
        removeDialog.runningCount = items.length - eligibleItems.length
        removeDialog.optionChecked = alsoDelete
        removeDialog.open()
    }

    function removeDownloads(items, alsoDelete) {
        const ids = items.map(item => Number(item.id))
        if (!ids.length)
            return
        request({action: alsoDelete ? "delete" : "remove", ids: ids}, true, response => {
            if (!response || !response.done || !response.done.length)
                return
            const removed = new Set(response.done.map(String))
            chosenIds = chosenIds.filter(id => !removed.has(id))
            if (removed.has(selectionAnchor))
                selectionAnchor = ""
        })
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
        if (settingsWindow.visibility === Window.Minimized)
            settingsWindow.showNormal()
        else
            settingsWindow.show()
        settingsWindow.raise()
        settingsWindow.requestActivate()
    }

    function showBrowserSettings() {
        settingsWindow.showCategory("Browser Integration")
    }

    function hideMainToTray() {
        if (engine.trayAvailable)
            hide()
        else
            showMinimized()
    }

    function minimizeMain() {
        if (minimizeToTray && engine.trayAvailable)
            hideMainToTray()
        else
            showMinimized()
    }

    function hideProgressToTray(id) {
        const key = String(id)
        const details = detailWindows[key]
        if (!details)
            return
        if (!engine.trayAvailable) {
            details.showMinimized()
            return
        }
        if (!hiddenProgressIds.includes(key))
            hiddenProgressIds = hiddenProgressIds.concat([key])
        details.hide()
    }

    function forgetHiddenProgress(id) {
        const key = String(id)
        if (hiddenProgressIds.includes(key))
            hiddenProgressIds = hiddenProgressIds.filter(hidden => hidden !== key)
    }

    function showDownload(id) {
        const key = String(id)
        const wasHidden = hiddenProgressIds.includes(key)
        let details = detailWindows[key]
        if (!details) {
            details = detailsFactory.createObject(root, {downloadId: Number(id)})
            if (!details) {
                actionError = qsTr("The download window could not open.")
                return
            }
            detailWindows[key] = details
        }
        forgetHiddenProgress(id)
        if (wasHidden || details.visibility === Window.Minimized)
            details.showNormal()
        else
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
        event.accepted = false
        if (closeToTray)
            hideMainToTray()
        else
            engine.requestQuit()
    }
    onVisibilityChanged: {
        if (root.visibility === Window.Minimized && root.minimizeToTray && engine.trayAvailable) {
            Qt.callLater(() => {
                if (root.visibility === Window.Minimized)
                    root.hideMainToTray()
            })
        }
    }
    onSearchTermChanged: synchronizeRows()
    onSortOrderChanged: synchronizeRows()
    Component.onCompleted: {
        synchronizeRows()
        engine.refresh()
        if (engine.startHidden && !engine.trayAvailable)
            showMinimized()
    }

    Connections {
        target: engine
        function onOperationFailed(message) {
            root.actionError = message
        }
        function onDashboardChanged() {
            root.graphValues = root.graphValues.slice(-64).concat([Number(engine.dashboard.speed || 0)])
            root.recordTransferSpeeds()
            if (root.filterType === "queue" && !root.currentQueue)
                root.chooseFilter("status", "all")
            else if (root.filterType === "category" && !root.categories.some(c => c.key === root.filterKey))
                root.chooseFilter("status", "all")
            else
                root.synchronizeRows()
        }
    }

    ListModel { id: rows }
    function showUpdates() {
        settingsWindow.showUpdate(settingsWindow.availableUpdate)
    }

    SettingsWindow {
        id: settingsWindow
        objectName: "settingsWindow"
        transientParent: null
        onConfigChanged: if (config) enginePrompts.settings = config
    }
    UpdateNotice {
        id: updateNotice
        backend: engine
        anchorWindow: root
        automaticChecks: settingsWindow.automaticUpdateChecks
        presentation: settingsWindow.updatePresentation
        onAvailableUpdateChanged: settingsWindow.availableUpdate = updateNotice.availableUpdate
        onDetailsRequested: update => settingsWindow.showUpdate(update)
    }
    AddDownloadDialog { id: addDialog; hostWindow: root }
    Component {
        id: detailsFactory
        DownloadWindow {
            trayEnabled: Boolean(engine.trayAvailable)
            minimizeToTray: root.progressMinimizeToTray
            onHideToTrayRequested: id => root.hideProgressToTray(id)
        }
    }
    GalleryDownloadDialog {
        id: galleryDialog
        parent: root.contentItem
        onHelpersRequested: settingsWindow.showCategory("Advanced")
    }
    BatchDownloadDialog { id: batchDialog; parent: root.contentItem }
    EnginePrompts {
        id: enginePrompts
        popupParent: root.contentItem
        onShowProgressRequested: downloadId => {
            if (!root.hiddenProgressIds.includes(String(downloadId)))
                root.showDownload(downloadId)
        }
        onDownloadCompleted: downloadId => root.forgetHiddenProgress(downloadId)
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

    DetachedConfirmation {
        id: removeDialog
        hostWindow: root
        title: qsTr("Remove downloads")
        property var entries: []
        property int runningCount: 0
        message: (entries.length === 1
            ? qsTr("Remove %1 from the download list?").arg(entries[0].file)
            : qsTr("Remove %1 downloads from the list?").arg(entries.length))
            + (runningCount === 0 ? "" : "\n\n" + (runningCount === 1
                ? qsTr("Pause the running download before removing it.")
                : qsTr("Pause %1 running downloads before removing them.").arg(runningCount)))
        showOption: true
        optionText: qsTr("Also delete the downloaded files")
        confirmText: optionChecked ? qsTr("Delete files") : qsTr("Remove")
        destructive: optionChecked
        onConfirmed: root.removeDownloads(entries, optionChecked)
    }

    DetachedConfirmation {
        id: restartDialog
        hostWindow: root
        property var entry: null
        title: qsTr("Redownload from the start")
        message: entry ? qsTr("Download %1 again? Saved progress will be discarded. A finished file is replaced after the new download completes.").arg(entry.file) : ""
        confirmText: qsTr("Redownload")
        destructive: true
        onConfirmed: if (entry) root.itemAction("redownload", entry)
    }

    DetachedDialogWindow {
        id: shortcutsDialog
        objectName: "shortcutsWindow"
        hostWindow: root
        width: 455
        title: qsTr("Keyboard shortcuts")
        onDismissRequested: hide()
        onOpened: closeShortcuts.forceActiveFocus()

        bodyContent: [
            Repeater {
                model: [
                    {key: qsTr("Ctrl+N"), label: qsTr("Add URL")},
                    {key: qsTr("Ctrl+O"), label: qsTr("Add torrent")},
                    {key: qsTr("Ctrl+F"), label: qsTr("Search downloads")},
                    {key: qsTr("Ctrl+,"), label: qsTr("Open Settings")},
                    {key: qsTr("F5"), label: qsTr("Refresh downloads")},
                    {key: qsTr("Enter"), label: qsTr("Show selected download")},
                    {key: qsTr("Ctrl+A"), label: qsTr("Select all downloads in this view")},
                    {key: qsTr("Delete"), label: qsTr("Remove selected downloads")},
                    {key: qsTr("Shift+Delete"), label: qsTr("Remove selected downloads and their files")},
                    {key: qsTr("Ctrl+M"), label: qsTr("Move or rename the selected download")}
                ]

                delegate: RowLayout {
                    id: shortcutRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 12

                    Label {
                        Layout.preferredWidth: 118
                        leftPadding: 8
                        rightPadding: 8
                        topPadding: 4
                        bottomPadding: 4
                        text: shortcutRow.modelData.key
                        color: shortcutsDialog.colors.ink
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                        background: GlassSurface { material: shortcutsDialog.material; role: "field" }
                    }
                    Label {
                        Layout.fillWidth: true
                        text: shortcutRow.modelData.label
                        wrapMode: Text.WordWrap
                        color: shortcutsDialog.colors.ink
                    }
                }
            }
        ]

        footer: Item {
            implicitHeight: closeShortcuts.implicitHeight + 20
            GlassSurface { anchors.fill: parent; material: shortcutsDialog.material; role: "footer" }
            GlassButton {
                id: closeShortcuts
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 10
                material: shortcutsDialog.material
                text: qsTr("Close")
                onClicked: shortcutsDialog.hide()
            }
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
            CaptionMoveArea {
                objectName: "titleDragArea"
                hostWindow: root
                anchors.fill: parent
                anchors.rightMargin: captionActions.width + 6
                z: 1
                onDoubleClickRequested: root.toggleMaximized()
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
                CaptionControls {
                    id: captionActions
                    trayEnabled: Boolean(engine.trayAvailable)
                    maximized: root.visibility === Window.Maximized
                    minimizeLabel: root.minimizeToTray && engine.trayAvailable ? qsTr("Minimize to system tray") : qsTr("Minimize")
                    closeLabel: root.closeToTray ? qsTr("Keep Auralis running") : qsTr("Exit Auralis")
                    onHideRequested: root.hideMainToTray()
                    onMinimizeRequested: root.minimizeMain()
                    onMaximizeRequested: root.toggleMaximized()
                    onCloseRequested: root.close()
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
                        MenuItem { text: qsTr("Hide in system tray"); enabled: Boolean(engine.trayAvailable); onTriggered: root.hideMainToTray() }
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
                        MenuItem { text: qsTr("Check for updates"); onTriggered: root.showUpdates() }
                        MenuItem { text: qsTr("Project guide"); onTriggered: Qt.openUrlExternally("https://github.com/4ls4mi/Auralis-Download-Manager#guides-and-recovery") }
                    }
                }
                Item { Layout.fillWidth: true }
                GlassButton {
                    visible: Boolean(settingsWindow.availableUpdate)
                    text: qsTr("Update available")
                    Accessible.description: settingsWindow.availableUpdate
                        ? qsTr("Auralis %1").arg(settingsWindow.availableUpdate.version) : ""
                    onClicked: root.showUpdates()
                }
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
                        {command: addUrl, icon: "add"},
                        {command: addTorrent, icon: "torrent"},
                        {command: resumeTransfers, icon: "start"},
                        {command: pauseTransfers, icon: "pause"},
                        {command: stopAll, icon: "stop"},
                        {command: removeSelection, icon: "remove"},
                        {command: removeCompleted, icon: "check"},
                        {command: settingsAction, icon: "settings"},
                        {command: schedulerAction, icon: "clock"},
                        {command: startQueue, icon: "start", accentKey: "queueStart"},
                        {command: stopQueue, icon: "pause", accentKey: "queueStop"}
                    ]
                    delegate: GlassButton {
                        id: actionButton
                        required property var modelData
                        Layout.preferredWidth: root.compact ? 41 : 54
                        Layout.preferredHeight: 36
                        action: modelData.command
                        accent: MaterialTheme.actionColor(modelData.accentKey || modelData.icon, root.colors.light)
                        contentItem: DashboardIcon {
                            symbol: actionButton.modelData.icon
                            bold: true
                            solid: symbol === "start" || symbol === "stop"
                            ink: actionButton.displayAccent
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
                        GlassComboBox {
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
                        visible: root.chosenIds.length > 0
                        Label {
                            text: qsTr("%1 selected").arg(root.chosenItems.length)
                            color: root.colors.ink
                        }
                        GlassButton { action: resumeTransfers; accent: root.colors.positive }
                        GlassButton { action: pauseTransfers; accent: root.colors.caution }
                        GlassButton { action: removeSelection; accent: root.colors.destructive }
                        GlassButton { text: qsTr("Clear"); onClicked: root.clearSelection() }
                        Item { Layout.fillWidth: true }
                    }
                    Item {
                        Layout.preferredHeight: 30
                        Layout.fillWidth: true
                        GlassSurface { anchors.fill: parent; role: "field" }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 11
                            anchors.rightMargin: 11 + root.listGutter
                            spacing: 9
                            CheckBox {
                                objectName: "selectVisibleDownloads"
                                focusPolicy: Qt.TabFocus
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 26
                                padding: 2
                                enabled: rows.count > 0
                                tristate: true
                                checkState: root.chosenIds.length === 0 ? Qt.Unchecked
                                    : root.chosenIds.length === rows.count ? Qt.Checked : Qt.PartiallyChecked
                                nextCheckState: function () { return checkState === Qt.Checked ? Qt.Unchecked : Qt.Checked }
                                onClicked: checkState === Qt.Checked ? root.selectEveryRow() : root.clearSelection()
                                Accessible.name: qsTr("Select all visible downloads")
                                ToolTip.visible: hovered
                                ToolTip.delay: 650
                                ToolTip.text: Accessible.name
                            }
                            Item { Layout.preferredWidth: 21 }
                            Label { Layout.fillWidth: true; Layout.minimumWidth: 85; text: qsTr("File name"); color: root.colors.muted; font.weight: Font.DemiBold }
                            RowLayout {
                                Layout.preferredWidth: root.indicatorColumnWidth
                                spacing: 7
                                Label {
                                    Layout.preferredWidth: Math.floor(root.indicatorColumnWidth * .49)
                                    text: qsTr("Progress")
                                    color: root.colors.muted
                                    font.weight: Font.DemiBold
                                }
                                Label {
                                    Layout.preferredWidth: Math.floor(root.indicatorColumnWidth * .24)
                                    text: root.compact ? qsTr("Links") : qsTr("Connections")
                                    elide: Text.ElideRight
                                    color: root.colors.muted
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: qsTr("Activity")
                                    elide: Text.ElideRight
                                    color: root.colors.muted
                                }
                            }
                            Label { Layout.preferredWidth: root.timeColumnWidth; horizontalAlignment: Text.AlignRight; text: qsTr("Time left"); color: root.colors.muted; font.weight: Font.DemiBold }
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
                            width: ListView.view.width - root.listGutter
                            height: implicitHeight
                            colors: root.colors
                            indicatorWidth: root.indicatorColumnWidth
                            timeWidth: root.timeColumnWidth
                            fileName: file
                            sizeLabel: TransferData.bytes(bytes) + (length >= 0 ? " / " + TransferData.bytes(length) : "")
                            statusLabel: root.statusText(status)
                            statusInk: root.statusColor(status)
                            transferring: status === "Downloading"
                            speedLabel: transferring ? TransferData.rate(transferSpeed) : ""
                            timeLabel: TransferData.timeLeft({status: status, size: length, downloaded: bytes, speed: transferSpeed})
                            progress: status === "Complete" ? 1 : length > 0 ? Math.max(0, Math.min(1, bytes / length)) : 0
                            torrent: visual.is_torrent === true
                            mixed: visual.direct_recovery === true
                            chosen: root.chosenSet.has(transferId)
                            cursorFocused: list.activeFocus && root.focusedTransferId === transferId
                            recoveryLabel: root.recoveryLabels[visual.recovery_stage] || ""
                            telemetry: visual
                            speedSamples: root.transferSpeedHistory[transferId] || []
                            onSelected: modifiers => root.selectRow(index, modifiers)
                            onOpened: root.showDownload(transferId)
                            onOptionsRequested: {
                                if (root.chosenSet.has(transferId))
                                    root.focusRow(index)
                                else
                                    root.selectRow(index, Qt.NoModifier)
                                contextMenu.popup()
                            }
                        }
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                                const direction = event.key === Qt.Key_Up ? -1 : 1
                                const next = Math.min(rows.count - 1, Math.max(0, currentIndex + direction))
                                if (next >= 0) {
                                    if ((event.modifiers & Qt.ControlModifier) && !(event.modifiers & Qt.ShiftModifier))
                                        root.focusRow(next)
                                    else
                                        root.selectRow(next, event.modifiers)
                                    positionViewAtIndex(next, ListView.Contain)
                                }
                                event.accepted = true
                            } else if (event.key === Qt.Key_Space && currentIndex >= 0) {
                                root.selectRow(currentIndex, Qt.ControlModifier | event.modifiers)
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
                                root.clearSelection()
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
                    lineColor: MaterialTheme.graphColors[0]
                    endpointColor: MaterialTheme.graphColors[1]
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
