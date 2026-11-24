import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Window
import QtCore
import "TransferData.js" as TransferData

AuralisWindow {
    id: root
    objectName: "mainWindow"
    title: qsTr("Auralis Download Manager")
    width: windowPreferences.fullWidth
    height: windowPreferences.fullHeight
    minimumWidth: compactView ? 500 : 680
    minimumHeight: compactView ? 320 : 450
    visible: !engine.startHidden || !engine.trayAvailable
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint

    readonly property var colors: MaterialTheme.palette
    readonly property bool studioChrome: colors.cleanStudio === true
    readonly property string materialLayout: colors.layout || ""
    readonly property bool violetRail: materialLayout === "violetRail"
    readonly property bool fogSlate: materialLayout === "fogSlate"
    readonly property bool coralSlate: materialLayout === "coralSlate"
    readonly property bool materialDashboard: fogSlate || violetRail || coralSlate
    readonly property bool compactView: windowPreferences.compactView
    readonly property bool sideMenus: materialDashboard && showSidebar && !compactView
    readonly property bool groupedQueue: !compactView && violetRail && filterType === "status" && filterKey === "all"
    readonly property color sidebarInk: colors.sidebarInk || colors.ink
    readonly property color sidebarMuted: colors.sidebarMuted || colors.muted
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
    readonly property var browserDownloadNotice: engine.visuals.browserDownload || null
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
    readonly property int layoutInset: visibility === Window.Maximized ? 0 : compactView ? 5 : 8
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
    readonly property var downloadSortLabels: [qsTr("Newest first"), qsTr("Oldest first"), qsTr("Name"), qsTr("Size"), qsTr("Status")]
    property bool showSidebar: true
    property var chosenIds: []
    property string selectionAnchor: ""
    property string focusedTransferId: ""
    readonly property var chosenItems: {
        return downloads.filter(item => chosenSet.has(String(item.id)))
    }
    readonly property var currentItem: chosenItems.find(item => String(item.id) === focusedTransferId) || chosenItems[0] || null
    readonly property var currentVisual: currentItem ? visualById[currentItem.id] || ({}) : ({})
    readonly property var chosenSet: new Set(chosenIds)
    readonly property int indicatorColumnWidth: compactView ? 174 : violetRail && width < 740 ? 183 : compact ? 207 : 330
    readonly property int timeColumnWidth: compactView ? 51 : compact ? 57 : 72
    readonly property int listGutter: list.contentHeight > list.height ? 8 : 0
    property var detailWindows: ({})
    property var hiddenProgressIds: []
    readonly property bool minimizeToTray: enginePrompts.settings.minimize_to_tray !== false
    readonly property bool closeToTray: enginePrompts.settings.close_to_tray !== false
    readonly property bool progressMinimizeToTray: enginePrompts.settings.progress_minimize_to_tray === undefined
        ? minimizeToTray : enginePrompts.settings.progress_minimize_to_tray !== false
    readonly property bool traySpeedLimiterKnown: typeof enginePrompts.settings.speed_limit_on === "boolean"
    readonly property bool traySpeedLimiterOn: enginePrompts.settings.speed_limit_on === true
    readonly property var trayDownloadItems: {
        const hiddenIds = new Set(hiddenProgressIds)
        const entries = []
        for (const item of downloads) {
            const hidden = hiddenIds.has(String(item.id))
            if (item.status === "Complete" || (!hidden && item.status !== "Downloading"))
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
            entries.push({id: item.id, name: item.file, summary: summary, details: details, hidden: hidden})
        }
        return entries
    }

    onTrayDownloadItemsChanged: {
        if (engine.trayAvailable)
            engine.setTrayDownloadItems(trayDownloadItems)
    }

    property var graphValues: []
    readonly property bool animateThroughput: root.visible && root.visibility !== Window.Minimized
        && root.online && Number(engine.dashboard.speed || 0) > 0
    property var transferSpeedHistory: ({})
    property var recoveryDismissed: ({})
    property var dismissedBrowserDownloadId: null
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
        if (!rows || !list)
            return
        const terms = searchTerm.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean)
        const queueIds = new Set(filterType === "queue" && currentQueue ? currentQueue.ids.map(Number) : [])
        const shown = downloads.filter(item => matchesFilter(item, queueIds, terms))
        shown.sort((a, b) => {
            if (groupedQueue && (a.status === "Complete") !== (b.status === "Complete"))
                return a.status === "Complete" ? 1 : -1
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
                sectionKey: entry.status === "Complete" ? "completed" : "unfinished",
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
        addDialog.openAddress(torrent)
    }

    function addDownload() {
        if (online && !busy)
            chooseAdd(false)
    }

    function showBatchDownload() {
        if (online && !busy && !batchDialog.visible)
            batchDialog.present()
    }

    function showBatchDownloadFromClipboard(text) {
        if (online && !busy)
            enginePrompts.links.present(text)
    }

    function showScheduler() {
        if (settingsWindow.visibility === Window.Minimized)
            settingsWindow.showNormal()
        settingsWindow.showCategory("Scheduler")
    }

    function setMainQueueRunningFromTray(running) {
        const queue = queues[0]
        if (queue && Boolean(queue.running) !== running)
            request({action: running ? "start_queue" : "stop_queue", queue: queue.name}, true)
    }

    function setTraySpeedLimiter(enabled) {
        request({action: "glass-setting", category: "speed_limit_on", queue: String(enabled)}, false, () => {
            enginePrompts.settings = Object.assign({}, enginePrompts.settings, {speed_limit_on: enabled})
            if (settingsWindow.visible)
                settingsWindow.load()
        })
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

    function canRecoverDownload(item) {
        if (!item || item.status === "Downloading" || item.status === "Complete")
            return false
        const visual = visualById[item.id]
        return Boolean(visual) && !visual.is_torrent && !visual.is_video && !visual.is_gallery && !visual.is_remote
    }

    function canRefreshDownloadAddress(item) {
        if (!canRecoverDownload(item))
            return false
        const details = detailWindows[String(item.id)]
        return details ? details.canOpenAddressEditor
            : !["searching", "preparing"].includes(visualById[item.id].recovery_stage)
    }

    function showDownload(id, recovery) {
        const key = String(id)
        const wasHidden = hiddenProgressIds.includes(key)
        let details = detailWindows[key]
        if (!details) {
            details = detailsFactory.createObject(downloadWindowOwner, {downloadId: Number(id)})
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
        if (recovery)
            details.openRecovery()
        details.raise()
        details.requestActivate()
        return details
    }

    Settings {
        id: windowPreferences
        category: "MainWindow"
        property bool compactView: false
        property int fullWidth: 810
        property int fullHeight: 525
    }

    function toggleCompactView() {
        if (!compactView && visibility === Window.Windowed) {
            windowPreferences.fullWidth = width
            windowPreferences.fullHeight = height
        }
        if (visibility === Window.Maximized)
            showNormal()
        windowPreferences.compactView = !compactView
        width = compactView ? 540 : windowPreferences.fullWidth
        height = compactView ? 390 : windowPreferences.fullHeight
        synchronizeRows()
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
    onVioletRailChanged: synchronizeRows()
    Component.onCompleted: {
        if (compactView) {
            width = 540
            height = 390
        }
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
    BrowserAppearance { backend: engine }
    function showUpdates() {
        updateNotice.showUpdate()
    }

    SettingsWindow {
        id: settingsWindow
        objectName: "settingsWindow"
        transientParent: null
        availableUpdate: updateNotice.availableUpdate
        onUpdateCheckRequested: updateNotice.manualCheck(settingsWindow)
        onSetupRequested: {
            settingsWindow.hide()
            startupSetup.present()
        }
        onUpdateDetailsRequested: updateNotice.showUpdate(settingsWindow)
        onConfigChanged: if (config) enginePrompts.settings = config
    }
    UpdateNotice {
        id: updateNotice
        backend: engine
        anchorWindow: root
        automaticChecks: settingsWindow.automaticUpdateChecks && !startupSetup.blockingAnnouncements
        minimizeToTray: root.minimizeToTray
        presentation: settingsWindow.updatePresentation
    }
    StartupSetup {
        id: startupSetup
        hostWindow: root
        automatic: engine.interactiveSetup === true
        languages: settingsWindow.common.language.options
    }
    AddDownloadDialog { id: addDialog }
    // Preserve QObject ownership without making the dashboard their native parent.
    QtObject { id: downloadWindowOwner }
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
        onHelpersRequested: settingsWindow.showCategory("Media Helpers")
    }
    BatchDownloadDialog { id: batchDialog; parent: root.contentItem }
    EnginePrompts {
        id: enginePrompts
        popupParent: root.contentItem
        onShowProgressRequested: downloadId => {
            if (!root.hiddenProgressIds.includes(String(downloadId)))
                root.showDownload(downloadId)
        }
        onDownloadCompleted: downloadId => {
            root.forgetHiddenProgress(downloadId)
            const details = root.detailWindows[String(downloadId)]
            if (details) {
                Qt.callLater(() => {
                    if (details.finished)
                        details.close()
                })
            }
        }
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
        onTriggered: root.showScheduler()
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

    component MenuRule: Basic.MenuSeparator {
        implicitHeight: 9
        leftPadding: 8
        rightPadding: 8
        topPadding: 4
        bottomPadding: 4
        contentItem: Rectangle {
            implicitHeight: 1
            color: MaterialTheme.menuColors.border
        }
    }

    AppMenu {
        id: downloadAreaMenu
        objectName: "downloadAreaContextMenu"
        parent: root.contentItem

        AppMenuItem { symbol: "add"; action: addUrl; text: qsTr("Add new download…") }
        AppMenuItem {
            symbol: "check"
            text: qsTr("Select all")
            enabled: rows.count > 0
            onTriggered: root.selectEveryRow()
        }
        AppMenu {
            id: arrangeDownloads
            objectName: "arrangeDownloadsMenu"
            title: qsTr("Arrange by")
            Instantiator {
                model: root.downloadSortLabels
                delegate: AppMenuItem {
                    required property int index
                    required property string modelData
                    text: modelData
                    checkable: true
                    checked: root.sortOrder === index
                    onTriggered: root.sortOrder = index
                }
                onObjectAdded: (index, object) => arrangeDownloads.insertItem(index, object)
                onObjectRemoved: (index, object) => arrangeDownloads.removeItem(object)
            }
        }
        AppMenuItem {
            symbol: "refresh"
            text: qsTr("Clear all filters")
            enabled: root.searchTerm.length > 0 || root.filterType !== "status" || root.filterKey !== "all"
            onTriggered: {
                searchField.clear()
                root.chooseFilter("status", "all")
            }
        }
        MenuRule {}
        AppMenuItem {
            symbol: "remove"
            action: removeCompleted
            text: qsTr("Delete all completed…")
            destructive: true
        }
    }

    AppMenu {
        id: contextMenu
        objectName: "downloadContextMenu"
        parent: root.contentItem
        AppMenuItem { symbol: "details"; action: detailsAction }
        AppMenuItem {
            objectName: "refreshDownloadAddressMenuItem"
            symbol: "refresh"
            text: qsTr("Refresh download address")
            visible: root.canRecoverDownload(root.currentItem)
            enabled: root.online && !root.busy && root.canRefreshDownloadAddress(root.currentItem)
            onTriggered: {
                const entry = root.currentItem
                if (root.canRefreshDownloadAddress(entry))
                    root.showDownload(entry.id, true)?.openAddressEditor()
            }
        }
        AppMenuItem {
            objectName: "downloadRecoveryMenuItem"
            symbol: "refresh"
            text: qsTr("Download recovery…")
            visible: root.canRecoverDownload(root.currentItem)
            enabled: root.online && !root.busy
            onTriggered: if (root.currentItem) root.showDownload(root.currentItem.id, true)
        }
        AppMenuItem {
            symbol: "file"
            text: qsTr("Open")
            enabled: root.currentItem !== null && root.currentItem.status === "Complete"
            onTriggered: root.openPicked(false)
        }
        AppMenuItem {
            symbol: "folder"
            text: qsTr("Open folder")
            enabled: root.currentItem !== null
            onTriggered: root.openPicked(true)
        }
        AppMenuItem { symbol: "file"; action: openWith }
        AppMenuItem { symbol: "folder"; action: moveFile }
        AppMenuItem { symbol: "refresh"; action: restartFile; commandColor: root.colors.caution }
        MenuRule {}
        AppMenuItem { symbol: "start"; action: resumeTransfers; commandColor: root.colors.positive }
        AppMenuItem { symbol: "pause"; action: pauseTransfers; commandColor: root.colors.caution }
        AppMenu {
            id: queueMenu
            title: qsTr("Add to queue")
            enabled: root.currentItem !== null && root.queues.length > 0
            Instantiator {
                model: root.queues
                delegate: AppMenuItem {
                    required property var modelData
                    symbol: "queue"
                    text: modelData.name
                    onTriggered: root.itemAction("queue-add", root.currentItem, modelData.name)
                }
                onObjectAdded: (index, object) => queueMenu.insertItem(index, object)
                onObjectRemoved: (index, object) => queueMenu.removeItem(object)
            }
        }
        AppMenuItem {
            symbol: "queue"
            text: qsTr("Remove from queue")
            enabled: root.currentItem !== null && root.queues.some(q => q.ids.includes(root.currentItem.id))
            onTriggered: root.itemAction("queue-remove", root.currentItem)
        }
        MenuRule {}
        AppMenuItem { symbol: "remove"; action: removeSelection; destructive: true }
    }

    function openRow(id, status) {
        if (status !== "Complete") {
            showDownload(id)
            return
        }
        request({query: "glass-settings"}, false, settings => {
            if (settings?.double_click_open === true)
                openPicked(false, {id, status})
            else
                showDownload(id)
        })
    }

    function openPicked(folder, item = currentItem) {
        if (!item || (!folder && item.status !== "Complete"))
            return
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
        readonly property color navigationAccent: MaterialTheme.vividControlAccent(MaterialTheme.safeAccent(
            MaterialTheme.forcedAccent || accent, root.fogSlate || root.colors.light), root.colors.light)
        readonly property var finish: MaterialTheme.buttonFinishes[root.colors.finish]
        readonly property color pigment: MaterialTheme.controlPigment(navigationAccent, root.colors.secondary, finish.tint)
        readonly property color baseFace: root.colors.navigationFill || root.colors.background
        readonly property real idleStrength: MaterialTheme.controlIdleStrength(root.colors, finish)
        readonly property color idleFace: MaterialTheme.mix(baseFace, pigment, idleStrength, 1)
        readonly property bool emphasized: checked || down || hovered || visualFocus
        readonly property color face: MaterialTheme.mix(baseFace,
            pigment, down ? finish.press : hovered || visualFocus ? finish.hover : finish.selected, 1)
        readonly property color actualFace: emphasized ? face : idleFace
        readonly property color foreground: MaterialTheme.controlTextInk(root.sidebarInk, actualFace)

        hoverEnabled: true
        leftPadding: 9
        rightPadding: 7
        topPadding: 3
        bottomPadding: 3
        Accessible.selected: checked
        contentItem: RowLayout {
            spacing: 7
            DashboardIcon {
                symbol: libraryButton.symbol
                ink: MaterialTheme.controlIconInk(libraryButton.navigationAccent, libraryButton.actualFace)
                relief: libraryButton.enabled
                surface: libraryButton.actualFace
                Layout.preferredWidth: 17
                Layout.preferredHeight: 17
            }
            Label {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: libraryButton.text
                color: libraryButton.foreground
                font.family: root.fontFamilyForText(text)
                font.pixelSize: TypographyScale.pixels(12)
                font.weight: libraryButton.checked ? Font.DemiBold : Font.Normal
            }
            NumeralLabel {
                visible: libraryButton.count.length > 0
                valueText: libraryButton.count
                color: MaterialTheme.controlTextInk(root.sidebarMuted, libraryButton.actualFace)
                font.pixelSize: TypographyScale.pixels(11)
            }
        }
        background: Rectangle {
            id: libraryFace
            radius: root.materialDashboard ? 8 : 6
            color: libraryButton.emphasized ? libraryButton.face
                : Qt.alpha(libraryButton.pigment, libraryButton.idleStrength)
            border.width: libraryButton.visualFocus ? 2 : 1
            border.color: libraryButton.visualFocus ? libraryButton.foreground
                : Qt.alpha(libraryButton.pigment, .45 + libraryButton.finish.depth * .35)

            ButtonLighting {
                anchors.fill: parent
                radius: libraryFace.radius
                enabled: libraryButton.enabled
                accent: libraryButton.pigment
                emphasized: libraryButton.emphasized
                pressed: libraryButton.down
            }

            Behavior on color {
                ColorAnimation { duration: MaterialTheme.reducedMotion ? 0 : 120 }
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

    component CommandMenuButton: AppMenuButton {
        property string symbol: ""
        Layout.fillWidth: root.sideMenus
        Layout.minimumWidth: root.sideMenus ? 0 : -1
        Layout.preferredWidth: root.sideMenus && root.violetRail ? violetMenuDock.width : -1
        Layout.preferredHeight: root.sideMenus ? (root.violetRail ? 37 : 25) : -1
        railIcon: root.sideMenus && root.violetRail ? symbol : ""
        accent: MaterialTheme.actionColor(symbol, root.fogSlate || root.colors.light)
        idleInk: root.sideMenus && root.violetRail ? "#ffffff"
            : root.sideMenus ? root.sidebarInk : MaterialTheme.menuColors.ink
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.layoutInset
        spacing: root.compactView ? 4 : 7

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.compactView ? 36 : 43
            GlassSurface { anchors.fill: parent; role: "title"; roundedPanel: true }
            CaptionMoveArea {
                objectName: "titleDragArea"
                hostWindow: root
                anchors.fill: parent
                anchors.rightMargin: titleActions.width + 6
                z: 1
                onDoubleClickRequested: root.toggleMaximized()
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 6
                spacing: 8
                BrandMark {
                    Layout.preferredWidth: root.compactView ? 24 : 29
                    Layout.preferredHeight: root.compactView ? 24 : 29
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label {
                        Layout.fillWidth: true
                        text: qsTr("Auralis")
                        color: root.colors.ink
                        font.pixelSize: TypographyScale.pixels(17)
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }
                    Label {
                        visible: !root.compactView
                        Layout.fillWidth: true
                        text: qsTr("Download Manager")
                        color: root.colors.muted
                        font.pixelSize: TypographyScale.pixels(11)
                        elide: Text.ElideRight
                    }
                }
                Rectangle {
                    Layout.preferredWidth: 7
                    Layout.preferredHeight: 7
                    radius: width / 2
                    color: root.online ? root.colors.positive : root.colors.caution
                }
                Label {
                    visible: !root.compactView
                    text: root.online ? qsTr("Connected") : qsTr("Offline")
                    color: root.colors.muted
                    font.pixelSize: TypographyScale.pixels(12)
                }
                RowLayout {
                    id: titleActions
                    spacing: 8

                    GlassButton {
                        objectName: "mainDonatePatreon"
                        visible: !root.compactView
                        Layout.preferredHeight: 34
                        text: qsTr("Donate on Patreon")
                        filled: true
                        accent: root.colors.light ? "#a64f25" : "#ffbd7d"
                        font.weight: Font.DemiBold
                        onClicked: Qt.openUrlExternally("https://www.patreon.com/c/Alsamii")
                    }
                    GlassButton {
                        id: compactButton
                        objectName: "mainCompactView"
                        readonly property string viewLabel: root.compactView ? qsTr("Full view") : qsTr("Compact view")
                        readonly property string viewHint: root.compactView ? qsTr("Return to the full layout")
                            : qsTr("Switch to the compact layout")
                        Layout.preferredHeight: 30
                        text: viewLabel
                        font.weight: Font.DemiBold
                        accent: root.colors.accent
                        filled: root.compactView
                        padding: 3
                        leftPadding: 8
                        rightPadding: 8
                        Accessible.name: viewLabel
                        Accessible.description: viewHint
                        contentItem: RowLayout {
                            spacing: 5
                            transform: Translate { y: compactButton.faceOffset }
                            DashboardIcon {
                                Layout.preferredWidth: 18
                                Layout.preferredHeight: 18
                                symbol: root.compactView ? "fullView" : "compactView"
                                ink: compactButton.iconInk
                                surface: compactButton.faceColor
                                relief: compactButton.enabled
                            }
                            Label {
                                text: compactButton.text
                                color: compactButton.buttonInk
                                font: compactButton.font
                                Accessible.ignored: true
                            }
                        }
                        ToolTip.visible: hovered || visualFocus
                        ToolTip.text: viewHint
                        ToolTip.delay: 420
                        onClicked: root.toggleCompactView()
                    }
                    CaptionControls {
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
        }

        Item {
            id: topMenuDock
            visible: !root.sideMenus
            Layout.fillWidth: true
            Layout.preferredHeight: root.compactView ? 27 : 31

            Item {
                id: menuPanel
                parent: !root.sideMenus ? topMenuDock : root.violetRail ? violetMenuDock : sideMenuDock
                anchors.fill: parent

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    visible: !root.sideMenus
                    color: MaterialTheme.menuColors.surface
                }

                GridLayout {
                    anchors.fill: parent
                    anchors.leftMargin: root.sideMenus ? 0 : 6
                    columns: root.sideMenus ? 1 : 7
                    columnSpacing: 2
                    rowSpacing: root.sideMenus ? 2 : 0
                    CommandMenuButton {
                        id: taskMenuButton
                        symbol: "add"
                        text: qsTr("&Tasks")
                        menuOpen: taskMenu.visible
                        onClicked: taskMenu.open()
                        AppMenu {
                            id: taskMenu
                            x: root.sideMenus ? taskMenuButton.width : 0
                            y: root.sideMenus ? 0 : taskMenuButton.height
                            AppMenuItem { symbol: "add"; action: addUrl; commandColor: root.colors.positive }
                            AppMenuItem { symbol: "torrent"; action: addTorrent; commandColor: root.colors.positive }
                            MenuRule {}
                            AppMenuItem { symbol: "file"; text: qsTr("Download video from a page…"); enabled: root.online; onTriggered: enginePrompts.video.presentLookup() }
                            AppMenuItem { symbol: "folder"; text: qsTr("Download a gallery…"); enabled: root.online; onTriggered: galleryDialog.present() }
                            AppMenuItem { symbol: "queue"; text: qsTr("Batch download…"); enabled: root.online; onTriggered: root.showBatchDownload() }
                            AppMenuItem { symbol: "add"; text: qsTr("Link grabber…"); enabled: root.online; onTriggered: enginePrompts.links.present() }
                            MenuRule {}
                            AppMenuItem { symbol: "tray"; text: qsTr("Hide in system tray"); enabled: Boolean(engine.trayAvailable); onTriggered: root.hideMainToTray() }
                            AppMenuItem { symbol: "close"; text: qsTr("Exit"); onTriggered: engine.requestQuit() }
                        }
                    }
                    CommandMenuButton {
                        id: fileMenuButton
                        symbol: "file"
                        text: qsTr("&File")
                        menuOpen: fileMenu.visible
                        onClicked: fileMenu.open()
                        AppMenu {
                            id: fileMenu
                            x: root.sideMenus ? fileMenuButton.width : 0
                            y: root.sideMenus ? 0 : fileMenuButton.height
                            AppMenuItem { symbol: "details"; action: detailsAction }
                            AppMenuItem { symbol: "file"; text: qsTr("Open"); enabled: root.currentItem !== null && root.currentItem.status === "Complete"; onTriggered: root.openPicked(false) }
                            AppMenuItem { symbol: "folder"; text: qsTr("Open folder"); enabled: root.currentItem !== null; onTriggered: root.openPicked(true) }
                            AppMenuItem { symbol: "file"; action: openWith }
                            AppMenuItem { symbol: "folder"; action: moveFile }
                            AppMenuItem { symbol: "refresh"; action: restartFile; commandColor: root.colors.caution }
                            MenuRule {}
                            AppMenuItem { symbol: "remove"; action: removeSelection; destructive: true }
                        }
                    }
                    CommandMenuButton {
                        id: downloadMenuButton
                        symbol: "downloads"
                        text: qsTr("&Downloads")
                        menuOpen: downloadMenu.visible
                        onClicked: downloadMenu.open()
                        AppMenu {
                            id: downloadMenu
                            x: root.sideMenus ? downloadMenuButton.width : 0
                            y: root.sideMenus ? 0 : downloadMenuButton.height
                            AppMenuItem { symbol: "start"; action: resumeTransfers; commandColor: root.colors.positive }
                            AppMenuItem { symbol: "pause"; action: pauseTransfers; commandColor: root.colors.caution }
                            AppMenuItem { symbol: "stop"; action: stopAll; commandColor: root.colors.caution }
                            AppMenuItem { symbol: "check"; action: removeCompleted; destructive: true }
                            MenuRule {}
                            AppMenuItem { symbol: "start"; action: startQueue; commandColor: root.colors.positive }
                            AppMenuItem { symbol: "stop"; action: stopQueue; commandColor: root.colors.caution }
                            AppMenuItem { symbol: "clock"; action: schedulerAction }
                        }
                    }
                    CommandMenuButton {
                        id: viewMenuButton
                        symbol: "details"
                        text: qsTr("&View")
                        menuOpen: viewMenu.visible
                        onClicked: viewMenu.open()
                        AppMenu {
                            id: viewMenu
                            x: root.sideMenus ? viewMenuButton.width : 0
                            y: root.sideMenus ? 0 : viewMenuButton.height
                            AppMenuItem { symbol: "refresh"; action: refreshAction }
                            AppMenuItem { symbol: "search"; action: findAction }
                            AppMenuItem { visible: !root.compactView; text: root.showSidebar ? qsTr("Hide sidebar") : qsTr("Show sidebar"); onTriggered: root.showSidebar = !root.showSidebar }
                            AppMenuItem { text: compactButton.viewLabel; onTriggered: root.toggleCompactView() }
                            MenuRule {}
                            AppMenuItem { symbol: "settings"; text: qsTr("Appearance"); onTriggered: settingsWindow.showCategory("Appearance") }
                            AppMenuItem { symbol: "settings"; text: qsTr("Display & fonts"); onTriggered: settingsWindow.showCategory("Display") }
                        }
                    }
                    CommandMenuButton {
                        id: helpMenuButton
                        symbol: "keys"
                        text: qsTr("&Help")
                        menuOpen: helpMenu.visible
                        onClicked: helpMenu.open()
                        AppMenu {
                            id: helpMenu
                            x: root.sideMenus ? helpMenuButton.width : 0
                            y: root.sideMenus ? 0 : helpMenuButton.height
                            AppMenuItem { symbol: "keys"; text: qsTr("Keyboard shortcuts"); onTriggered: shortcutsDialog.open() }
                            AppMenuItem { symbol: "web"; text: qsTr("Browser integration"); onTriggered: settingsWindow.showCategory("Browser Integration") }
                            AppMenuItem { symbol: "refresh"; text: qsTr("Check for updates"); enabled: updateNotice.updateSupported; onTriggered: updateNotice.manualCheck() }
                            AppMenuItem { symbol: "details"; text: qsTr("Updates & about"); onTriggered: settingsWindow.showCategory("Updates") }
                            AppMenuItem { symbol: "details"; text: qsTr("Project guide"); onTriggered: Qt.openUrlExternally("https://github.com/4ls4mi/Auralis-Download-Manager#guides-and-recovery") }
                            AppMenuItem { visible: root.compactView; text: qsTr("Donate on Patreon"); onTriggered: Qt.openUrlExternally("https://www.patreon.com/c/Alsamii") }
                        }
                    }
                    Item { Layout.fillWidth: true; Layout.fillHeight: root.sideMenus }
                }
            }
        }

        Item {
            id: topActionDock
            visible: !root.materialDashboard || root.compactView
            Layout.fillWidth: true
            Layout.preferredHeight: root.compactView ? 37 : 51
            Item {
                id: actionPanel
                parent: root.materialDashboard && !root.compactView ? workspaceActionDock : topActionDock
                anchors.fill: parent

                GlassSurface { anchors.fill: parent; role: "toolbar"; roundedPanel: true }
                RowLayout {
                    id: actionControls
                    anchors.fill: parent
                    anchors.leftMargin: 7
                    anchors.rightMargin: 7
                    spacing: root.materialDashboard || root.compact ? 4 : 7
                    Repeater {
                        model: [
                            {command: addUrl, icon: "add"},
                            {command: addTorrent, icon: "torrent", secondary: true},
                            {command: resumeTransfers, icon: "start"},
                            {command: pauseTransfers, icon: "pause"},
                            {command: stopAll, icon: "stop"},
                            {command: removeSelection, icon: "remove"},
                            {command: removeCompleted, icon: "check", secondary: true},
                            {command: settingsAction, icon: "settings"},
                            {command: schedulerAction, icon: "clock", secondary: true},
                            {command: startQueue, icon: "start", accentKey: "queueStart", secondary: true},
                            {command: stopQueue, icon: "pause", accentKey: "queueStop", secondary: true}
                        ]
                        delegate: GlassButton {
                            id: actionButton
                            required property int index
                            required property var modelData
                            readonly property bool primaryCommand: modelData.command === addUrl
                            readonly property bool fogResume: root.fogSlate && modelData.command === resumeTransfers
                            readonly property bool fogPause: root.fogSlate && modelData.command === pauseTransfers
                            readonly property string label: fogResume ? qsTr("Resume") : qsTr("Pause")
                            readonly property bool showLabel: !root.compactView && (fogResume || fogPause) && actionControls.width >= 730
                            visible: !root.compactView || !modelData.secondary
                            Layout.preferredWidth: root.compactView ? 36 : root.materialDashboard
                                ? (showLabel ? Math.max(102, buttonLabel.implicitWidth + 40)
                                    : Math.min(43, Math.floor((actionControls.width - 48) / 11)))
                                : root.compact ? 41 : 54
                            Layout.preferredHeight: root.compactView ? 30 : root.fogSlate ? 39 : 36
                            action: modelData.command
                            filled: (root.materialDashboard && primaryCommand) || fogResume
                            leftPadding: showLabel ? 13 : 4
                            rightPadding: leftPadding
                            topPadding: 4
                            bottomPadding: 5
                            accent: fogResume ? root.colors.positive
                                : root.materialDashboard && primaryCommand ? root.colors.accent
                                : MaterialTheme.actionColor(modelData.accentKey || modelData.icon, root.colors.light)
                            contentItem: RowLayout {
                                spacing: 5
                                transform: Translate { y: actionButton.faceOffset }
                                DashboardIcon {
                                    Layout.fillWidth: !actionButton.showLabel
                                    Layout.preferredWidth: root.compactView ? 19 : 24
                                    Layout.preferredHeight: root.compactView ? 19 : 24
                                    symbol: actionButton.modelData.icon
                                    bold: true
                                    solid: symbol === "start" || symbol === "stop"
                                    relief: actionButton.enabled
                                    ink: actionButton.iconInk
                                    surface: actionButton.faceColor
                                }
                                Label {
                                    id: buttonLabel
                                    visible: actionButton.showLabel
                                    Layout.fillWidth: true
                                    text: actionButton.label
                                    color: actionButton.buttonInk
                                    font.weight: Font.DemiBold
                                }
                            }
                            ToolTip.visible: hovered
                            ToolTip.text: text
                            ToolTip.delay: 420
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
            }
        }

        UpdateStatusCard {
            objectName: "mainUpdateBanner"
            Layout.fillWidth: true
            visible: Boolean(updateNotice.statusStage)
            stage: updateNotice.statusStage
            installedVersion: engine.version
            targetVersion: updateNotice.statusRelease?.version || ""
            installerBytes: updateNotice.statusInstallerBytes
            downloadedBytes: updateNotice.statusDownloadedBytes
            problem: updateNotice.statusProblem
            actionLabel: updateNotice.updateInProgress || updateNotice.statusProblem
                ? qsTr("View update status") : qsTr("Review update")
            announceChanges: true
            onActionRequested: root.showUpdates()
        }

        Frame {
            visible: root.recoveryNotice !== null
            Layout.fillWidth: true
            padding: 6
            background: GlassSurface { role: "card"; roundedPanel: true }
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
                    onClicked: if (root.recoveryNotice) root.showDownload(root.recoveryNotice.id, true)
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
            Layout.minimumHeight: root.compactView ? 95 : 155
            Layout.fillWidth: true
            spacing: 7

            Item {
                id: violetMenuDock
                visible: root.sideMenus && root.violetRail
                Layout.fillHeight: true
                Layout.preferredWidth: 45
                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: root.colors.railFill || root.colors.accent
                }
            }

            Frame {
                visible: root.showSidebar && !root.compactView
                Layout.preferredWidth: root.compact ? 151 : 184
                Layout.fillHeight: true
                padding: 6
                background: GlassSurface { role: "sidebar"; roundedPanel: true }
                ScrollView {
                    id: libraryScroll
                    anchors.fill: parent
                    anchors.bottomMargin: sideMenuDock.visible ? sideMenuDock.height + 6 : 0
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
                                accent: MaterialTheme.actionColor(modelData.icon, root.fogSlate || root.colors.light)
                                onClicked: root.chooseFilter("status", modelData.key)
                            }
                        }
                        Label {
                            text: qsTr("Categories")
                            color: root.sidebarMuted
                            leftPadding: 8
                            topPadding: 9
                            bottomPadding: 4
                            font.pixelSize: TypographyScale.pixels(12)
                            font.weight: Font.DemiBold
                        }
                        Repeater {
                            model: root.categories.filter(category => category.key !== "General")
                            delegate: LibraryButton {
                                required property var modelData
                                required property int index
                                width: parent.width
                                height: 29
                                text: modelData.name
                                symbol: "folder"
                                checked: root.filterType === "category" && root.filterKey === modelData.key
                                accent: MaterialTheme.navigationColor(index + 2, root.fogSlate || root.colors.light)
                                onClicked: root.chooseFilter("category", modelData.key)
                            }
                        }
                        Label {
                            visible: root.queues.length > 0
                            text: qsTr("Queues")
                            color: root.sidebarMuted
                            leftPadding: 8
                            topPadding: 9
                            bottomPadding: 4
                            font.pixelSize: TypographyScale.pixels(12)
                            font.weight: Font.DemiBold
                        }
                        Repeater {
                            model: root.queues
                            delegate: LibraryButton {
                                required property var modelData
                                required property int index
                                width: parent.width
                                height: 29
                                text: modelData.name
                                symbol: "queue"
                                count: String(modelData.ids.length)
                                checked: root.filterType === "queue" && root.filterKey === modelData.name
                                accent: modelData.running ? root.colors.positive
                                    : MaterialTheme.navigationColor(index + 4, root.fogSlate || root.colors.light)
                                onClicked: root.chooseFilter("queue", modelData.name)
                            }
                        }
                    }
                }
                Item {
                    id: sideMenuDock
                    visible: root.sideMenus && !root.violetRail
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 139
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Qt.alpha(root.sidebarInk, .16)
                    }
                }
            }

            Frame {
                Layout.fillHeight: true
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                padding: root.compactView ? 5 : 9
                background: GlassSurface { role: "content"; roundedPanel: true }
                ColumnLayout {
                    anchors.fill: parent
                    spacing: root.compactView ? 3 : root.materialDashboard ? 8 : 5
                    Item {
                        id: workspaceActionDock
                        visible: root.materialDashboard && !root.compactView
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                    }
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
                                font.pixelSize: TypographyScale.pixels(root.compactView ? 15
                                    : root.studioChrome ? (root.compact ? 20 : 24) : (root.compact ? 17 : 22))
                                font.weight: Font.Bold
                                elide: Text.ElideRight
                            }
                            NumeralLabel {
                                visible: !root.compactView
                                Layout.fillWidth: true
                                valueText: qsTr("%1 of %2 downloads").arg(rows.count).arg(root.downloads.length)
                                color: root.colors.muted
                                font.pixelSize: TypographyScale.pixels(11)
                            }
                        }
                        GlassButton {
                            visible: root.compactView && (root.filterType !== "status" || root.filterKey !== "all")
                            text: qsTr("All Downloads")
                            onClicked: root.chooseFilter("status", "all")
                        }
                        GlassComboBox {
                            id: sortSelector
                            visible: !root.compactView
                            Layout.preferredWidth: root.compact ? 115 : 132
                            model: root.downloadSortLabels
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
                        visible: !root.compactView && root.chosenIds.length > 0
                        NumeralLabel {
                            valueText: qsTr("%1 selected").arg(root.chosenItems.length)
                            color: root.colors.ink
                        }
                        GlassButton { action: resumeTransfers; accent: root.colors.positive }
                        GlassButton { action: pauseTransfers; accent: root.colors.caution }
                        GlassButton { action: removeSelection; accent: root.colors.destructive }
                        GlassButton { text: qsTr("Clear"); onClicked: root.clearSelection() }
                        Item { Layout.fillWidth: true }
                    }
                    RowLayout {
                        visible: !root.compactView && root.coralSlate && root.height >= 580
                        Layout.fillWidth: true
                        Layout.minimumHeight: 76
                        Layout.maximumHeight: 76
                        spacing: 8

                        GlassSurface {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            role: "card"
                            roundedPanel: true
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 13
                                Column {
                                    spacing: 3
                                    Label { text: qsTr("Total speed"); color: root.colors.muted; font.pixelSize: TypographyScale.pixels(11) }
                                    NumeralLabel {
                                        valueText: TransferData.rate(engine.dashboard.speed || 0)
                                        color: root.colors.ink
                                        font.pixelSize: TypographyScale.pixels(19)
                                        font.weight: Font.DemiBold
                                    }
                                }
                                TransferGraph {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    samples: root.graphValues
                                    animationStyle: WindowAppearance.graphAnimation
                                    flowActive: root.animateThroughput
                                    lineColor: MaterialTheme.graphColors[0]
                                    endpointColor: MaterialTheme.graphColors[1]
                                    gridColor: root.colors.divider
                                    Accessible.name: qsTr("Recent total transfer speed")
                                }
                            }
                        }
                        GlassSurface {
                            Layout.preferredWidth: Math.max(120, activeSummary.implicitWidth + 26)
                            Layout.fillHeight: true
                            role: "summary"
                            roundedPanel: true
                            Column {
                                id: activeSummary
                                anchors.left: parent.left
                                anchors.leftMargin: 13
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                Label {
                                    text: qsTr("Active downloads")
                                    color: root.colors.summaryInk || root.colors.ink
                                    font.pixelSize: TypographyScale.pixels(11)
                                }
                                NumeralLabel {
                                    valueText: String(root.counts.downloading)
                                    color: root.colors.summaryInk || root.colors.ink
                                    font.pixelSize: TypographyScale.pixels(21)
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                        GlassSurface {
                            id: connectionSummary
                            readonly property var workers: (root.currentVisual.connections || []).slice(0, 4)
                            visible: !root.compact && workers.length > 0
                            Layout.preferredWidth: 145
                            Layout.fillHeight: true
                            role: "connections"
                            roundedPanel: true

                            Column {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 3
                                Label { text: qsTr("Connections"); color: root.colors.muted; font.pixelSize: TypographyScale.pixels(11) }
                                Repeater {
                                    model: connectionSummary.workers
                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        readonly property var assignedFraction: TransferData.assigned(modelData.id, root.currentVisual.segments)
                                        width: parent.width
                                        height: 5
                                        radius: 2.5
                                        color: root.colors.divider
                                        Accessible.name: qsTr("Connection %1").arg(index + 1)
                                        Rectangle {
                                            width: parent.width * (parent.assignedFraction || 0)
                                            height: parent.height
                                            radius: parent.radius
                                            color: index % 2 ? MaterialTheme.connectionColors[1]
                                                : MaterialTheme.connectionColors[0]
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Item {
                        Layout.preferredHeight: root.compactView ? 25 : 30
                        Layout.fillWidth: true
                        GlassSurface { anchors.fill: parent; role: "field"; roundedPanel: true }
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
                                Layout.fillWidth: false
                                Layout.minimumWidth: root.indicatorColumnWidth
                                Layout.maximumWidth: root.indicatorColumnWidth
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
                                    text: root.compactView || (root.compact && root.materialDashboard) ? qsTr("Speed") : qsTr("Activity")
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
                        section.property: root.groupedQueue ? "sectionKey" : ""
                        section.delegate: Label {
                            required property string section
                            width: list.width - root.listGutter
                            leftPadding: 12
                            topPadding: 7
                            bottomPadding: 5
                            text: section === "completed" ? qsTr("Recently completed") : qsTr("Unfinished")
                            color: root.colors.ink
                            font.weight: Font.DemiBold
                            background: GlassSurface { role: "card" }
                        }
                        Accessible.role: Accessible.List
                        Accessible.name: qsTr("Downloads list")
                        ScrollBar.vertical: LibraryScrollBar { id: downloadsScrollBar }
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: point => {
                                if (downloadsScrollBar.visible && root.listGutter > 0
                                        && downloadsScrollBar.contains(downloadsScrollBar.mapFromItem(null, point.scenePosition)))
                                    return
                                const contentPosition = list.contentItem.mapFromItem(null, point.scenePosition)
                                if (list.indexAt(contentPosition.x, contentPosition.y) === -1)
                                    downloadAreaMenu.popup(root.contentItem.mapFromItem(null, point.scenePosition))
                            }
                        }
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
                            compactView: root.compactView
                            fileName: file
                            sizeLabel: TransferData.bytes(bytes) + (length >= 0 ? " / " + TransferData.bytes(length) : "")
                            statusLabel: root.statusText(status)
                            statusInk: root.statusColor(status)
                            transferring: status === "Downloading"
                            animationsAllowed: root.visibility !== Window.Minimized
                                && y + height > list.contentY && y < list.contentY + list.height
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
                            onOpened: root.openRow(transferId, status)
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
                            } else if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 &&
                                        (event.modifiers & Qt.ShiftModifier))) {
                                const row = list.currentItem
                                if (!root.currentItem)
                                    downloadAreaMenu.popup(list.mapToItem(root.contentItem, 12, 12))
                                else if (row)
                                    contextMenu.popup(row.mapToItem(root.contentItem, 12, row.height))
                                else
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

        Frame {
            id: browserNotice
            objectName: "browserDownloadNotice"
            readonly property var noticeId: root.browserDownloadNotice?.id ?? null
            readonly property string browserName: root.browserDownloadNotice?.browser || ""
            readonly property string filename: root.browserDownloadNotice?.name || ""
            readonly property string guidance: browserName
                ? qsTr("%1 kept this download. See it in the browser’s Downloads list.").arg(browserName)
                : qsTr("Your browser kept this download. See it in its Downloads list.")

            visible: noticeId !== null && noticeId !== root.dismissedBrowserDownloadId
            Layout.fillWidth: true
            padding: 7
            leftPadding: 10
            Accessible.role: Accessible.Grouping
            Accessible.name: qsTr("Browser download notice")
            Accessible.description: filename ? filename + ". " + guidance : guidance
            onNoticeIdChanged: {
                Qt.callLater(function () {
                    if (browserNotice.visible && root.visible && root.visibility !== Window.Minimized)
                        browserNotice.Accessible.announce(browserNotice.Accessible.description)
                })
            }

            background: GlassSurface { role: "card" }
            contentItem: RowLayout {
                spacing: 8

                DashboardIcon {
                    symbol: "downloads"
                    ink: root.colors.accent
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                    Accessible.ignored: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2

                    Label {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        visible: Boolean(browserNotice.filename)
                        text: browserNotice.filename
                        textFormat: Text.PlainText
                        color: root.colors.ink
                        font.family: root.fontFamilyForText(text)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Label {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: browserNotice.guidance
                        textFormat: Text.PlainText
                        color: root.colors.muted
                        font.family: root.fontFamilyForText(text)
                        wrapMode: Text.Wrap
                    }
                }

                GlassButton {
                    objectName: "dismissBrowserDownloadNotice"
                    text: qsTr("Dismiss")
                    Accessible.description: qsTr("Dismiss the browser download notice")
                    onClicked: root.dismissedBrowserDownloadId = browserNotice.noticeId
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.compactView ? 36 : 55
            GlassSurface { anchors.fill: parent; role: "footer"; roundedPanel: true }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 11
                anchors.rightMargin: 9
                spacing: root.compactView ? 8 : 13
                Repeater {
                    model: [
                        {title: qsTr("Total speed"), value: TransferData.rate(engine.dashboard.speed || 0)},
                        {title: qsTr("Active"), value: String(root.counts.downloading)}
                    ].concat(root.compactView ? [] : [
                        {title: qsTr("Completed"), value: String(root.counts.finished)}
                    ])
                    delegate: Item {
                        required property var modelData
                        Layout.preferredWidth: footerMetric.implicitWidth + (root.fogSlate && !root.compactView ? 20 : 0)
                        Layout.preferredHeight: footerMetric.implicitHeight + (root.fogSlate && !root.compactView ? 12 : 0)
                        GlassSurface { anchors.fill: parent; visible: root.fogSlate && !root.compactView; role: "card" }
                        ColumnLayout {
                            id: footerMetric
                            anchors.centerIn: parent
                            spacing: 2
                            Label { text: modelData.title; color: root.colors.muted; font.pixelSize: TypographyScale.pixels(11) }
                            NumeralLabel { valueText: modelData.value; color: root.colors.ink; font.weight: Font.DemiBold }
                        }
                    }
                }
                TransferGraph {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 85
                    Layout.preferredHeight: root.compactView ? 24 : 35
                    samples: root.graphValues
                    animationStyle: WindowAppearance.graphAnimation
                    flowActive: root.animateThroughput
                    lineColor: MaterialTheme.graphColors[0]
                    endpointColor: MaterialTheme.graphColors[1]
                    gridColor: root.colors.divider
                    Accessible.name: qsTr("Recent total transfer speed")
                }
                GlassComboBox {
                    id: footerLanguage
                    objectName: "mainLanguageSelector"
                    property bool saving: false
                    Layout.preferredWidth: root.compactView ? 96 : 110
                    Layout.alignment: Qt.AlignVCenter
                    model: settingsWindow.common.language.options
                    textRole: "label"
                    valueRole: "value"
                    currentIndex: Math.max(0, model.findIndex(language => language.value === engine.interfaceLanguage))
                    font.family: root.fontFamilyForText(displayText)
                    font.pixelSize: TypographyScale.pixels(11)
                    enabled: engine.ready && !saving
                    Accessible.name: qsTranslate("SettingsWindow", "Interface language")
                    onActivated: {
                        saving = true
                        engine.request({action: "glass-setting", category: "language", queue: currentValue},
                            function(reply, error) {
                                footerLanguage.saving = false
                                if (error || reply?.saved !== true)
                                    root.actionError = qsTranslate("SettingsWindow", "Could not change the interface language.")
                                footerLanguage.currentIndex = Qt.binding(() => Math.max(0,
                                    footerLanguage.model.findIndex(language => language.value === engine.interfaceLanguage)))
                            })
                    }
                }
                NumeralLabel {
                    id: statusMessage
                    visible: !root.compactView || Boolean(root.actionError)
                    Layout.preferredWidth: Math.min(root.compactView ? 134 : 240, Math.ceil(implicitWidth))
                    valueText: root.actionError || (root.online ? qsTr("Auralis %1").arg(engine.version) : engine.status || qsTr("Offline"))
                    color: root.actionError ? root.colors.destructive : root.colors.muted
                    elide: Text.ElideRight
                    font.pixelSize: TypographyScale.pixels(11)
                    PlainTextToolTip {
                        visible: statusHover.hovered && statusMessage.valueText.length > 20
                        text: statusMessage.valueText
                    }
                    HoverHandler { id: statusHover }
                }
            }
        }
    }

    WindowResizeHandles { hostWindow: root }
}
