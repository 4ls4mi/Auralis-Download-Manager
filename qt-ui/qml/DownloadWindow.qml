pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import "TransferData.js" as Transfer

ApplicationWindow {
    id: root
    property var downloadId: null
    property string material: MaterialTheme.current
    readonly property var colors: MaterialTheme.profile(material)
    readonly property string progressShape: selectedShape(WindowAppearance.progressShape)
    readonly property string connectionShape: selectedShape(WindowAppearance.connectionShape)
    readonly property var item: Transfer.find(engine.dashboard.downloads, downloadId)
    readonly property var telemetry: Transfer.find(engine.visuals.downloads, downloadId)
    readonly property var workerRows: !torrent && telemetry && telemetry.connections ? telemetry.connections.slice(0, 32) : []
    readonly property var torrent: telemetry && telemetry.torrent ? telemetry.torrent : null
    readonly property bool mixed: !!(telemetry && telemetry.direct_recovery)
    readonly property bool ordinary: !!(telemetry && !telemetry.is_torrent && !telemetry.is_video && !telemetry.is_gallery && !telemetry.is_remote)
    readonly property bool runningTransfer: !!(item && item.status === "Downloading")
    readonly property bool finished: !!(item && item.status === "Complete")
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
    minimumWidth: 485
    minimumHeight: 400
    color: "transparent"
    palette.windowText: colors.text
    palette.text: colors.text
    palette.buttonText: colors.text
    palette.base: colors.background
    palette.highlight: colors.accent
    title: item ? Math.round(Transfer.fraction(item) * 100) + "%  " + item.file : qsTr("Download details")

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

    header: ToolBar {
        padding: 10
        background: GlassSurface { material: root.material; role: "toolbar"; backdropAvailable: root.backdropAvailable }
        contentItem: RowLayout {
            spacing: 7
            Repeater {
                model: [qsTr("Download status"), qsTr("Speed limiter"), qsTr("Options on completion")]
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
            Item { Layout.fillWidth: true }
        }
    }

    ScrollView {
        id: view
        anchors.fill: parent
        clip: true
        padding: 12
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ColumnLayout {
            width: view.availableWidth
            spacing: 10

            Label {
                visible: !root.item
                text: qsTr("Waiting for download information…")
                color: root.colors.muted
            }

            Pane {
                visible: !!root.item && root.activeTab === 0
                Layout.fillWidth: true
                padding: 15
                background: GlassSurface { material: root.material; role: "card"; backdropAvailable: root.backdropAvailable }
                contentItem: ColumnLayout {
                    spacing: 10
                    Label {
                        Layout.fillWidth: true
                        text: root.item ? root.item.file : ""
                        elide: Text.ElideMiddle
                        color: root.colors.text
                        font.pixelSize: 19
                        font.bold: true
                    }
                    Label {
                        Layout.fillWidth: true
                        text: root.item ? root.item.url : ""
                        elide: Text.ElideMiddle
                        color: root.colors.muted
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: width >= 560 ? 2 : 1
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
                                Label { text: measurement.cell.label; color: root.colors.muted; Layout.preferredWidth: 116; elide: Text.ElideRight }
                                Label { text: measurement.cell.value; color: root.colors.text; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                        }
                    }
                    RowLayout {
                        id: progressLine
                        Layout.fillWidth: true
                        GlassProgress {
                            Layout.fillWidth: root.progressShape !== "bubble"
                            Layout.preferredWidth: root.progressShape === "bubble" ? progressLine.width * .53 : 100
                            Layout.preferredHeight: root.progressShape === "bubble" ? 38 : 27
                            value: Transfer.fraction(root.item)
                            animated: root.runningTransfer
                            shape: root.progressShape
                            fillStyle: WindowAppearance.progressFill
                            material: root.material
                            Accessible.name: qsTr("Download progress")
                        }
                        Label {
                            text: Math.round(Transfer.fraction(root.item) * 100) + "%"
                            color: root.colors.text
                            font.bold: true
                        }
                        Item { Layout.fillWidth: root.progressShape === "bubble"; visible: root.progressShape === "bubble" }
                    }
                    Label {
                        visible: root.mixed
                        Layout.fillWidth: true
                        color: root.colors.positive
                        wrapMode: Text.WordWrap
                        text: root.mixed && root.telemetry.original_partial
                              ? qsTr("Original direct partial kept at %1").arg(root.telemetry.original_partial) : ""
                    }
                    Label {
                        visible: !!(root.item && root.item.error)
                        Layout.fillWidth: true
                        text: root.item && root.item.error || ""
                        color: root.colors.destructive
                        wrapMode: Text.WordWrap
                    }
                }
            }

            GridLayout {
                visible: !!root.item && root.activeTab === 0
                Layout.fillWidth: true
                columns: width >= 630 ? 2 : 1
                columnSpacing: 10
                rowSpacing: 10
                Pane {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 355
                    padding: 12
                    background: GlassSurface { material: root.material; role: "card"; backdropAvailable: root.backdropAvailable }
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
                            Layout.fillWidth: true
                            columns: 8
                            rowSpacing: 5
                            columnSpacing: 5
                            Repeater {
                                model: root.workerRows.length
                                delegate: Item {
                                    id: worker
                                    required property int index
                                    readonly property var connection: root.workerRows[index] || {}
                                    readonly property var saved: Transfer.assigned(connection.id, root.telemetry && root.telemetry.segments)
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 31
                                    Layout.preferredHeight: 31
                                    GlassSurface { anchors.fill: parent; material: root.material; role: "field" }
                                    GlassProgress {
                                        visible: worker.saved !== null
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        height: 9
                                        material: root.material
                                        shape: root.connectionShape
                                        fillStyle: WindowAppearance.connectionFill
                                        value: worker.saved === null ? 0 : worker.saved
                                        animated: worker.connection.state === "Receiving"
                                    }
                                    Label {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.top
                                        anchors.topMargin: 3
                                        color: worker.connection.state === "Receiving" ? root.colors.positive
                                             : worker.connection.state === "Failed" || worker.connection.state === "Retrying" ? root.colors.caution : root.colors.muted
                                        text: Number(worker.connection.id) + 1
                                        font.pixelSize: 11
                                    }
                                    Rectangle {
                                        id: droplet
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 4
                                        height: 4
                                        radius: width / 2
                                        color: root.colors.accent
                                        border.color: root.colors.secondary
                                        visible: worker.connection.state === "Receiving" && !MaterialTheme.reducedMotion
                                        NumberAnimation on y {
                                            from: 10; to: 24; duration: 800
                                            running: droplet.visible && root.visible
                                            loops: Animation.Infinite
                                            easing.type: Easing.InQuad
                                        }
                                    }
                                    HoverHandler { id: workerHover }
                                    ToolTip.visible: workerHover.hovered
                                    ToolTip.text: qsTr("Connection %1 · %2 · %3").arg(Number(worker.connection.id) + 1).arg(worker.connection.state).arg(Transfer.rate(worker.connection.speed))
                                    Accessible.name: ToolTip.text
                                }
                            }
                        }
                    }
                }
                Pane {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 325
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
                            Layout.preferredHeight: 106
                            samples: root.speedSamples
                            lineColor: root.colors.accent
                            endpointColor: root.colors.secondary
                            gridColor: root.colors.divider
                            Accessible.name: qsTr("Measured transfer speed history")
                        }
                    }
                }
            }

            Pane {
                visible: root.activeTab === 0 && root.ordinary && !root.runningTransfer && !root.finished
                Layout.fillWidth: true
                padding: 14
                background: GlassSurface { material: root.material; role: "card"; backdropAvailable: root.backdropAvailable }
                contentItem: ColumnLayout {
                    spacing: 8
                    Label { text: qsTr("Download recovery"); color: root.colors.text; font.bold: true }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        GlassButton {
                            text: qsTr("Check saved data")
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
                            text: qsTr("Search Internet Archive")
                            enabled: root.torrentRecoveryAllowed && !root.busy && !root.recoveryBusy
                            material: root.material
                            onClicked: searchConsent.open()
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
                        GlassButton {
                            text: qsTr("Cancel torrent recovery")
                            material: root.material
                            visible: root.recoveryStage === "searching" || root.recoveryStage === "preparing"
                                     || root.pendingResult === "find-recovery-torrents-result" || root.pendingResult === "start-recovery-torrent-result"
                            onClicked: root.cancelRecovery()
                        }
                    }
                    Label {
                        visible: !root.torrentRecoveryAllowed
                        Layout.fillWidth: true
                        color: root.colors.muted
                        wrapMode: Text.WordWrap
                        text: qsTr("Torrent recovery is unavailable when a whole-file checksum is required.")
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        enabled: root.torrentRecoveryAllowed
                        TextField {
                            id: link
                            Layout.fillWidth: true
                            color: root.colors.text
                            placeholderText: qsTr("Magnet or torrent URL")
                            background: GlassSurface { material: root.material; role: "field" }
                            Accessible.name: placeholderText
                        }
                        GlassButton {
                            material: root.material
                            text: qsTr("Check link")
                            enabled: !root.busy && !root.recoveryBusy && /^(magnet:\?|https?:\/\/)/i.test(link.text.trim())
                            onClicked: linkConsent.open()
                        }
                        GlassButton {
                            material: root.material
                            text: qsTr("Torrent file…")
                            enabled: !root.busy && !root.recoveryBusy
                            onClicked: recoveryFile.open()
                        }
                    }
                    Repeater {
                        model: root.candidates
                        delegate: RowLayout {
                            id: candidate
                            required property var modelData
                            Layout.fillWidth: true
                            ColumnLayout {
                                Layout.fillWidth: true
                                Label { text: candidate.modelData.title || candidate.modelData.path; color: root.colors.text; Layout.fillWidth: true; elide: Text.ElideRight }
                                Label {
                                    text: qsTr("%1 matching pieces · %2 unchecked").arg(candidate.modelData.matching_pieces).arg(candidate.modelData.unavailable_pieces)
                                    color: root.colors.muted
                                }
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
                    CheckBox {
                        id: risk
                        visible: root.candidates.length > 0
                        text: qsTr("I understand that the rest of the torrent may differ.")
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
                    ComboBox { id: powerAction; model: [qsTr("Keep computer on"), qsTr("Shut down"), qsTr("Sleep"), qsTr("Hibernate")] }
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
                visible: root.message !== ""
                Layout.fillWidth: true
                text: root.message
                color: root.error ? root.colors.destructive : root.colors.text
                wrapMode: Text.WordWrap
            }
        }
    }

    footer: ToolBar {
        padding: 10
        background: GlassSurface { material: root.material; role: "footer"; backdropAvailable: root.backdropAvailable }
        contentItem: Flow {
            spacing: 7
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
                material: root.material
                text: root.runningTransfer ? qsTr("Pause") : root.item && root.item.status === "Queued" ? qsTr("Start") : qsTr("Resume")
                visible: !!root.item && !root.finished
                enabled: !root.busy && (root.runningTransfer || (!root.recoveryBusy && !(root.telemetry && root.telemetry.recovery_damaged)))
                accent: root.runningTransfer ? root.colors.caution : root.colors.positive
                onClicked: root.perform(root.runningTransfer ? "pause" : "start", false)
            }
            GlassButton {
                material: root.material
                text: root.runningTransfer ? qsTr("Cancel…") : qsTr("Close")
                accent: root.runningTransfer ? root.colors.destructive : root.colors.accent
                onClicked: root.runningTransfer ? stopConsent.open() : root.close()
            }
        }
    }

    Dialog {
        id: stopConsent
        anchors.centerIn: parent
        modal: true
        title: qsTr("Stop this download?")
        standardButtons: Dialog.Yes | Dialog.No
        Label { text: qsTr("Saved data will be kept so the download can resume."); width: 320; wrapMode: Text.WordWrap }
        onAccepted: root.perform("pause", true)
    }
    Dialog {
        id: restartConsent
        anchors.centerIn: parent
        modal: true
        title: qsTr("Download from the beginning?")
        standardButtons: Dialog.Yes | Dialog.No
        Label { text: qsTr("This discards the saved partial and starts a new download."); width: 330; wrapMode: Text.WordWrap }
        onAccepted: root.saveOptions("redownload", null, qsTr("Restarting the download…"))
    }
    Dialog {
        id: searchConsent
        anchors.centerIn: parent
        modal: true
        title: qsTr("Search for a matching torrent?")
        standardButtons: Dialog.Yes | Dialog.No
        Label { text: qsTr("Searching sends filename terms to Internet Archive. A piece match only verifies the compared bytes."); width: 340; wrapMode: Text.WordWrap }
        onAccepted: root.beginCheck("find-recovery-torrents", null, qsTr("Searching Internet Archive…"))
    }
    Dialog {
        id: linkConsent
        anchors.centerIn: parent
        modal: true
        title: qsTr("Check this torrent source?")
        standardButtons: Dialog.Yes | Dialog.No
        Label { text: qsTr("Checking a magnet contacts BitTorrent peers. A matching piece cannot verify the rest of the file."); width: 340; wrapMode: Text.WordWrap }
        onAccepted: root.beginCheck(/^magnet:/i.test(link.text.trim()) ? "check-recovery-magnet" : "check-recovery-torrent-url",
            link.text.trim(), qsTr("Checking the supplied torrent metadata…"))
    }
    Dialog {
        id: addressPrompt
        anchors.centerIn: parent
        modal: true
        title: qsTr("Update download address")
        width: Math.min(480, root.width - 24)
        standardButtons: Dialog.Save | Dialog.Cancel
        contentItem: ColumnLayout {
            Label {
                Layout.fillWidth: true
                text: qsTr("Saved bytes are kept. Use an address for the same file.")
                wrapMode: Text.WordWrap
            }
            TextField {
                id: updatedAddress
                Layout.fillWidth: true
                selectByMouse: true
                Accessible.name: qsTr("New download address")
            }
        }
        onAccepted: {
            const address = updatedAddress.text.trim()
            if (!/^(https?|ftp):\/\//i.test(address))
                root.say(qsTr("Enter a valid download address."), true)
            else
                root.saveOptions("refresh-address", address, qsTr("Download address updated. Saved bytes were kept."))
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
