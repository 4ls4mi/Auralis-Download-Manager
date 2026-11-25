pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "TransferData.js" as TransferData

DetachedDialogWindow {
    id: update

    required property var backend
    property var release: null
    property var transfer: null
    property string stage: ""
    property string problem: ""
    property bool waitingForAutomaticCheck: false
    property bool minimizeToTray: false
    readonly property bool trayAvailable: backend.trayAvailable === true
    readonly property bool checking: stage === "checking" || stage === "rechecking"
    readonly property bool requestInProgress: checking || busy
    readonly property string statusStage: stage === "downloading" ? transfer?.state || "connecting" : stage
    readonly property double totalBytes: Number(transfer?.total || release?.size || 0)
    readonly property double downloadedBytes: Math.min(totalBytes, Math.max(0, Number(transfer?.downloaded || 0)))
    readonly property real completion: totalBytes > 0 ? downloadedBytes / totalBytes : 0

    signal checked(var result)
    signal showMainRequested()

    objectName: "updateWindow"
    title: qsTr("Auralis Update")
    width: 550
    minimumHeight: 245
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowSystemMenuHint | Qt.WindowMinimizeButtonHint | Qt.WindowCloseButtonHint
    modality: Qt.NonModal
    transientParent: null
    busy: ["rechecking", "downloading", "installing", "closing"].includes(stage)
    onDismissRequested: hide()
    onVisibleChanged: if (!visible) closeWhenCurrent.stop()
    onClosing: if (requestInProgress) hide()
    onVisibilityChanged: {
        if (update.visibility === Window.Minimized && trayAvailable && minimizeToTray) {
            Qt.callLater(() => {
                if (update.visibility === Window.Minimized)
                    update.hide()
            })
        }
    }

    function present() {
        if (visibility === Window.Minimized)
            showNormal()
        if (!positioned && hostWindow?.visible && hostWindow.visibility !== Window.Minimized) {
            fitInitialHeight()
            x = Math.round(hostWindow.x + (hostWindow.width - width) / 2)
            y = Math.round(hostWindow.y + (hostWindow.height - height) / 2)
            positioned = true
        }
        open()
    }

    function minimizeWindow() {
        if (trayAvailable && minimizeToTray)
            hide()
        else
            showMinimized()
    }

    function beginCheck(awaitAutomaticCheck) {
        if (requestInProgress) { present(); return }
        closeWhenCurrent.stop()
        stage = "checking"
        problem = ""
        release = null
        transfer = null
        waitingForAutomaticCheck = awaitAutomaticCheck
        present()
        if (!awaitAutomaticCheck)
            backend.request({shellAction: "update-check"}, function(result, error) { update.finishCheck(result, error) })
    }

    function finishCheck(result, error) {
        waitingForAutomaticCheck = false
        if (error || !result || !["latest", "available"].includes(result.state)) {
            stage = "error"
            problem = error || qsTr("Could not check for Auralis updates.")
            return
        }
        checked(result)
        release = result.state === "available" ? result : null
        stage = release ? "available" : "latest"
        if (stage === "latest" && visible) closeWhenCurrent.restart()
    }

    function showRelease(result) {
        if (requestInProgress) { present(); return }
        if (!result || result.state !== "available") {
            beginCheck(false)
            return
        }
        closeWhenCurrent.stop()
        release = result
        transfer = null
        problem = ""
        stage = "available"
        present()
    }

    function downloadAndInstall() {
        if (requestInProgress || !release) return
        const version = String(release.version)
        stage = "rechecking"
        problem = ""
        transfer = null
        backend.request({shellAction: "update-check"}, function(result, error) {
            if (error || !result || !["latest", "available"].includes(result.state)) {
                stage = "available"
                problem = error || qsTr("Could not confirm the selected release.")
                return
            }
            if (result.state === "latest") { finishCheck(result, null); return }
            checked(result)
            release = result
            if (String(result.version) !== version) {
                stage = "available"
                problem = qsTr("A newer release is available. Review it before installing.")
                return
            }
            stage = "downloading"
            backend.request({shellAction: "update-download", expectedVersion: version}, function(receipt, downloadError) {
                if (downloadError || !receipt || !receipt.ok) {
                    stage = "available"
                    problem = downloadError || qsTr("Could not download and verify the installer.")
                    return
                }
                transfer = {version: version, total: Number(receipt.size || release.size), downloaded: Number(receipt.size || release.size)}
                installVerified(version)
            })
        })
    }

    function installVerified(version) {
        stage = "installing"
        problem = ""
        backend.request({shellAction: "update-install", expectedVersion: version}, function(result, error) {
            if (error || !result || !result.ok) {
                stage = "available"
                problem = error || qsTr("Could not start the verified installer.")
                return
            }
            stage = "closing"
        })
    }

    function pollTransfer() {
        if (stage !== "downloading") return
        backend.request({shellAction: "update-progress"}, function(status, error) {
            if (!error && stage === "downloading" && status && release && status.version === release.version
                    && ["connecting", "downloading", "verifying"].includes(status.state))
                transfer = status
        })
    }

    Timer {
        id: closeWhenCurrent
        interval: 2200
        onTriggered: if (update.stage === "latest") update.hide()
    }

    Timer {
        interval: 160
        repeat: true
        running: update.stage === "downloading"
        triggeredOnStart: true
        onTriggered: update.pollTransfer()
    }

    bodyContent: [
        UpdateStatusCard {
            Layout.fillWidth: true
            stage: update.statusStage
            installedVersion: update.backend.version || ""
            targetVersion: update.release?.version || ""
            installerBytes: update.totalBytes
        },
        ProgressBar {
            Layout.fillWidth: true
            visible: update.checking && !MaterialTheme.reducedMotion
            indeterminate: true
            Accessible.name: qsTr("Checking for Auralis updates")
        },
        GlassProgress {
            Layout.fillWidth: true
            baseHeight: 24
            visible: update.stage === "downloading"
            value: update.completion
            animated: visible && update.visibility !== Window.Minimized
            layoutStyle: "classic"
            animationStyle: WindowAppearance.progressAnimation
            shape: WindowAppearance.progressShape === "material"
                ? (["bubble", "prism", "ice"].includes(profile.shape) ? profile.shape : "round") : WindowAppearance.progressShape
            startColor: MaterialTheme.progressColors[0]
            endColor: MaterialTheme.progressColors[1]
            showLabel: false
        },
        NumeralLabel {
            Layout.fillWidth: true
            visible: update.stage === "downloading" && update.totalBytes > 0
            valueText: qsTr("%1% · %2 of %3").arg(Math.floor(update.completion * 100))
                .arg(TransferData.bytes(update.downloadedBytes)).arg(TransferData.bytes(update.totalBytes))
            color: update.colors.muted
            Accessible.name: qsTr("Update download progress")
        },
        Label {
            Layout.fillWidth: true
            visible: Boolean(update.problem)
            text: update.problem
            textFormat: Text.PlainText
            color: update.colors.destructive
            wrapMode: Text.WordWrap
        },
        ColumnLayout {
            Layout.fillWidth: true
            visible: Boolean(update.release?.notes) && update.stage === "available"
            spacing: 6
            Label {
                text: qsTr("Release notes")
                color: update.colors.ink
                font.weight: Font.DemiBold
            }
            TextArea {
                Layout.fillWidth: true
                text: visible ? update.release?.notes || "" : ""
                textFormat: TextEdit.PlainText
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                color: update.colors.ink
                padding: 8
                background: GlassSurface { role: "field" }
            }
        }
    ]

    footer: Item {
        implicitHeight: actions.implicitHeight + 16
        GlassSurface { anchors.fill: parent; role: "footer" }
        Flow {
            id: actions
            width: parent.width - 28
            anchors.centerIn: parent
            layoutDirection: Qt.RightToLeft
            spacing: 8
            GlassButton {
                objectName: "downloadAuralisUpdate"
                text: qsTr("Download and install")
                Accessible.description: qsTr("Install Auralis %1").arg(update.release?.version || "")
                accent: update.colors.positive
                visible: update.stage === "available"
                highlighted: true
                onClicked: update.downloadAndInstall()
            }
            GlassButton {
                objectName: "manualUpdateRetry"
                text: qsTr("Check again")
                accent: update.colors.caution
                visible: update.stage === "error"
                onClicked: update.beginCheck(false)
            }
            GlassButton {
                objectName: "hideUpdateWindow"
                text: qsTr("Hide to main window")
                accent: update.colors.accent
                visible: update.requestInProgress
                onClicked: {
                    update.hide()
                    update.showMainRequested()
                }
            }
            GlassButton {
                objectName: "minimizeUpdateWindow"
                text: update.trayAvailable && update.minimizeToTray ? qsTr("Minimize to system tray") : qsTr("Minimize")
                visible: update.requestInProgress
                onClicked: update.minimizeWindow()
            }
            GlassButton {
                text: qsTr("Close")
                accent: update.colors.destructive
                visible: !update.requestInProgress
                onClicked: update.hide()
            }
        }
    }
}
