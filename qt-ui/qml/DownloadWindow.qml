pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window
import "TransferData.js" as Transfer

ApplicationWindow {
    id: root
    objectName: "downloadProgressWindow"
    property var downloadId: null
    property bool trayEnabled: false
    property bool minimizeToTray: false
    signal hideToTrayRequested(var downloadId)
    property string material: MaterialTheme.current
    readonly property int resizeInset: 14
    readonly property var colors: MaterialTheme.profile(material)
    readonly property string transferLayout: colors.layout || ""
    readonly property bool sideTabs: ["fogSlate", "violetRail", "coralSlate"].includes(transferLayout)
    readonly property color detailDivider: colors.surfaceLine || colors.divider
    readonly property color summaryInk: sideTabs && colors.summaryInk ? colors.summaryInk : colors.text
    readonly property int recoveryTab: 3
    readonly property var transferTabs: {
        const tabs = [qsTr("Download status"), qsTr("Speed limiter"), qsTr("Options on completion")]
        if (recoveryAvailable)
            tabs.push(qsTr("Recovery"))
        return tabs
    }
    readonly property string progressShape: selectedShape(WindowAppearance.progressShape)
    readonly property string connectionShape: selectedShape(WindowAppearance.connectionShape)
    readonly property var item: Transfer.find(engine.dashboard.downloads, downloadId)
    readonly property var telemetry: Transfer.find(engine.visuals.downloads, downloadId)
    readonly property var workerRows: !torrent && telemetry && telemetry.connections ? telemetry.connections.slice(0, 32) : []
    readonly property var torrent: telemetry && telemetry.torrent ? telemetry.torrent : null
    readonly property bool mixed: !!(telemetry && telemetry.direct_recovery)
    readonly property bool ordinary: !!(telemetry && !telemetry.is_torrent && !telemetry.is_video && !telemetry.is_gallery && !telemetry.is_remote)
    readonly property bool runningTransfer: !!(item && item.status === "Downloading")
    readonly property bool displayFlow: activeTab === 0 && !!item && !!item.url
    readonly property bool interactiveFrame: resizeHandles.resizing || downloadCaption.dragging
    readonly property bool showWaterFlow: visible && visibility !== Window.Minimized && displayFlow
        && runningTransfer && !interactiveFrame
    readonly property var progressColors: MaterialTheme.progressColors
    readonly property var connectionColors: MaterialTheme.connectionColors
    readonly property bool finished: !!(item && item.status === "Complete")
    readonly property bool recoveryAvailable: !!item && ordinary && !runningTransfer && !finished
    readonly property string recoveryStage: telemetry && telemetry.recovery_stage || ""
    readonly property bool recoveryBusy: !!pendingResult || recoveryStage === "searching" || recoveryStage === "preparing"
    readonly property bool torrentRecoveryAllowed: !details.checksum
    readonly property bool backdropAvailable: windowBackdrop.backdropAvailable || windowBackdrop.pictureReady || windowBackdrop.movieReady
    property string message: ""
    property bool error: false
    property bool busy: false
    property string pendingResult: ""
    property bool polling: false
    property string previousStage: ""
    property var candidates: []
    property var speedSamples: []
    property var details: ({})
    property int activeTab: 0

    width: 790
    height: 625
    minimumWidth: 450
    minimumHeight: 340
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    transientParent: null
    palette.windowText: colors.text
    palette.text: colors.text
    palette.buttonText: colors.text
    palette.base: colors.background
    palette.highlight: colors.accent
    title: item ? Math.round(Transfer.fraction(item) * 100) + "%  " + item.file : qsTr("Download details")

    function hideToTray() {
        if (trayEnabled && downloadId !== null && !finished)
            hideToTrayRequested(downloadId)
        else
            showMinimized()
    }

    function minimizeWindow() {
        if (minimizeToTray && trayEnabled && downloadId !== null && !finished)
            hideToTray()
        else
            showMinimized()
    }

    function toggleMaximized() {
        if (visibility === Window.Maximized)
            showNormal()
        else
            showMaximized()
    }

    onVisibilityChanged: {
        if (root.visibility === Window.Minimized && root.minimizeToTray && root.trayEnabled && root.downloadId !== null && !root.finished) {
            Qt.callLater(() => {
                if (root.visibility === Window.Minimized)
                    root.hideToTray()
            })
        }
    }

    function openRecovery() {
        if (recoveryAvailable)
            activeTab = recoveryTab
    }

    function selectedShape(choice) {
        if (choice !== "material")
            return choice
        return ["bubble", "prism", "ice"].includes(colors.shape) ? colors.shape : "round"
    }

    function say(text, failed) {
        message = text || ""
        error = !!failed
    }

    function itemRequest(operation, value, callback) {
        const id = downloadId
        if (id === null || id === undefined)
            return
        const command = {action: "glass-item", category: operation, ids: [id]}
        if (value !== null && value !== undefined)
            command.queue = value
        engine.request(command, function (reply, transportError) {
            if (String(root.downloadId) !== String(id))
                return
            const issue = Transfer.problem(reply, transportError)
            if (callback)
                callback(reply || {}, issue)
            else if (issue)
                say(issue, true)
        })
    }

    function perform(action, thenClose) {
        if (busy || !item)
            return
        const id = downloadId
        busy = true
        engine.request({action, ids: [id]}, function (reply, transportError) {
            if (String(root.downloadId) !== String(id))
                return
            busy = false
            const failed = Transfer.problem(reply, transportError)
                || (reply && reply.skipped && reply.skipped.length ? reply.skipped[0].why : "")
            if (failed)
                say(failed, true)
            else {
                engine.refresh()
                if (thenClose)
                    close()
            }
        })
    }

    function openLocation(folder) {
        const id = downloadId
        engine.request({query: "glass-move-status", ids: [id]}, function (state, transportError) {
            if (String(root.downloadId) !== String(id))
                return
            const failed = Transfer.problem(state, transportError)
            if (failed || !state || state.moved_away || !state.path) {
                say(failed || qsTr("The file location is unavailable."), true)
                return
            }
            if (!(folder ? engine.openFolder(state.path) : engine.openPath(state.path)))
                say(qsTr("The saved file or folder could not be opened."), true)
        })
    }

    function loadDetails() {
        itemRequest("details", null, function (reply, issue) {
            if (issue) {
                say(issue, true)
                return
            }
            details = reply
            limitEnabled.checked = reply.own_limit_kb !== null && reply.own_limit_kb !== undefined
            limitField.text = limitEnabled.checked ? String(reply.own_limit_kb) : ""
            const completion = reply.completion || {}
            hangUp.checked = !!completion.hang_up
            closeApp.checked = !!completion.exit
            forceAction.checked = !!completion.force
            powerAction.currentIndex = Math.max(0, ["", "ShutDown", "Sleep", "Hibernate"].indexOf(completion.turn_off || ""))
        })
    }

    function saveOptions(operation, value, confirmation) {
        if (busy)
            return
        busy = true
        itemRequest(operation, value, function (reply, issue) {
            busy = false
            say(issue || confirmation, !!issue)
            if (!issue)
                engine.refresh()
        })
    }

    function beginCheck(operation, value, text) {
        if (busy || pendingResult)
            return
        busy = true
        say(text, false)
        if (operation === "find-recovery-torrents" || operation.indexOf("check-recovery-") === 0) {
            candidates = []
            risk.checked = false
        }
        itemRequest(operation, value, function (reply, issue) {
            busy = false
            if (issue) {
                say(issue, true)
                return
            }
            pendingResult = operation.indexOf("check-recovery-") === 0
                            ? "find-recovery-torrents-result" : operation + "-result"
            pollResult()
        })
    }

    function pollResult() {
        if (!pendingResult || polling)
            return
        const operation = pendingResult
        polling = true
        itemRequest(operation, null, function (reply, issue) {
            polling = false
            if (operation !== pendingResult)
                return
            if (!issue && !reply.complete)
                return
            pendingResult = ""
            if (issue || reply.failure) {
                say(issue || reply.failure, true)
                return
            }
            if (operation === "find-recovery-torrents-result") {
                candidates = reply.matches || []
                if (candidates.length > 0)
                    say(qsTr("Found %1 possible match(es). Confirm the piece comparison before continuing.").arg(candidates.length), false)
                else if (reply.searched && reply.failed === reply.searched)
                    say(qsTr("No candidates could be checked. Try another source."), true)
                else
                    say(qsTr("No matching torrent could be verified. Try a torrent link, magnet or file."), false)
            } else if (operation === "start-recovery-torrent-result") {
                const report = reply.report || {}
                say(qsTr("Continuing via BitTorrent. Reused %1 of verified data.").arg(Transfer.bytes(report.verified_bytes)), false)
                engine.refresh()
            } else if (operation === "checksum-result") {
                say(reply.error || (reply.matches ? qsTr("The file matches its checksum.") : qsTr("Checksum mismatch.")), !reply.matches)
            } else {
                const report = reply.report || {}
                const damaged = (report.damaged_ranges || []).length
                const unchecked = report.unhashed_bytes ? qsTr(" %1 had no saved hash.").arg(Transfer.bytes(report.unhashed_bytes)) : ""
                say(operation === "repair-saved-result"
                    ? qsTr("Repair prepared. %1 of saved data was retained.").arg(Transfer.bytes(report.retained_bytes)) + unchecked
                    : qsTr("Checked %1. Found %2 changed range(s).").arg(Transfer.bytes(report.checked_bytes)).arg(damaged) + unchecked,
                    operation !== "repair-saved-result" && damaged > 0)
                engine.refresh()
            }
        })
    }

    function observeRecovery() {
        if (!visible || recoveryStage === previousStage)
            return
        previousStage = recoveryStage
        if (pendingResult)
            return
        if (recoveryStage === "searching" || recoveryStage === "matched") {
            pendingResult = "find-recovery-torrents-result"
            say(recoveryStage === "searching" ? qsTr("The direct download failed. Checking matching torrents…") : qsTr("A possible matching torrent is available."), false)
            pollResult()
        } else if (recoveryStage === "preparing" || recoveryStage === "handoff-failed") {
            pendingResult = "start-recovery-torrent-result"
            pollResult()
        } else if (recoveryStage === "no-match") {
            say(qsTr("No matching torrent could be verified. Try a torrent link, magnet or file."), false)
        } else if (recoveryStage === "search-failed") {
            say(qsTr("The torrent search failed. Try another source."), true)
        } else if (recoveryStage === "handed-off" && telemetry && telemetry.recovery_verified_bytes != null) {
            say(qsTr("BitTorrent reused %1 of verified data.").arg(Transfer.bytes(telemetry.recovery_verified_bytes)), false)
        }
    }

    function cancelRecovery() {
        itemRequest("cancel-recovery-torrent", null, function (reply, issue) {
            if (!issue) {
                pendingResult = ""
                candidates = []
                say(qsTr("Torrent recovery was cancelled. Saved data was kept."), false)
                engine.refresh()
            } else {
                say(issue, true)
            }
        })
    }

    onVisibleChanged: if (visible) {
        loadDetails()
        observeRecovery()
    }
    onRecoveryStageChanged: observeRecovery()
    onRecoveryAvailableChanged: {
        if (!recoveryAvailable && activeTab === recoveryTab)
            activeTab = 0
    }
    onActiveTabChanged: {
        const flickable = view ? (view.contentItem as Flickable) : null
        if (flickable)
            flickable.contentY = flickable.originY
    }
    onDownloadIdChanged: {
        activeTab = 0
        speedSamples = []
        busy = false
        previousStage = ""
        pendingResult = ""
        polling = false
        candidates = []
        say("", false)
        if (visible) {
            loadDetails()
            observeRecovery()
        }
    }

    Timer {
        interval: 950
        repeat: true
        running: root.visible && !!root.pendingResult
        onTriggered: root.pollResult()
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.visible && root.runningTransfer
        onTriggered: root.speedSamples = root.speedSamples.slice(-59).concat([Math.max(0, Number(root.item.speed) || 0)])
    }

    background: WindowBackdrop {
        id: windowBackdrop
        hostWindow: root
        target: "details"
    }

    header: ColumnLayout {
        spacing: 0
        ToolBar {
            Layout.fillWidth: true
            padding: 0
            background: GlassSurface { material: root.material; role: "title"; backdropAvailable: root.backdropAvailable }
            contentItem: RowLayout {
                spacing: 7
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 43
                    BrandMark {
                        id: transferBrand
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: transferBrand.right
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        verticalAlignment: Text.AlignVCenter
                        text: root.title
                        textFormat: Text.PlainText
                        elide: Text.ElideMiddle
                        font.weight: Font.DemiBold
                        color: root.colors.ink
                    }
                    CaptionMoveArea {
                        id: downloadCaption
                        objectName: "downloadTitleDragArea"
                        hostWindow: root
                        allowManualMove: true
                        anchors.fill: parent
                        onDoubleClickRequested: root.toggleMaximized()
                    }
                }
                CaptionControls {
                    material: root.material
                    trayEnabled: root.trayEnabled && root.downloadId !== null && !root.finished
                    maximized: root.visibility === Window.Maximized
                    minimizeLabel: root.trayEnabled && root.minimizeToTray && !root.finished
                        ? qsTr("Minimize to system tray") : qsTr("Minimize")
                    closeLabel: qsTr("Close download window")
                    onHideRequested: root.hideToTray()
                    onMinimizeRequested: root.minimizeWindow()
                    onMaximizeRequested: root.toggleMaximized()
                    onCloseRequested: root.close()
                }
                Item { Layout.preferredWidth: root.resizeInset }
            }
        }
        ToolBar {
            objectName: "transferCommands"
            Layout.fillWidth: true
            leftPadding: root.resizeInset + 2
            rightPadding: root.resizeInset + 2
            topPadding: 7
            bottomPadding: 7
            background: GlassSurface { material: root.material; role: "toolbar"; backdropAvailable: root.backdropAvailable }
            contentItem: Flow {
                spacing: 7
                GlassButton {
                    objectName: "pauseOrResumeDownload"
                    material: root.material
                    text: root.runningTransfer ? qsTr("Pause") : root.item && root.item.status === "Queued" ? qsTr("Start") : qsTr("Resume")
                    visible: !!root.item && !root.finished
                    enabled: !root.busy && (root.runningTransfer || (!root.recoveryBusy && !(root.telemetry && root.telemetry.recovery_damaged)))
                    accent: root.runningTransfer ? root.colors.caution : root.colors.positive
                    onClicked: root.perform(root.runningTransfer ? "pause" : "start", false)
                }
                GlassButton {
                    objectName: "stopOrCloseDownload"
                    material: root.material
                    text: root.runningTransfer ? qsTr("Cancel…") : qsTr("Close")
                    accent: root.runningTransfer ? root.colors.destructive : root.colors.accent
                    onClicked: root.runningTransfer ? stopConsent.open() : root.close()
                }
                GlassButton { material: root.material; text: qsTr("Open folder"); enabled: !!root.item; onClicked: root.openLocation(true) }
                GlassButton {
                    material: root.material
                    text: qsTr("Open file")
                    visible: root.finished
                    accent: root.colors.positive
                    onClicked: root.openLocation(false)
                }
                GlassButton {
                    material: root.material
                    text: qsTr("Open with…")
                    visible: root.finished
                    onClicked: root.itemRequest("open-with", null)
                }
                GlassButton {
                    material: root.material
                    text: qsTr("Move file…")
                    visible: root.finished
                    enabled: !root.busy
                    onClicked: movePicker.open()
                }
                GlassButton {
                    material: root.material
                    text: qsTr("Verify checksum")
                    visible: root.finished && !!root.details.checksum
                    enabled: !root.busy && !root.pendingResult
                    onClicked: root.beginCheck("checksum", root.details.checksum, qsTr("Verifying checksum…"))
                }
                GlassButton {
                    objectName: "openDownloadRecovery"
                    material: root.material
                    text: qsTr("Recovery…")
                    visible: root.recoveryAvailable && root.activeTab !== root.recoveryTab
                    accent: root.colors.accent
                    onClicked: root.openRecovery()
                }
            }
        }
        ToolBar {
            visible: !root.sideTabs
            Layout.fillWidth: true
            padding: 8
            leftPadding: root.resizeInset + 2
            rightPadding: root.resizeInset + 2
            background: GlassSurface { material: root.material; role: "toolbar"; backdropAvailable: root.backdropAvailable }
            contentItem: Flow {
                spacing: 7
                Repeater {
                    model: root.transferTabs
                    delegate: GlassButton {
                        required property int index
                        required property string modelData
                        material: root.material
                        text: modelData
                        checkable: true
                        checked: root.activeTab === index
                        onClicked: root.activeTab = index
                    }
                }
            }
        }
    }

    WindowResizeHandles {
        id: resizeHandles
        hostWindow: root
        // The Quick grips own the pointer grab. A second Win32 capture path
        // would compete with the same drag on this transparent window.
        coalesceGeometry: true
        borderSize: 11
        cornerSize: 19
        showGrip: true
        gripColor: root.colors.muted
    }

    Timer {
        id: water
        property real phase: 0
        interval: root.workerRows.length > 16 ? 96 : root.workerRows.length > 8 ? 64 : 48
        repeat: true
        running: root.showWaterFlow && !MaterialTheme.reducedMotion
        onTriggered: phase = (phase + Math.PI * 2 * interval / 1120) % (Math.PI * 2)
    }

    Pane {
        id: transferRail
        visible: root.sideTabs
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.resizeInset
        anchors.left: parent.left
        width: root.transferLayout === "violetRail"
            ? Math.max(122, Math.min(169, Math.round(root.width * .21)))
            : Math.max(115, Math.min(145, Math.round(root.width * .19)))
        padding: 9
        topPadding: root.transferLayout === "violetRail" ? 19 : padding
        background: GlassSurface {
            material: root.material
            role: "sidebar"
            backdropAvailable: root.backdropAvailable
            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: root.detailDivider
            }
        }
        contentItem: ColumnLayout {
            spacing: 5
            Repeater {
                model: root.transferTabs
                delegate: GlassButton {
                    id: transferTab
                    required property int index
                    required property string modelData
                    material: root.material
                    accent: MaterialTheme.navigationColor(index, root.colors.light)
                    text: modelData
                    checkable: true
                    autoExclusive: true
                    checked: root.activeTab === index
                    onClicked: root.activeTab = index
                    Layout.fillWidth: true
                    Layout.minimumHeight: 36
                    leftPadding: 8
                    rightPadding: 8
                    contentItem: Label {
                        text: transferTab.text
                        textFormat: Text.PlainText
                        font: transferTab.font
                        color: transferTab.buttonInk
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
            }
            Item { Layout.fillHeight: true }
        }
    }

    ScrollView {
        id: view
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.resizeInset
        anchors.left: root.sideTabs ? transferRail.right : parent.left
        anchors.right: parent.right
        anchors.rightMargin: root.resizeInset
        clip: true
        padding: root.transferLayout === "fogSlate" ? 10 : 12
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        Item {
            width: view.availableWidth
            implicitHeight: sections.implicitHeight

            ColumnLayout {
                id: sections
                anchors.fill: parent
                spacing: 10

                Label {
                    visible: !root.item
                    text: qsTr("Waiting for download information…")
                    color: root.colors.muted
                }

                Pane {
                    visible: !!root.item && root.activeTab === 0
                    Layout.fillWidth: true
                    padding: root.transferLayout === "fogSlate" ? 12 : 15
                    leftPadding: root.displayFlow ? 27 : padding
                    background: GlassSurface {
                        material: root.material
                        role: root.sideTabs ? "summary" : "card"
                        backdropAvailable: root.backdropAvailable
                    }
                    contentItem: ColumnLayout {
                        spacing: root.transferLayout === "fogSlate" ? 8 : 10
                        Label {
                            Layout.fillWidth: true
                            text: root.item ? root.item.file : ""
                            textFormat: Text.PlainText
                            elide: Text.ElideMiddle
                            color: root.summaryInk
                            font.pixelSize: 19
                            font.bold: true
                        }
                        Label {
                            id: transferSource
                            Layout.fillWidth: true
                            text: root.item ? root.item.url : ""
                            textFormat: Text.PlainText
                            elide: Text.ElideMiddle
                            color: root.colors.muted
                        }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: width >= (root.sideTabs ? 540 : 560) ? 2 : 1
                            rowSpacing: 6
                            columnSpacing: 16
                            Repeater {
                                id: measurements
                                property var cells: {
                                    const d = root.item || {}
                                    const t = root.telemetry || {}
                                    const server = t.server || {}
                                    return [
                                        {label: qsTr("Status"), value: d.status || "—"},
                                        {label: qsTr("Transfer method"), value: root.mixed ? qsTr("Direct → BitTorrent") : t.is_torrent ? qsTr("BitTorrent") : t.is_video ? qsTr("Video") : qsTr("Direct download")},
                                        {label: qsTr("Downloaded"), value: Transfer.bytes(d.downloaded) + " / " + Transfer.bytes(d.size)},
                                        {label: qsTr("Transfer rate"), value: Transfer.rate(d.speed)},
                                        {label: qsTr("Time left"), value: Transfer.timeLeft(d)},
                                        {label: qsTr("Resume capability"), value: t.resumable === true ? qsTr("Yes") : t.resumable === false ? qsTr("No") : qsTr("Unknown")},
                                        {label: root.torrent ? qsTr("Connected peers") : qsTr("Server"), value: root.torrent ? String(root.torrent.peers || 0)
                                            : (server.place && server.place.name || server.country_code || server.hostname || "—") + (server.rtt_ms != null ? " · " + server.rtt_ms + " ms" : "")}
                                    ]
                                }
                                model: cells.length
                                delegate: RowLayout {
                                    id: measurement
                                    required property int index
                                    readonly property var cell: measurements.cells[index]
                                    Layout.fillWidth: true
                                    Label {
                                    text: measurement.cell.label
                                    color: root.colors.muted
                                    Layout.preferredWidth: root.sideTabs ? 132 : 116
                                    elide: Text.ElideRight
                                }
                                    Label { text: measurement.cell.value; textFormat: Text.PlainText; color: root.summaryInk; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                            }
                        }
                        Item {
                            id: progressLine
                            Layout.fillWidth: true
                            implicitHeight: Math.max(38, progressPercent.implicitHeight)
                            GlassProgress {
                                id: downloadProgress
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, Math.min(progressLine.width * .53,
                                    progressLine.width - progressPercent.width - progressPercent.anchors.leftMargin))
                                height: 38
                                value: Transfer.fraction(root.item)
                                animated: root.runningTransfer && !root.interactiveFrame
                                shape: root.progressShape
                                fillStyle: WindowAppearance.progressFill
                                startColor: root.progressColors[0]
                                endColor: root.progressColors[1]
                                trackColor: root.colors.background
                                material: root.material
                                Accessible.name: qsTr("Download progress")
                            }
                            Label {
                                id: progressPercent
                                anchors.left: downloadProgress.right
                                anchors.leftMargin: 5
                                anchors.verticalCenter: parent.verticalCenter
                                text: Math.round(Transfer.fraction(root.item) * 100) + "%"
                                color: root.summaryInk
                                font.bold: true
                            }
                        }
                        Label {
                            visible: root.mixed
                            Layout.fillWidth: true
                            color: root.colors.positive
                            wrapMode: Text.WordWrap
                            text: root.mixed && root.telemetry.original_partial
                                  ? qsTr("Original direct partial kept at %1").arg(root.telemetry.original_partial) : ""
                            textFormat: Text.PlainText
                        }
                        Label {
                            visible: !!(root.item && root.item.error)
                            Layout.fillWidth: true
                            text: root.item && root.item.error || ""
                            textFormat: Text.PlainText
                            color: root.colors.destructive
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                GridLayout {
                    id: transferOverview
                    visible: !!root.item && root.activeTab === 0
                    Layout.fillWidth: true
                    columns: root.transferLayout !== "coralSlate" && width >= (root.sideTabs ? 535 : 630) ? 2 : 1
                    columnSpacing: root.transferLayout === "fogSlate" ? 8 : 10
                    rowSpacing: root.transferLayout === "fogSlate" ? 8 : 10
                    Pane {
                        Layout.fillWidth: true
                        Layout.preferredWidth: root.transferLayout === "violetRail" ? 315 : 355
                        Layout.alignment: root.sideTabs ? Qt.AlignTop : Qt.AlignVCenter
                        padding: 12
                        leftPadding: root.displayFlow ? 27 : padding
                        background: GlassSurface {
                            material: root.material
                            role: root.sideTabs ? "connections" : "card"
                            backdropAvailable: root.backdropAvailable
                        }
                        contentItem: ColumnLayout {
                            spacing: 8
                            Label { text: root.torrent ? qsTr("BitTorrent swarm") : qsTr("Connections"); color: root.colors.text; font.bold: true }
                            Label {
                                visible: !!root.torrent
                                Layout.fillWidth: true
                                color: root.colors.muted
                                wrapMode: Text.WordWrap
                                text: root.torrent ? qsTr("Upload %1  ·  Sent %2\nInfo hash %3").arg(Transfer.rate(root.torrent.upload_speed)).arg(Transfer.bytes(root.torrent.uploaded)).arg(root.torrent.info_hash || "—") : ""
                            }
                            Label {
                                visible: !root.torrent && !(root.telemetry && root.telemetry.connections && root.telemetry.connections.length)
                                text: qsTr("No active connection data")
                                color: root.colors.muted
                            }
                            GridLayout {
                                id: waterGrid
                                Layout.fillWidth: true
                                Layout.topMargin: root.displayFlow ? 10 : 0
                                columns: 8
                                rowSpacing: root.displayFlow ? 16 : 5
                                columnSpacing: 5
                                Repeater {
                                    id: waterWorkers
                                    model: root.workerRows.length
                                    delegate: Item {
                                        id: worker
                                        required property int index
                                        readonly property var connection: root.workerRows[index] || {}
                                        readonly property var saved: Transfer.assigned(connection.id, root.telemetry && root.telemetry.segments)
                                        readonly property bool receiving: root.runningTransfer && connection.state === "Receiving"
                                        readonly property real liquidSurface: chunkWater.surfaceY
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 31
                                        Layout.preferredHeight: 39
                                        ConnectionWater {
                                            id: chunkWater
                                            anchors.fill: parent
                                            material: root.material
                                            shape: root.connectionShape
                                            fillStyle: WindowAppearance.connectionFill
                                            value: worker.saved
                                            paintingPaused: root.interactiveFrame
                                            receiving: worker.receiving
                                            phase: worker.receiving ? water.phase : 0
                                            startColor: root.connectionColors[0]
                                            endColor: root.connectionColors[1]
                                            trackColor: root.colors.background
                                        }
                                        Label {
                                            anchors.left: parent.left
                                            anchors.leftMargin: 4
                                            anchors.top: parent.top
                                            anchors.topMargin: 4
                                            color: root.colors.text
                                            style: Text.Outline
                                            styleColor: root.colors.shade
                                            text: Number(worker.connection.id) + 1
                                            font.pixelSize: 11
                                        }
                                        HoverHandler { id: workerHover }
                                        ToolTip.visible: workerHover.hovered
                                        ToolTip.text: saved === null
                                            ? qsTr("Connection %1 · %2 · %3").arg(Number(connection.id) + 1)
                                                .arg(connection.state).arg(Transfer.rate(connection.speed))
                                            : qsTr("Connection %1 · %2 · %3 · %4%").arg(Number(connection.id) + 1)
                                                .arg(connection.state).arg(Transfer.rate(connection.speed)).arg(Math.round(saved * 100))
                                        Accessible.name: ToolTip.text
                                    }
                                }
                            }
                        }
                    }
                    Pane {
                        Layout.fillWidth: true
                        Layout.preferredWidth: root.transferLayout === "violetRail" ? 380 : 325
                        Layout.alignment: root.sideTabs ? Qt.AlignTop : Qt.AlignVCenter
                        Layout.topMargin: root.transferLayout === "violetRail" && transferOverview.columns === 2 ? 19 : 0
                        padding: 12
                        background: GlassSurface { material: root.material; role: "card"; backdropAvailable: root.backdropAvailable }
                        contentItem: ColumnLayout {
                            spacing: 8
                            RowLayout {
                                Label { text: qsTr("Transfer speed"); color: root.colors.text; font.bold: true }
                                Item { Layout.fillWidth: true }
                                Label { text: root.item ? Transfer.rate(root.item.speed) : "—"; color: root.colors.muted }
                            }
                            TransferGraph {
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.transferLayout === "fogSlate" ? 92 : 106
                                samples: root.speedSamples
                                paintingPaused: root.interactiveFrame
                                lineColor: MaterialTheme.graphColors[0]
                                endpointColor: MaterialTheme.graphColors[1]
                                gridColor: root.colors.divider
                                Accessible.name: qsTr("Measured transfer speed history")
                            }
                        }
                    }
                }

                Pane {
                    objectName: "downloadRecoveryPane"
                    visible: root.activeTab === root.recoveryTab && root.recoveryAvailable
                    Layout.fillWidth: true
                    padding: 14
                    background: GlassSurface { material: root.material; role: "card"; backdropAvailable: root.backdropAvailable }
                    contentItem: ColumnLayout {
                        spacing: 10
                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Download recovery")
                            color: root.colors.text
                            font.bold: true
                            font.pixelSize: 16
                        }
                        Label {
                            visible: root.message !== ""
                            Layout.fillWidth: true
                            text: root.message
                            textFormat: Text.PlainText
                            color: root.error ? root.colors.destructive : root.colors.text
                            wrapMode: Text.Wrap
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            GlassButton {
                                objectName: "verifySavedDownload"
                                text: qsTr("Verify saved data")
                                enabled: !root.busy && !root.recoveryBusy
                                material: root.material
                                onClicked: root.beginCheck("check-saved", null, qsTr("Checking saved blocks…"))
                            }
                            GlassButton {
                                text: qsTr("Check source and repair")
                                enabled: !root.busy && !root.recoveryBusy
                                material: root.material
                                onClicked: root.beginCheck("repair-saved", null, qsTr("Checking the direct source…"))
                            }
                            GlassButton {
                                text: qsTr("Download again…")
                                enabled: !root.busy && !root.recoveryBusy
                                material: root.material
                                accent: root.colors.caution
                                onClicked: restartConsent.open()
                            }
                            GlassButton {
                                text: qsTr("Update address…")
                                enabled: !root.busy && !root.recoveryBusy
                                material: root.material
                                onClicked: {
                                    updatedAddress.text = root.item.url
                                    addressPrompt.open()
                                }
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: qsTr("Continue with BitTorrent")
                            color: root.colors.text
                            font.bold: true
                        }
                        Label {
                            visible: !root.torrentRecoveryAllowed
                            Layout.fillWidth: true
                            color: root.colors.muted
                            wrapMode: Text.WordWrap
                            text: qsTr("Torrent recovery is unavailable when a whole-file checksum is required.")
                        }
                        TextField {
                            id: link
                            Layout.fillWidth: true
                            enabled: root.torrentRecoveryAllowed && !root.busy && !root.recoveryBusy
                            color: root.colors.text
                            placeholderText: qsTr("Magnet or torrent URL")
                            background: GlassSurface { material: root.material; role: "field" }
                            Accessible.name: placeholderText
                            onAccepted: if (checkLink.enabled) linkConsent.open()
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            GlassButton {
                                id: checkLink
                                objectName: "checkRecoveryLink"
                                material: root.material
                                text: qsTr("Check link")
                                enabled: link.enabled && /^(magnet:\?|https?:\/\/)/i.test(link.text.trim())
                                onClicked: linkConsent.open()
                            }
                            GlassButton {
                                material: root.material
                                text: qsTr("Torrent file…")
                                enabled: link.enabled
                                onClicked: recoveryFile.open()
                            }
                            GlassButton {
                                text: qsTr("Search Internet Archive")
                                enabled: link.enabled
                                material: root.material
                                onClicked: searchConsent.open()
                            }
                            GlassButton {
                                text: qsTr("Cancel torrent recovery")
                                material: root.material
                                visible: root.recoveryStage === "searching" || root.recoveryStage === "preparing"
                                         || root.pendingResult === "find-recovery-torrents-result" || root.pendingResult === "start-recovery-torrent-result"
                                onClicked: root.cancelRecovery()
                            }
                        }
                        CheckBox {
                            id: risk
                            visible: root.candidates.length > 0
                            Layout.fillWidth: true
                            text: qsTr("I understand that the rest of the torrent may differ.")
                            contentItem: Label {
                                text: risk.text
                                color: root.colors.text
                                verticalAlignment: Text.AlignVCenter
                                wrapMode: Text.Wrap
                                leftPadding: risk.indicator.width + risk.spacing
                            }
                        }
                        Repeater {
                            model: root.candidates
                            delegate: ColumnLayout {
                                id: candidate
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 4
                                Label {
                                    text: candidate.modelData.title || candidate.modelData.path
                                    textFormat: Text.PlainText
                                    color: root.colors.text
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: qsTr("%1 matching pieces · %2 unchecked").arg(candidate.modelData.matching_pieces).arg(candidate.modelData.unavailable_pieces)
                                    color: root.colors.muted
                                    wrapMode: Text.Wrap
                                }
                                GlassButton {
                                    material: root.material
                                    text: qsTr("Continue with torrent")
                                    enabled: root.torrentRecoveryAllowed && risk.checked && !root.busy && !root.recoveryBusy
                                    onClicked: root.beginCheck("start-recovery-torrent",
                                        JSON.stringify({candidate: candidate.modelData.candidate, file_index: candidate.modelData.file_index,
                                            info_hash: candidate.modelData.info_hash, accept_partial_match: true}),
                                        qsTr("Rechecking compatible pieces…"))
                                }
                            }
                        }
                    }
                }

                Pane {
                    visible: root.activeTab === 1
                    Layout.fillWidth: true
                    padding: 14
                    background: GlassSurface { material: root.material; role: "card"; backdropAvailable: root.backdropAvailable }
                    contentItem: ColumnLayout {
                        spacing: 10
                        CheckBox { id: limitEnabled; text: qsTr("Limit this download's speed") }
                        RowLayout {
                            TextField {
                                id: limitField
                                enabled: limitEnabled.checked
                                validator: IntValidator { bottom: 1; top: 10000000 }
                                inputMethodHints: Qt.ImhDigitsOnly
                                placeholderText: qsTr("Enter a limit")
                                Accessible.name: qsTr("Maximum KB per second")
                            }
                            Label { text: qsTr("KB/s"); color: root.colors.muted }
                        }
                        GlassButton {
                            material: root.material
                            text: qsTr("Save speed limit")
                            enabled: !!root.item && !root.busy && (!limitEnabled.checked || limitField.acceptableInput)
                            onClicked: root.saveOptions("speed-limit", limitEnabled.checked ? limitField.text : "off", qsTr("Speed limit saved."))
                        }
                    }
                }

                Pane {
                    visible: root.activeTab === 2
                    Layout.fillWidth: true
                    padding: 14
                    background: GlassSurface { material: root.material; role: "card"; backdropAvailable: root.backdropAvailable }
                    contentItem: ColumnLayout {
                        spacing: 8
                        CheckBox { id: hangUp; text: qsTr("Disconnect on completion") }
                        CheckBox { id: closeApp; text: qsTr("Exit Auralis on completion") }
                        GlassComboBox { id: powerAction; model: [qsTr("Keep computer on"), qsTr("Shut down"), qsTr("Sleep"), qsTr("Hibernate")] }
                        CheckBox { id: forceAction; enabled: powerAction.currentIndex > 0; text: qsTr("Force the power action") }
                        GlassButton {
                            material: root.material
                            text: qsTr("Save completion action")
                            enabled: !!root.item && !root.busy
                            onClicked: root.saveOptions("completion-options", JSON.stringify({hang_up: hangUp.checked,
                                exit: closeApp.checked, turn_off: [null, "ShutDown", "Sleep", "Hibernate"][powerAction.currentIndex],
                                force: powerAction.currentIndex > 0 && forceAction.checked}), qsTr("Completion action saved."))
                        }
                    }
                }

                Label {
                    visible: root.message !== "" && root.activeTab !== root.recoveryTab
                    Layout.fillWidth: true
                    text: root.message
                    textFormat: Text.PlainText
                    color: root.error ? root.colors.destructive : root.colors.text
                    wrapMode: Text.WordWrap
                }
            }

            TransferTubes {
                width: Math.min(parent.width, waterWorkers.count > 0 ? waterGrid.width + 52 : 34)
                height: parent.height
                visible: root.displayFlow
                sourceItem: transferSource
                progressItem: downloadProgress
                gridItem: waterGrid
                workers: waterWorkers
                phase: water.phase
                paintingPaused: root.interactiveFrame
                flowing: root.showWaterFlow
                progressStart: root.progressColors[0]
                progressEnd: root.progressColors[1]
                connectionStart: root.connectionColors[0]
                connectionEnd: root.connectionColors[1]
            }
        }
    }

    DetachedConfirmation {
        id: stopConsent
        hostWindow: root
        material: root.material
        title: qsTr("Stop this download?")
        message: qsTr("Saved data will be kept so the download can resume.")
        confirmText: qsTr("Stop download")
        onConfirmed: root.perform("pause", true)
    }
    DetachedConfirmation {
        id: restartConsent
        hostWindow: root
        material: root.material
        title: qsTr("Download from the beginning?")
        message: qsTr("This discards the saved partial and starts a new download.")
        confirmText: qsTr("Redownload")
        destructive: true
        onConfirmed: root.saveOptions("redownload", null, qsTr("Restarting the download…"))
    }
    DetachedConfirmation {
        id: searchConsent
        hostWindow: root
        material: root.material
        title: qsTr("Search for a matching torrent?")
        message: qsTr("Searching sends filename terms to Internet Archive. A piece match only verifies the compared bytes.")
        confirmText: qsTr("Search")
        onConfirmed: root.beginCheck("find-recovery-torrents", null, qsTr("Searching Internet Archive…"))
    }
    DetachedConfirmation {
        id: linkConsent
        hostWindow: root
        material: root.material
        title: qsTr("Check this torrent source?")
        message: /^magnet:/i.test(link.text.trim())
            ? qsTr("Checking the magnet contacts BitTorrent peers. A match verifies only the pieces compared.")
            : qsTr("Checking the torrent URL contacts its host. A match verifies only the pieces compared.")
        confirmText: qsTr("Check source")
        onConfirmed: root.beginCheck(/^magnet:/i.test(link.text.trim()) ? "check-recovery-magnet" : "check-recovery-torrent-url",
            link.text.trim(), qsTr("Checking the supplied torrent metadata…"))
    }
    DetachedDialogWindow {
        id: addressPrompt
        hostWindow: root
        material: root.material
        title: qsTr("Update download address")
        width: 485
        onDismissRequested: hide()
        onOpened: updatedAddress.forceActiveFocus()
        onDismissed: updatedAddress.clear()
        function saveAddress() {
            const address = updatedAddress.text.trim()
            if (!/^(https?|ftp):\/\//i.test(address)) {
                addressError.text = qsTr("Enter a valid download address.")
                return
            }
            hide()
            root.saveOptions("refresh-address", address, qsTr("Download address updated. Saved bytes were kept."))
        }
        bodyContent: [
            Label {
                Layout.fillWidth: true
                text: qsTr("Saved bytes are kept. Use an address for the same file.")
                color: root.colors.ink
                wrapMode: Text.WordWrap
            },
            TextField {
                id: updatedAddress
                Layout.fillWidth: true
                selectByMouse: true
                Accessible.name: qsTr("New download address")
                placeholderText: qsTr("New download address")
                maximumLength: 8192
                color: root.colors.ink
                background: GlassSurface { material: root.material; role: "field" }
                onAccepted: addressPrompt.saveAddress()
                onTextChanged: addressError.text = ""
            },
            Label {
                id: addressError
                Layout.fillWidth: true
                visible: text.length > 0
                color: root.colors.destructive
                wrapMode: Text.Wrap
            }
        ]
        footer: Item {
            implicitHeight: addressActions.implicitHeight + 20
            GlassSurface { anchors.fill: parent; material: root.material; role: "footer" }
            RowLayout {
                id: addressActions
                anchors.fill: parent
                anchors.margins: 10
                Item { Layout.fillWidth: true }
                GlassButton { material: root.material; text: qsTr("Cancel"); onClicked: addressPrompt.hide() }
                GlassButton { material: root.material; accent: root.colors.positive; text: qsTr("Update address"); onClicked: addressPrompt.saveAddress() }
            }
        }
    }
    FileDialog {
        id: movePicker
        title: qsTr("Move download to an unused file name")
        fileMode: FileDialog.SaveFile
        onAccepted: root.saveOptions("move", engine.localPath(selectedFile), qsTr("Moving the downloaded file…"))
    }
    FileDialog {
        id: recoveryFile
        title: qsTr("Choose a torrent to compare")
        nameFilters: [qsTr("Torrent files (*.torrent)")]
        onAccepted: {
            const id = root.downloadId
            root.busy = true
            root.candidates = []
            risk.checked = false
            engine.request({action: "glass-recovery-torrent-file", ids: [id], dir: engine.localPath(selectedFile)}, function (reply, transportError) {
                if (String(root.downloadId) !== String(id))
                    return
                root.busy = false
                const issue = Transfer.problem(reply, transportError)
                if (issue)
                    root.say(issue, true)
                else {
                    root.say(qsTr("Comparing saved data with the torrent file…"), false)
                    root.pendingResult = "find-recovery-torrents-result"
                    root.pollResult()
                }
            })
        }
    }
}
