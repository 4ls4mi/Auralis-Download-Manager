pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window
import QtCore
import "TransferData.js" as Transfer
import "MaterialGeometry.js" as Geometry

AuralisWindow {
    id: root
    objectName: "downloadProgressWindow"
    property var downloadId: null
    property bool trayEnabled: false
    property bool minimizeToTray: false
    signal hideToTrayRequested(var downloadId)
    property string material: MaterialTheme.current
    readonly property int resizeInset: 14
    readonly property int panelInset: 8
    readonly property int outerPanelInset: Math.max(panelInset, frameSafeInset)
    readonly property int bodyBottomInset: Math.max(resizeInset, outerPanelInset)
    readonly property var colors: MaterialTheme.profile(material)
    readonly property string transferLayout: colors.layout || ""
    readonly property bool sideTabs: ["fogSlate", "violetRail", "coralSlate"].includes(transferLayout)
    readonly property bool compactWidth: width < 670
    readonly property bool compactHeight: height < 470
    readonly property bool compactView: transferWindowSettings.compactView
    readonly property bool classicPreset: MaterialTheme.isMdmPreset(material)
    readonly property bool classicFullView: classicPreset && !compactView
    readonly property color classicPageFace: colors.contentOverride || colors.mdm?.tabPage
        || colors.roleFaces?.card || colors.background
    readonly property bool railTabs: !compactView && sideTabs && !compactWidth && height >= 420
    readonly property bool useCompactActions: compactView || (compactHeight && !classicFullView)
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
    readonly property real connectionBlockScale: (WindowAppearance.connectionBlockSize ?? 100) / 100
    readonly property var item: Transfer.find(engine.dashboard.downloads, downloadId)
    readonly property var telemetry: Transfer.find(engine.visuals.downloads, downloadId)
    readonly property bool transferPaused: !!item && item.status === "Stopped"
    readonly property var workerRows: {
        if (torrent || !telemetry)
            return []
        const observed = telemetry.connections || []
        if (observed.length || !transferPaused)
            return observed.slice(0, 32)
        // A restarted app has no live meters for a paused file. Its configured
        // slots can still show Paused, without guessing per-connection progress.
        const slots = Math.max(0, Math.min(32, Number(telemetry.chunk_count) || 0))
        return Array.from({length: slots}, (_, id) => ({id}))
    }
    readonly property var torrent: telemetry && telemetry.torrent ? telemetry.torrent : null
    readonly property bool mixed: !!(telemetry && telemetry.direct_recovery)
    readonly property bool ordinary: !!(telemetry && !telemetry.is_torrent && !telemetry.is_video && !telemetry.is_gallery && !telemetry.is_remote)
    readonly property bool runningTransfer: !!(item && item.status === "Downloading")
    readonly property bool feedingConnections: runningTransfer && workerRows.some(connectionHasData)
    readonly property bool displayFlow: !classicPreset && activeTab === 0 && !!item && !!item.url
    readonly property bool displayConnectionFlow: displayFlow && workerRows.length > 0
    readonly property real pipeScale: compactView ? .68 : 1
    readonly property int pipeInset: Math.round(32 * pipeScale)
    readonly property bool interactiveFrame: resizeHandles.resizing || downloadCaption.dragging
    readonly property bool animateTransfer: visible && visibility !== Window.Minimized && activeTab === 0
        && runningTransfer && !interactiveFrame
    readonly property bool showWaterFlow: displayFlow && animateTransfer
    readonly property var progressColors: MaterialTheme.progressColors
    readonly property var connectionColors: MaterialTheme.connectionColors
    readonly property bool finished: !!(item && item.status === "Complete")
    readonly property bool recoveryAvailable: !!item && ordinary && !runningTransfer && !finished
    readonly property string recoveryStage: telemetry && telemetry.recovery_stage || ""
    readonly property bool recoveryBusy: !!pendingResult || recoveryStage === "searching" || recoveryStage === "preparing"
    readonly property bool canOpenAddressEditor: recoveryAvailable && !busy && !recoveryBusy
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
    property bool classicDetailsVisible: true
    property real classicExpandedHeight: 442
    property size expandedWindowSize: classicPreset ? Qt.size(546, 442) : Qt.size(790, 625)
    property size compactWindowSize: Qt.size(transferWindowSettings.initialCompactWidth,
                                             transferWindowSettings.initialCompactHeight)

    function connectionHasData(connection) {
        return connection.state === "Receiving" && connection.receiving_data !== false
    }

    width: expandedWindowSize.width
    height: expandedWindowSize.height
    minimumWidth: compactView ? 395 : 450
    minimumHeight: compactView || (classicFullView && !classicDetailsVisible) ? 270 : 340
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    transientParent: null
    palette.windowText: colors.text
    palette.text: colors.text
    palette.buttonText: colors.text
    palette.base: colors.background
    palette.highlight: colors.accent
    title: item ? Math.round(Transfer.fraction(item) * 100) + "%  " + item.file : qsTr("Download details")

    Settings {
        id: transferWindowSettings
        category: "TransferWindowLayout"
        property bool compactView: false
        property int initialCompactWidth: 510
        property int initialCompactHeight: 290
    }

    Component.onCompleted: {
        if (compactView)
            applyViewSize(true)
    }

    function applyViewSize(compact) {
        Qt.callLater(() => {
            if (root.compactView !== compact || (root.visibility !== Window.Windowed && root.visibility !== Window.Hidden))
                return
            const size = compact ? root.compactWindowSize : root.expandedWindowSize
            root.setGeometry(root.x, root.y, size.width, size.height)
        })
    }

    function setCompactView(compact) {
        if (compact === compactView)
            return
        if (visibility === Window.Windowed) {
            const size = Qt.size(width, height)
            if (compactView)
                compactWindowSize = size
            else
                expandedWindowSize = size
        }
        if (visibility === Window.Maximized)
            showNormal()
        if (compact)
            activeTab = 0
        transferWindowSettings.compactView = compact
        applyViewSize(compact)
    }

    function toggleClassicDetails() {
        if (visibility === Window.Windowed && classicDetailsVisible)
            classicExpandedHeight = height
        classicDetailsVisible = !classicDetailsVisible
        Qt.callLater(() => {
            if (root.classicFullView && root.visibility === Window.Windowed) {
                const contentHeight = root.header.height + sections.implicitHeight + root.bodyBottomInset
                root.height = Math.max(root.minimumHeight,
                    root.classicDetailsVisible ? root.classicExpandedHeight : Math.ceil(contentHeight))
            }
        })
    }

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

    function openAddressEditor() {
        if (!canOpenAddressEditor)
            return
        if (!addressPrompt.visible)
            updatedAddress.text = item.url
        addressPrompt.open()
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
        spacing: 3
        ToolBar {
            Layout.fillWidth: true
            padding: 0
            leftPadding: root.outerPanelInset + (root.classicFullView ? 3 : 8)
            rightPadding: root.outerPanelInset + (root.classicFullView ? 3 : 8)
            topPadding: root.classicFullView ? 0 : root.panelInset
            bottomPadding: 2
            leftInset: root.classicFullView ? 0 : root.outerPanelInset
            rightInset: leftInset
            topInset: topPadding
            bottomInset: 2
            background: GlassSurface { material: root.material; role: "title"; roundedPanel: !root.classicFullView; backdropAvailable: root.backdropAvailable }
            contentItem: RowLayout {
                spacing: 7
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.classicFullView ? 29 : root.compactView ? 36 : 43
                    BrandMark {
                        id: transferBrand
                        width: root.classicFullView ? 16 : implicitWidth
                        height: root.classicFullView ? 16 : implicitHeight
                        anchors.left: parent.left
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
                        font.family: root.fontFamilyForText(text)
                        font.weight: root.classicFullView ? Font.Normal : Font.DemiBold
                        color: root.colors.titleInk || root.colors.mdm?.captionText || root.colors.ink
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
                GlassButton {
                    id: compactButton
                    objectName: "toggleCompactTransferView"
                    material: root.material
                    readonly property string viewLabel: root.compactView ? qsTr("Full view") : qsTr("Compact view")
                    readonly property string viewHint: root.compactView ? qsTr("Return to the full layout")
                        : qsTr("Switch to the compact layout")
                    Layout.preferredHeight: root.classicFullView ? 25 : 30
                    text: viewLabel
                    font.weight: Font.DemiBold
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
                            visible: root.width >= 420
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
                    onClicked: root.setCompactView(!root.compactView)
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
            }
        }
        ToolBar {
            objectName: "transferCommands"
            visible: !root.compactView && (root.finished || (root.recoveryAvailable && root.activeTab !== root.recoveryTab))
            Layout.fillWidth: true
            leftPadding: root.panelInset + 8
            rightPadding: root.panelInset + 8
            topPadding: 7
            bottomPadding: 7
            leftInset: root.panelInset
            rightInset: root.panelInset
            background: GlassSurface { material: root.material; role: "toolbar"; roundedPanel: true; backdropAvailable: root.backdropAvailable }
            contentItem: Flow {
                id: transferCommandFlow
                spacing: 7
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
        TabBar {
            id: desktopTransferTabs
            objectName: "classicTransferTabs"
            visible: root.classicFullView
            Layout.fillWidth: true
            Layout.leftMargin: root.outerPanelInset + 8
            Layout.rightMargin: root.resizeInset
            spacing: 1
            currentIndex: root.activeTab
            onCurrentIndexChanged: if (currentIndex >= 0 && currentIndex !== root.activeTab)
                                       root.activeTab = currentIndex

            background: Rectangle {
                y: parent.height - 1
                width: parent.width
                height: 1
                color: root.detailDivider
            }

            Repeater {
                model: root.transferTabs
                delegate: TabButton {
                    id: desktopTransferTab
                    required property string modelData
                    text: modelData
                    width: implicitWidth
                    leftPadding: 7
                    rightPadding: 7
                    topPadding: 3
                    bottomPadding: 3
                    font.pixelSize: TypographyScale.pixels(11)
                    readonly property color face: checked ? root.classicPageFace
                        : hovered ? root.colors.mdm?.tabHot || root.colors.background
                        : root.colors.mdm?.tab || root.colors.background
                    palette.buttonText: MaterialTheme.controlTextInk(root.colors.ink, face)
                    background: Rectangle {
                        color: desktopTransferTab.face
                        border.width: 1
                        border.color: desktopTransferTab.visualFocus ? root.colors.accent : root.detailDivider
                        radius: Math.min(3, root.colors.buttonRadius || root.colors.radius)
                    }
                }
            }
        }
        ToolBar {
            visible: !root.classicFullView && !root.railTabs && (!root.compactView || root.activeTab !== 0)
            Layout.fillWidth: true
            padding: root.compactHeight ? 5 : 8
            leftPadding: root.panelInset + 8
            rightPadding: root.panelInset + 8
            leftInset: root.panelInset
            rightInset: root.panelInset
            background: GlassSurface { material: root.material; role: "toolbar"; roundedPanel: true; backdropAvailable: root.backdropAvailable }
            contentItem: Flow {
                spacing: root.compactWidth ? 5 : 7
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

    FrameAnimation {
        id: water
        property real phase: 0
        property real slowPhase: 0
        property real progressPhase: 0
        property real activeSeconds: 0
        property real nextPaint: 0
        // Keep both eight- and sixteen-connection grids at display cadence.
        readonly property real paintInterval: 1 / (root.workerRows.length > 16 ? 45 : 60)
        readonly property bool animateConnections: WindowAppearance.connectionAnimation !== "none"
            && root.feedingConnections
        readonly property bool animateProgressPipe: root.displayFlow && WindowAppearance.progressAnimation !== "none"
        running: root.animateTransfer && !MaterialTheme.reducedMotion && (animateConnections || animateProgressPipe)
        onRunningChanged: nextPaint = activeSeconds
        onPaintIntervalChanged: nextPaint = activeSeconds
        onTriggered: {
            activeSeconds += frameTime
            const sample = activeSeconds + .002
            // Render each ordinary display frame. Only sample that clock on
            // very fast displays or when a larger connection grid costs more.
            const sampleFrames = root.workerRows.length > 16 || smoothFrameTime < 1 / 75
            if (sampleFrames && sample < nextPaint)
                return
            nextPaint = (Math.floor(sample / paintInterval) + 1) * paintInterval
            const turn = Math.PI * 2
            phase = activeSeconds % 1.72 / 1.72 * turn
            if (WindowAppearance.progressAnimation === "water")
                progressPhase = activeSeconds % 1.48 / 1.48 * turn
            if (WindowAppearance.connectionAnimation === "jelly" || WindowAppearance.progressAnimation === "jelly")
                slowPhase = activeSeconds % 3.7 / 3.7 * turn
        }
    }

    Pane {
        id: transferRail
        visible: root.railTabs
        anchors.top: parent.top
        anchors.topMargin: root.panelInset
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.bodyBottomInset
        anchors.left: parent.left
        anchors.leftMargin: root.panelInset
        width: root.transferLayout === "violetRail"
            ? Math.max(122, Math.min(169, Math.round(root.width * .21)))
            : Math.max(115, Math.min(145, Math.round(root.width * .19)))
        padding: 9
        topPadding: root.transferLayout === "violetRail" ? 19 : padding
        background: GlassSurface {
            material: root.material
            role: "sidebar"
            roundedPanel: true
            backdropAvailable: root.backdropAvailable
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

    Pane {
        id: compactActions
        visible: root.useCompactActions
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.outerPanelInset
        anchors.rightMargin: root.outerPanelInset
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.resizeInset
        implicitHeight: downloadActions.implicitHeight + topPadding + bottomPadding
        padding: root.compactView ? 4 : 6
        background: GlassSurface {
            material: root.material
            role: root.colors.footerOverride ? "footer" : "toolbar"
            roundedPanel: true
            backdropAvailable: root.backdropAvailable
        }
    }

    GridLayout {
        id: downloadActions
        objectName: "downloadActionGroup"
        parent: root.useCompactActions ? compactActions.contentItem : inlineActionArea
        anchors.centerIn: parent
        width: parent ? (root.classicFullView ? parent.width : Math.min(implicitWidth, parent.width)) : implicitWidth
        readonly property real actionWidth: [classicDetailsToggle, pauseResume, openFile, openFolder, stopClose]
            .filter(button => button.parent === downloadActions && button.visible)
            .reduce((total, button) => total + Math.max(button.Layout.minimumWidth, button.implicitWidth) + columnSpacing,
                -columnSpacing)
        columns: root.classicFullView ? (parent && parent.width < actionWidth + columnSpacing ? 2 : 4)
            : parent && parent.width < actionWidth ? (root.compactView && parent.width >= 223 ? 2 : 1)
            : root.compactView ? 3 : 2
        columnSpacing: root.classicFullView ? 7 : root.compactView ? 5 : 9
        rowSpacing: root.classicFullView || root.compactView ? 4 : 6

        GlassButton {
            id: classicDetailsToggle
            objectName: "toggleClassicTransferDetails"
            visible: root.classicFullView && !!root.item
            material: root.material
            text: root.classicDetailsVisible ? qsTr("<< Hide details") : qsTr("Show details >>")
            Layout.preferredHeight: 23
            Layout.minimumWidth: 120
            topPadding: 2
            bottomPadding: 2
            onClicked: root.toggleClassicDetails()
        }
        Item {
            visible: root.classicFullView && downloadActions.columns === 4
            Layout.fillWidth: true
        }

        GlassButton {
            id: pauseResume
            objectName: "pauseOrResumeDownload"
            material: root.material
            text: root.runningTransfer ? qsTr("Pause") : root.item && root.item.status === "Queued" ? qsTr("Start") : qsTr("Resume")
            visible: !!root.item && !root.finished
            enabled: !root.busy && (root.runningTransfer || (!root.recoveryBusy && !(root.telemetry && root.telemetry.recovery_damaged)))
            Layout.minimumWidth: 96
            Layout.minimumHeight: root.classicFullView ? 23 : root.compactView ? 32 : 36
            Layout.preferredHeight: root.classicFullView ? 23 : implicitHeight
            topPadding: root.classicFullView ? 2 : 7
            bottomPadding: topPadding
            filled: !root.classicFullView
            accent: MaterialTheme.actionColor(root.runningTransfer ? "pause" : "start", root.colors.light)
            onClicked: root.perform(root.runningTransfer ? "pause" : "start", false)
        }
        GlassButton {
            id: openFolder
            objectName: "openDownloadFolder"
            parent: root.compactView ? downloadActions : transferCommandFlow
            Layout.minimumHeight: 32
            material: root.material
            text: qsTr("Open folder")
            enabled: !!root.item
            onClicked: root.openLocation(true)
        }
        GlassButton {
            id: openFile
            objectName: "openDownloadedFile"
            parent: root.compactView ? downloadActions : transferCommandFlow
            Layout.minimumHeight: 32
            material: root.material
            text: qsTr("Open file")
            visible: root.finished
            accent: root.colors.positive
            onClicked: root.openLocation(false)
        }
        GlassButton {
            id: stopClose
            objectName: "stopOrCloseDownload"
            material: root.material
            text: root.runningTransfer ? qsTr("Cancel…") : qsTr("Close")
            Layout.minimumWidth: 96
            Layout.minimumHeight: root.classicFullView ? 23 : root.compactView ? 32 : 36
            Layout.preferredHeight: root.classicFullView ? 23 : implicitHeight
            topPadding: root.classicFullView ? 2 : 7
            bottomPadding: topPadding
            accent: root.runningTransfer ? root.colors.destructive : root.colors.accent
            onClicked: root.runningTransfer ? stopConsent.open() : root.close()
        }
    }

    component ClassicTransferPage: Rectangle {
        color: root.classicPageFace
        border.color: root.detailDivider
        border.width: 1
    }

    component ClassicConnectionCells: RowLayout {
        id: cells

        required property string number
        required property string downloaded
        required property string info
        property bool heading: false
        readonly property color ink: heading
            ? MaterialTheme.controlTextInk(root.colors.text, root.colors.mdm?.header || root.colors.background)
            : root.colors.text

        spacing: 0
        Label {
            Layout.preferredWidth: 30
            leftPadding: 5
            text: cells.number
            color: cells.ink
            font.pixelSize: TypographyScale.pixels(11)
        }
        NumeralLabel {
            Layout.preferredWidth: 98
            leftPadding: 5
            valueText: cells.downloaded
            color: cells.ink
            font.pixelSize: TypographyScale.pixels(11)
            elide: Text.ElideRight
        }
        Label {
            Layout.fillWidth: true
            leftPadding: 5
            rightPadding: 6
            text: cells.info
            elide: Text.ElideRight
            color: cells.ink
            font.pixelSize: TypographyScale.pixels(11)
        }
    }

    ScrollView {
        id: view
        objectName: "downloadDetailsScroll"
        anchors.top: parent.top
        anchors.topMargin: root.classicFullView ? 0 : root.panelInset
        anchors.bottom: root.useCompactActions ? compactActions.top : parent.bottom
        anchors.bottomMargin: root.useCompactActions ? root.panelInset : root.bodyBottomInset
        anchors.left: root.railTabs ? transferRail.right : parent.left
        anchors.leftMargin: root.classicFullView ? root.outerPanelInset + 8 : root.railTabs ? 0 : root.panelInset
        anchors.right: parent.right
        anchors.rightMargin: root.resizeInset
        clip: true
        padding: root.classicFullView ? 0 : root.compactView ? 5 : root.compactWidth || root.compactHeight ? 7 : root.transferLayout === "fogSlate" ? 10 : 12
        contentWidth: availableWidth
        contentHeight: scrollContent.implicitHeight
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical: ScrollBar {
            id: detailsScrollBar
            policy: ScrollBar.AsNeeded
            implicitWidth: 7
            padding: 1
            contentItem: Rectangle {
                implicitWidth: 5
                radius: 2.5
                color: root.colors.secondary
                opacity: detailsScrollBar.active ? .86 : .60
            }
            background: Item {}
        }
        Item {
            id: scrollContent
            width: view.availableWidth
            height: implicitHeight
            implicitHeight: sections.implicitHeight

            ColumnLayout {
                id: sections
                anchors.fill: parent
                spacing: root.classicFullView ? 5 : root.compactView ? 4 : root.compactWidth || root.compactHeight ? 6 : 8

                Label {
                    visible: !root.item
                    text: qsTr("Waiting for download information…")
                    color: root.colors.muted
                }

                Pane {
                    objectName: "downloadStatusCard"
                    visible: !!root.item && root.activeTab === 0
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    padding: root.compactView ? 5 : root.compactWidth || root.compactHeight ? 8 : root.transferLayout === "fogSlate" ? 11 : 13
                    leftPadding: root.displayFlow ? root.pipeInset : padding
                    background: Item {
                        ClassicTransferPage {
                            anchors.fill: parent
                            visible: root.classicFullView
                        }
                        GlassSurface {
                            anchors.fill: parent
                            visible: !root.classicFullView
                            material: root.material
                            role: root.sideTabs ? "summary" : "card"
                            backdropAvailable: root.backdropAvailable
                        }
                        TransferTubes {
                            objectName: "downloadProgressInlet"
                            sizeScale: root.pipeScale
                            LayoutMirroring.enabled: false
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: Math.min(parent.width, root.pipeInset + Math.round(17 * root.pipeScale))
                            visible: root.displayFlow
                            progressItem: downloadProgress
                            phase: water.phase
                            slowPhase: water.slowPhase
                            progressPhase: water.progressPhase
                            paintingPaused: root.interactiveFrame
                            flowing: root.showWaterFlow
                            progressAnimation: WindowAppearance.progressAnimation
                            progressLighting: WindowAppearance.progressLighting
                            progressStart: root.progressColors[0]
                            progressEnd: root.progressColors[1]
                            channelColor: root.colors.background
                            channelEdge: root.detailDivider
                        }
                    }
                    contentItem: ColumnLayout {
                        id: statusCardContent
                        spacing: root.classicFullView ? 2 : root.compactView ? 3 : root.compactWidth || root.compactHeight ? 5 : 8
                        Label {
                            id: transferName
                            visible: !root.classicFullView
                            Layout.fillWidth: true
                            text: root.item ? root.item.file : ""
                            textFormat: Text.PlainText
                            elide: Text.ElideMiddle
                            color: root.summaryInk
                            font.family: root.fontFamilyForText(text)
                            font.pixelSize: TypographyScale.pixels(root.compactView ? 16 : 19)
                            font.bold: true
                        }
                        Label {
                            id: transferSource
                            visible: !root.compactView
                            Layout.fillWidth: true
                            text: root.item ? root.item.url : ""
                            textFormat: Text.PlainText
                            elide: Text.ElideMiddle
                            color: root.classicFullView ? root.colors.text : root.colors.muted
                        }
                        GridLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            columns: !root.classicFullView && width >= (root.compactView ? 300 : 432) ? 2 : 1
                            rowSpacing: root.classicFullView ? 0 : root.compactView ? 2 : root.compactWidth || root.compactHeight ? 4 : 6
                            columnSpacing: root.compactView ? 6 : root.compactWidth ? 9 : 14
                            Repeater {
                                id: measurements
                                property var cells: {
                                    const d = root.item || {}
                                    const t = root.telemetry || {}
                                    const server = t.server || {}
                                    const cells = [
                                        {label: qsTr("Status"), value: Transfer.statusLabel(d.status)},
                                        {label: qsTr("Transfer method"), value: root.mixed ? qsTr("Direct → BitTorrent") : t.is_torrent ? qsTr("BitTorrent") : t.is_video ? qsTr("Video") : qsTr("Direct download"), optional: true},
                                        {label: qsTr("Downloaded"), value: Transfer.bytes(d.downloaded) + " / " + Transfer.bytes(d.size)},
                                        {label: qsTr("Transfer rate"), value: Transfer.rate(d.speed)},
                                        {label: qsTr("Time left"), value: Transfer.timeLeft(d)},
                                        {label: qsTr("Resume capability"), value: t.resumable === true ? qsTr("Yes") : t.resumable === false ? qsTr("No") : qsTr("Unknown"), optional: true},
                                        {label: root.torrent ? qsTr("Connected peers") : qsTr("Server"), value: root.torrent ? String(root.torrent.peers || 0)
                                            : (server.place && server.place.name || server.country_code || server.hostname || "—") + (server.rtt_ms != null ? " · " + server.rtt_ms + " ms" : ""), optional: !root.torrent}
                                    ]
                                    if (root.classicFullView) {
                                        let status = cells[0].value
                                        if (root.runningTransfer) {
                                            if (d.size > 0 && d.downloaded >= d.size)
                                                status = qsTr("Finishing…")
                                            else if (root.feedingConnections || d.speed > 0)
                                                status = qsTr("Receiving data…")
                                            else
                                                status = qsTr("Connecting…")
                                        }
                                        const downloaded = Transfer.bytes(d.downloaded)
                                        const amount = d.size > 0
                                            ? qsTr("%1 (%2%)").arg(downloaded).arg((100 * Transfer.fraction(d)).toFixed(2))
                                            : downloaded
                                        return [{label: cells[0].label, value: status, status: true},
                                            {label: qsTr("File size"), value: Transfer.bytes(d.size)},
                                            {label: cells[2].label, value: amount}, cells[3], cells[4], cells[5], cells[6]]
                                    }
                                    return root.compactView ? cells.filter(cell => !cell.optional) : cells
                                }
                                model: cells.length
                                delegate: RowLayout {
                                    id: measurement
                                    required property int index
                                    readonly property var cell: measurements.cells[index]
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    spacing: root.compactView ? 4 : 7
                                    Label {
                                        Layout.minimumWidth: 0
                                        Layout.preferredWidth: root.classicFullView ? 102 : root.compactView ? 82 : root.compactWidth ? 106 : 115
                                        text: measurement.cell.label
                                        color: root.classicFullView ? root.colors.text : root.colors.muted
                                        wrapMode: Text.Wrap
                                    }
                                    NumeralLabel {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        valueText: measurement.cell.value
                                        color: measurement.cell.status ? MaterialTheme.controlTextInk(
                                            root.colors.mdm?.statusValue || root.colors.accent,
                                            root.classicPageFace) : root.summaryInk
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }
                        }
                        Item {
                            id: progressLine
                            parent: root.classicFullView ? classicProgressArea : statusCardContent
                            anchors.fill: root.classicFullView ? parent : undefined
                            LayoutMirroring.enabled: false
                            LayoutMirroring.childrenInherit: true
                            Layout.fillWidth: true
                            implicitHeight: Math.max(downloadProgress.height, progressPercent.implicitHeight)
                            GlassProgress {
                                id: downloadProgress
                                objectName: "detailProgressShape"
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, progressLine.width - progressPercent.width - progressPercent.anchors.leftMargin)
                                baseHeight: root.classicFullView ? 18 : root.compactView ? 18 : 26
                                height: implicitHeight
                                value: Transfer.fraction(root.item)
                                transferState: String(root.item?.status || "")
                                animated: root.animateTransfer
                                animationStyle: WindowAppearance.progressAnimation
                                externalPhase: !root.displayFlow ? -1
                                    : animationStyle === "water" ? water.progressPhase
                                    : animationStyle === "jelly" ? water.slowPhase : -1
                                lightingStyle: WindowAppearance.progressLighting
                                shape: root.progressShape
                                startColor: root.progressColors[0]
                                endColor: root.progressColors[1]
                                trackColor: root.colors.background
                                material: root.material
                                Accessible.name: qsTr("Download progress")
                            }
                            NumeralLabel {
                                id: progressPercent
                                anchors.left: downloadProgress.right
                                anchors.leftMargin: 5
                                anchors.verticalCenter: parent.verticalCenter
                                valueText: Math.round(Transfer.fraction(root.item) * 100) + "%"
                                color: root.summaryInk
                                font.bold: true
                            }
                        }
                        NumeralLabel {
                            visible: root.mixed && !root.compactView
                            Layout.fillWidth: true
                            color: root.colors.positive
                            wrapMode: Text.WordWrap
                            valueText: root.mixed && root.telemetry.original_partial
                                  ? qsTr("Original direct partial kept at %1").arg(root.telemetry.original_partial) : ""
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

                ColumnLayout {
                    id: classicOptionPages
                    visible: root.classicFullView && root.activeTab !== 0
                    Layout.fillWidth: true
                    spacing: 0
                }

                Item {
                    id: classicProgressArea
                    visible: root.classicFullView && !!root.item
                    Layout.fillWidth: true
                    implicitHeight: progressLine.implicitHeight
                }

                Item {
                    id: inlineActions
                    visible: !root.useCompactActions
                    Layout.fillWidth: true
                    implicitHeight: visible ? downloadActions.implicitHeight + 1 : 0
                    Item {
                        id: inlineActionArea
                        anchors.fill: parent
                        anchors.leftMargin: root.displayConnectionFlow ? root.pipeInset : 0
                        anchors.rightMargin: anchors.leftMargin
                    }
                }

                GridLayout {
                    id: transferOverview
                    objectName: "transferOverview"
                    // Keep the chart and vessel coordinates aligned with the physical pipe gutter.
                    LayoutMirroring.enabled: false
                    LayoutMirroring.childrenInherit: true
                    visible: !!root.item && (root.classicFullView ? root.classicDetailsVisible : root.activeTab === 0)
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    columns: root.classicFullView ? 1 : root.compactView ? (connectionPane.visible && width >= 345 ? 2 : 1)
                        : root.transferLayout !== "coralSlate" && width >= (root.railTabs ? 560 : 585) ? 2 : 1
                    columnSpacing: root.compactView ? 5 : 8
                    rowSpacing: root.compactView ? 4 : root.compactWidth || root.compactHeight ? 6 : 8
                    Pane {
                        id: connectionPane
                        objectName: "downloadConnectionPane"
                        visible: !root.compactView || !!root.torrent || root.workerRows.length > 0 || Boolean(root.colors.mdm)
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: root.compactView ? 1 : root.transferLayout === "violetRail" ? 315 : 355
                        Layout.alignment: Qt.AlignTop
                        padding: root.classicFullView ? 0 : root.compactView ? 5 : root.compactWidth || root.compactHeight ? 8 : 11
                        leftPadding: root.displayConnectionFlow ? root.pipeInset : padding
                        background: Item {
                            GlassSurface {
                                anchors.fill: parent
                                material: root.material
                                role: root.sideTabs ? "connections" : "card"
                                backdropAvailable: root.backdropAvailable
                            }
                            TransferTubes {
                                id: transferTubes
                                objectName: "downloadTransferTubes"
                                sizeScale: root.pipeScale
                                anchors.fill: parent
                                visible: root.displayConnectionFlow
                                gridItem: waterGrid
                                workers: waterWorkers
                                phase: water.phase
                                slowPhase: water.slowPhase
                                paintingPaused: root.interactiveFrame
                                flowing: root.showWaterFlow
                                connectionAnimation: WindowAppearance.connectionAnimation
                                connectionLighting: WindowAppearance.connectionLighting
                                connectionStart: root.connectionColors[0]
                                connectionEnd: root.connectionColors[1]
                                channelColor: root.colors.background
                                channelEdge: root.detailDivider
                            }
                        }
                        contentItem: ColumnLayout {
                            spacing: root.classicFullView || root.compactView ? 4 : 8
                            Label {
                                Layout.fillWidth: true
                                text: root.torrent ? qsTr("BitTorrent swarm") : root.classicFullView
                                    ? qsTr("Start positions and download progress by connections") : qsTr("Connections")
                                color: root.colors.text
                                horizontalAlignment: root.classicFullView ? Text.AlignHCenter : Text.AlignLeft
                                font.bold: !root.classicFullView
                                wrapMode: Text.WordWrap
                            }
                            NumeralLabel {
                                visible: !!root.torrent && !root.compactView
                                Layout.fillWidth: true
                                color: root.colors.muted
                                wrapMode: Text.WordWrap
                                valueText: root.torrent ? qsTr("Upload %1  ·  Sent %2\nInfo hash %3").arg(Transfer.rate(root.torrent.upload_speed)).arg(Transfer.bytes(root.torrent.uploaded)).arg(root.torrent.info_hash || "—") : ""
                            }
                            Label {
                                visible: !root.classicPreset && !root.compactView && !root.torrent && !(root.telemetry && root.telemetry.connections && root.telemetry.connections.length)
                                text: qsTr("No active connection data")
                                color: root.colors.muted
                            }
                            MdmSegmentMap {
                                visible: Boolean(root.colors.mdm) && !root.torrent
                                Layout.fillWidth: true
                                segments: root.telemetry?.segments || []
                                totalBytes: Number(root.telemetry?.total || 0)
                                paintingPaused: root.interactiveFrame
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: workerHeader.height + workerTable.height + 2
                                visible: root.classicFullView && !root.torrent
                                color: root.colors.mdm?.list || root.colors.background
                                border.color: root.detailDivider
                                border.width: 1

                                Item {
                                    id: workerHeader
                                    x: 1
                                    y: 1
                                    width: parent.width - 2
                                    height: workerHeaderCells.implicitHeight + 4
                                    Rectangle {
                                        anchors.fill: parent
                                        color: root.colors.mdm?.header || root.colors.background
                                    }
                                    ClassicConnectionCells {
                                        id: workerHeaderCells
                                        anchors.fill: parent
                                        heading: true
                                        number: qsTr("No.")
                                        downloaded: qsTr("Downloaded")
                                        info: qsTr("Info")
                                    }
                                }

                                ListView {
                                    id: workerTable
                                    objectName: "classicTransferConnections"
                                    anchors.top: workerHeader.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 1
                                    anchors.rightMargin: 1
                                    height: rowHeight * Math.max(1, Math.min(6, count))
                                    readonly property int rowHeight: TypographyScale.pixels(16)
                                    clip: true
                                    model: root.classicFullView ? root.workerRows : []
                                    ScrollBar.vertical: ScrollBar { id: workerScroll; policy: ScrollBar.AsNeeded }
                                    delegate: ClassicConnectionCells {
                                        required property var modelData
                                        width: workerTable.width - (workerScroll.visible ? workerScroll.width : 0)
                                        height: workerTable.rowHeight
                                        number: String(Number(modelData.id) + 1)
                                        downloaded: Transfer.bytes(modelData.downloaded)
                                        info: root.transferPaused ? qsTr("Paused")
                                            : modelData.state === "Receiving" && !root.connectionHasData(modelData) ? qsTr("Stalled")
                                            : Transfer.connectionLabel(modelData.state)
                                    }
                                    Label {
                                        visible: workerTable.count === 0
                                        anchors.fill: parent
                                        leftPadding: 5
                                        verticalAlignment: Text.AlignVCenter
                                        text: qsTr("No active connection data")
                                        color: root.colors.muted
                                        font.pixelSize: TypographyScale.pixels(11)
                                    }
                                }
                            }
                            GridLayout {
                                id: waterGrid
                                visible: !root.classicPreset
                                objectName: "downloadConnectionGrid"
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.topMargin: root.displayConnectionFlow ? Math.round(19 * root.pipeScale) : 0
                                readonly property int blockHeight: Math.round((root.compactView ? 23
                                    : root.compactWidth || root.compactHeight ? 34 : 39) * root.connectionBlockScale)
                                readonly property int blockWidth: Geometry.connectionBlockWidth(blockHeight)
                                // The grid's own width is capped by the cells it has already laid out.
                                // Measure the pane to determine how many columns fit.
                                columns: Math.max(1, Math.min(8,
                                    Math.floor((connectionPane.availableWidth + columnSpacing) / (blockWidth + columnSpacing))))
                                rowSpacing: root.displayConnectionFlow ? Math.round(26 * root.pipeScale) : 5
                                columnSpacing: root.compactView ? 3 : 4
                                Repeater {
                                    id: waterWorkers
                                    objectName: "downloadConnectionWorkers"
                                    model: root.classicPreset ? 0 : root.workerRows.length
                                    delegate: Item {
                                        id: worker
                                        required property int index
                                        readonly property var connection: root.workerRows[index] || {}
                                        readonly property var sample: {
                                            const row = connection
                                            return {key: String(root.downloadId) + "/" + row.id,
                                                receiving: root.runningTransfer && root.connectionHasData(row),
                                                amount: Transfer.assigned(row.id, root.telemetry && root.telemetry.segments, true)}
                                        }
                                        readonly property bool receiving: sample.receiving
                                        readonly property string connectionState: root.transferPaused ? qsTr("Paused")
                                            : connection.state === "Receiving" && !receiving ? qsTr("Stalled")
                                            : Transfer.connectionLabel(connection.state)
                                        readonly property string connectionHint: saved === null
                                            ? qsTr("Connection %1 · %2 · %3").arg(Number(connection.id) + 1)
                                                .arg(connectionState).arg(Transfer.rate(connection.speed))
                                            : qsTr("Connection %1 · %2 · %3 · %4%").arg(Number(connection.id) + 1)
                                                .arg(connectionState).arg(Transfer.rate(connection.speed)).arg(Math.round(saved * 100))
                                        property var retainedId: null
                                        property var saved: null
                                        readonly property real liquidSurface: chunkWater.landingY
                                        readonly property real liquidX: chunkWater.landingX
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        Layout.preferredWidth: waterGrid.blockWidth
                                        Layout.maximumWidth: waterGrid.blockWidth
                                        Layout.preferredHeight: Geometry.connectionBlockHeight(width, waterGrid.blockHeight)
                                        function retainReceivedFill() {
                                            if (retainedId !== sample.key) {
                                                retainedId = sample.key
                                                saved = null
                                            }
                                            // Released ranges may be shortened or reassigned. Keep the
                                            // last measured appearance of this connection while it is idle.
                                            if (sample.amount !== null && (sample.receiving || saved === null))
                                                saved = sample.amount
                                        }
                                        // Update after sample-dependent labels finish rebinding.
                                        onSampleChanged: Qt.callLater(retainReceivedFill)
                                        Component.onCompleted: retainReceivedFill()
                                        onReceivingChanged: transferTubes.requestPaint()
                                        ConnectionWater {
                                            id: chunkWater
                                            anchors.fill: parent
                                            material: root.material
                                            shape: root.connectionShape
                                            animationStyle: WindowAppearance.connectionAnimation
                                            lightingStyle: WindowAppearance.connectionLighting
                                            channelIndex: worker.index
                                            connected: root.displayConnectionFlow
                                            value: worker.saved
                                            paintingPaused: root.interactiveFrame
                                            receiving: worker.receiving
                                            interrupted: !worker.receiving
                                            paused: root.transferPaused
                                            phase: worker.receiving ? water.phase : 0
                                            slowPhase: worker.receiving ? water.slowPhase : 0
                                            startColor: root.connectionColors[0]
                                            endColor: root.connectionColors[1]
                                            trackColor: root.colors.background
                                        }
                                        NumeralLabel {
                                            anchors.left: parent.left
                                            anchors.leftMargin: root.compactView ? 2 : 4
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: root.compactView ? 2 : 3
                                            color: root.colors.text
                                            style: Text.Outline
                                            styleColor: root.colors.shade
                                            valueText: Number(worker.connection.id) + 1
                                            font.pixelSize: TypographyScale.pixels(root.compactView ? 9 : 11)
                                        }
                                        HoverHandler { id: workerHover }
                                        ToolTip.visible: workerHover.hovered
                                        ToolTip.text: worker.connectionHint
                                        Accessible.name: worker.connectionHint
                                    }
                                }
                            }
                        }
                    }
                    Pane {
                        visible: !root.classicFullView
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: root.compactView ? 1 : root.transferLayout === "violetRail" ? 380 : 325
                        Layout.alignment: Qt.AlignTop
                        padding: root.compactView ? 5 : root.compactWidth || root.compactHeight ? 8 : 11
                        background: GlassSurface { material: root.material; role: "card"; backdropAvailable: root.backdropAvailable }
                        contentItem: ColumnLayout {
                            spacing: root.compactView ? 4 : 8
                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    Layout.fillWidth: true
                                    text: qsTr("Transfer speed")
                                    color: root.colors.text
                                    font.bold: true
                                    wrapMode: Text.WordWrap
                                }
                                NumeralLabel {
                                    visible: !root.compactView
                                    valueText: root.item ? Transfer.rate(root.item.speed) : "—"
                                    color: root.colors.muted
                                }
                            }
                            TransferGraph {
                                objectName: "downloadSpeedGraph"
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.preferredHeight: root.compactView ? 44 : root.compactWidth || root.compactHeight ? 70
                                    : root.transferLayout === "fogSlate" ? 88 : 104
                                compactStyle: root.compactView
                                samples: root.speedSamples
                                paintingPaused: root.interactiveFrame
                                animationStyle: WindowAppearance.graphAnimation
                                flowActive: root.animateTransfer
                                lineColor: MaterialTheme.graphColors[0]
                                endpointColor: MaterialTheme.graphColors[1]
                                gridColor: root.colors.divider
                                Accessible.name: qsTr("Measured transfer speed history")
                            }
                        }
                    }
                }

                Pane {
                    parent: root.classicFullView ? classicOptionPages : sections
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
                            font.pixelSize: TypographyScale.pixels(16)
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
                                enabled: root.canOpenAddressEditor
                                material: root.material
                                onClicked: root.openAddressEditor()
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
                                NumeralLabel {
                                    Layout.fillWidth: true
                                    valueText: qsTr("%1 matching pieces · %2 unchecked").arg(candidate.modelData.matching_pieces).arg(candidate.modelData.unavailable_pieces)
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
                    parent: root.classicFullView ? classicOptionPages : sections
                    visible: root.activeTab === 1
                    Layout.fillWidth: true
                    padding: root.classicFullView ? 8 : 14
                    background: Item {
                        ClassicTransferPage { anchors.fill: parent; visible: root.classicFullView }
                        GlassSurface {
                            anchors.fill: parent
                            visible: !root.classicFullView
                            material: root.material
                            role: "card"
                            backdropAvailable: root.backdropAvailable
                        }
                    }
                    contentItem: ColumnLayout {
                        spacing: 10
                        CheckBox { id: limitEnabled; text: qsTr("Limit this download's speed") }
                        RowLayout {
                            TextField {
                                id: limitField
                                font.family: text.length ? root.numeralInputFamily() : root.font.family
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
                    parent: root.classicFullView ? classicOptionPages : sections
                    visible: root.activeTab === 2
                    Layout.fillWidth: true
                    padding: root.classicFullView ? 8 : 14
                    background: Item {
                        ClassicTransferPage { anchors.fill: parent; visible: root.classicFullView }
                        GlassSurface {
                            anchors.fill: parent
                            visible: !root.classicFullView
                            material: root.material
                            role: "card"
                            backdropAvailable: root.backdropAvailable
                        }
                    }
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
                objectName: "downloadPipeTrunk"
                sizeScale: root.pipeScale
                LayoutMirroring.enabled: false
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: root.pipeInset - 2
                visible: root.displayFlow
                mainTrunk: true
                sourceItem: root.compactView ? transferName : transferSource
                progressItem: downloadProgress
                connectionCard: connectionPane
                gridItem: waterGrid
                workers: waterWorkers
                phase: water.phase
                slowPhase: water.slowPhase
                progressPhase: water.progressPhase
                paintingPaused: root.interactiveFrame
                flowing: root.showWaterFlow
                feedingConnections: root.feedingConnections
                progressAnimation: WindowAppearance.progressAnimation
                connectionAnimation: WindowAppearance.connectionAnimation
                progressLighting: WindowAppearance.progressLighting
                connectionLighting: WindowAppearance.connectionLighting
                progressStart: root.progressColors[0]
                progressEnd: root.progressColors[1]
                connectionStart: root.connectionColors[0]
                connectionEnd: root.connectionColors[1]
                channelColor: root.colors.background
                channelEdge: root.detailDivider
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
        objectName: "updateDownloadAddressWindow"
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
