pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

Window {
    id: popup

    LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    required property var backend
    required property Window anchorWindow
    property bool automaticChecks: true
    property bool minimizeToTray: false
    property string presentation: "toast"
    property var availableUpdate: null

    property bool updateSupported: Qt.platform.os === "windows"
    property int checkInterval: 15 * 60 * 1000
    readonly property bool canCheck: automaticChecks && updateSupported && Boolean(backend)
        && backend.interactiveSetup !== false && !backend.quitting
    readonly property var colors: MaterialTheme.palette
    readonly property bool working: stage !== ""
    readonly property bool updateInProgress: updateWindow.requestInProgress
    readonly property string statusProblem: updateWindow.problem
    readonly property string statusStage: updateInProgress ? updateWindow.statusStage
        : statusProblem ? "error" : availableUpdate ? "available" : ""
    readonly property var statusRelease: updateInProgress || statusProblem ? updateWindow.release : availableUpdate
    readonly property double statusInstallerBytes: updateWindow.stage === "downloading"
        ? updateWindow.totalBytes : Number(statusRelease?.size || 0)
    readonly property double statusDownloadedBytes: updateWindow.stage === "downloading" ? updateWindow.downloadedBytes : -1
    readonly property int bottomGap: 148

    property var release: null
    property string offeredVersion: ""
    property string stage: ""
    property double lastCheckStartedAt: 0
    property string hintedVersion: ""
    property int hintChecksRemaining: 0
    property double hintCheckAfter: 0

    objectName: "updateNotice"
    title: qsTr("Auralis update available")
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
    modality: Qt.NonModal
    transientParent: null
    screen: anchorWindow.screen
    color: "transparent"
    visible: false
    width: Screen.width > 0 ? Math.max(280, Math.min(424, Screen.width - 24)) : 424
    height: Math.max(144, body.implicitHeight + 28)
    x: Screen.virtualX + Math.min(Screen.width, Screen.desktopAvailableWidth || Screen.width) - width - 16
    y: Math.max(Screen.virtualY + 12, Screen.virtualY + Math.min(Screen.height, Screen.desktopAvailableHeight || Screen.height) - height - bottomGap)

    Settings {
        id: preferences
        category: "UpdateNotices"
        property string dismissedVersion: ""
        property string reminderVersion: ""
        property double remindAfter: 0
    }

    function offer(update, reminder) {
        if (!update || update.state !== "available" || !update.version)
            return;
        availableUpdate = update;
        const version = String(update.version);
        clearVerifiedHint(version);
        if (presentation === "quiet")
            return;
        if (preferences.dismissedVersion === version)
            return;
        if (preferences.reminderVersion === version && preferences.remindAfter > Date.now())
            return;
        if (offeredVersion === version && !reminder)
            return;
        if (preferences.reminderVersion === version) {
            preferences.reminderVersion = "";
            preferences.remindAfter = 0;
        }
        release = update;
        offeredVersion = version;
        if (presentation === "dialog") {
            visible = false;
            updateWindow.hostWindow = anchorWindow;
            updateWindow.showRelease(release);
        } else {
            visible = presentation === "toast" || presentation === "notify";
            if (presentation === "notify")
                backend.notifyUpdate(version);
        }
    }

    function configureReleaseHints() {
        backend?.setReleaseUpdateHintsEnabled?.(canCheck);
        if (!canCheck) {
            visible = false;
            lastCheckStartedAt = 0;
            hintedVersion = "";
            hintChecksRemaining = 0;
        }
    }

    function newerVersion(left, right) {
        const lhs = String(left).split(".").map(Number);
        const rhs = String(right).split(".").map(Number);
        for (let i = 0; i < 3; i++) {
            if (lhs[i] !== rhs[i])
                return lhs[i] > rhs[i];
        }
        return false;
    }

    function clearVerifiedHint(version) {
        if (hintedVersion && !newerVersion(hintedVersion, version)) {
            hintedVersion = "";
            hintChecksRemaining = 0;
        }
    }

    function handleReleaseHint(version) {
        if (!canCheck)
            return;
        const now = Date.now();
        if (!version) {
            if (hintChecksRemaining === 0 && now - lastCheckStartedAt >= 60000)
                checkForUpdate(false);
            return;
        }
        if (version === hintedVersion || !newerVersion(version, availableUpdate?.version || backend.version))
            return;
        // The socket announces a version only. Recheck the verified feed, with one retry
        // if the freshly published release has yet to appear there.
        hintedVersion = version;
        hintChecksRemaining = 2;
        hintCheckAfter = Math.max(now + 150, lastCheckStartedAt + 15000);
    }

    onCanCheckChanged: configureReleaseHints()
    Component.onCompleted: configureReleaseHints()
    onPresentationChanged: {
        if (presentation === "quiet")
            visible = false;
        else if (canCheck && availableUpdate)
            offer(availableUpdate, false);
    }

    Connections {
        target: popup.backend
        function onReleaseUpdateHint(version) { popup.handleReleaseHint(version); }
    }

    function checkForUpdate(reminder) {
        if (!canCheck || working || updateWindow.requestInProgress)
            return;
        lastCheckStartedAt = Date.now();
        stage = "check";
        backend.request({ shellAction: "update-check" }, function(result, error) {
            popup.stage = "";
            if (updateWindow.waitingForAutomaticCheck) {
                updateWindow.finishCheck(result, error);
                return;
            }
            if (error || !result || !popup.canCheck)
                return;
            if (result.state === "latest") {
                popup.visible = false;
                popup.release = null;
                popup.availableUpdate = null;
                preferences.reminderVersion = "";
                preferences.remindAfter = 0;
                return;
            }
            popup.offer(result, reminder && preferences.reminderVersion === String(result.version));
        });
    }

    function remindLater() {
        if (working || !release)
            return;
        preferences.reminderVersion = String(release.version);
        preferences.remindAfter = Date.now() + 60 * 60 * 1000;
        visible = false;
    }

    function dismiss() {
        if (working || !release)
            return;
        preferences.dismissedVersion = String(release.version);
        if (preferences.reminderVersion === preferences.dismissedVersion) {
            preferences.reminderVersion = "";
            preferences.remindAfter = 0;
        }
        visible = false;
    }

    function review() {
        if (working || !release)
            return;
        visible = false;
        if (!updateWindow.requestInProgress) updateWindow.hostWindow = anchorWindow;
        updateWindow.showRelease(release);
    }

    function manualCheck(owner) {
        if (!updateSupported) return;
        visible = false;
        if (!updateWindow.requestInProgress) updateWindow.hostWindow = owner || anchorWindow;
        updateWindow.beginCheck(stage === "check");
    }

    function showUpdate(owner) {
        if (updateInProgress || statusProblem) { updateWindow.present(); return; }
        if (!availableUpdate) { manualCheck(owner); return; }
        visible = false;
        if (!updateWindow.requestInProgress) updateWindow.hostWindow = owner || anchorWindow;
        updateWindow.showRelease(availableUpdate);
    }

    function installUpdate() {
        review();
        updateWindow.downloadAndInstall();
    }

    UpdateWindow {
        id: updateWindow
        hostWindow: popup.anchorWindow
        backend: popup.backend
        minimizeToTray: popup.minimizeToTray
        onShowMainRequested: {
            const mainWindow = popup.anchorWindow
            if (!mainWindow.visible || mainWindow.visibility === Window.Minimized)
                mainWindow.showNormal()
            mainWindow.raise()
            mainWindow.requestActivate()
        }
        onChecked: result => {
            popup.availableUpdate = result.state === "available" ? result : null;
            if (result.state === "available") {
                popup.release = result;
                popup.offeredVersion = String(result.version);
                popup.clearVerifiedHint(popup.offeredVersion);
            }
            if (result.state === "latest") {
                popup.release = null;
                preferences.reminderVersion = "";
                preferences.remindAfter = 0;
            }
        }
    }

    Timer {
        interval: 700
        running: popup.canCheck
        onTriggered: if (popup.lastCheckStartedAt === 0) popup.checkForUpdate(false)
    }
    Timer {
        interval: popup.checkInterval
        running: popup.canCheck && !popup.working && !popup.updateInProgress
        onTriggered: popup.checkForUpdate(false)
    }
    Timer {
        interval: popup.working || popup.updateInProgress ? 1 : Math.max(1, popup.hintCheckAfter - Date.now())
        running: popup.canCheck && !popup.working && !popup.updateInProgress && popup.hintChecksRemaining > 0
        onTriggered: {
            popup.hintChecksRemaining--;
            popup.hintCheckAfter = Date.now() + 60000;
            popup.checkForUpdate(false);
        }
    }
    Timer {
        interval: 60 * 1000
        repeat: true
        running: popup.canCheck && preferences.remindAfter > 0
        onTriggered: {
            if (preferences.remindAfter <= Date.now())
                popup.checkForUpdate(true);
        }
    }

    GlassSurface { anchors.fill: parent; role: "modal"; backdropAvailable: false }

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            UpdateStatusCard {
                Layout.fillWidth: true
                stage: "available"
                installedVersion: popup.backend.version || ""
                targetVersion: popup.release?.version || ""
                installerBytes: Number(popup.release?.size || 0)
            }
            GlassButton {
                objectName: "updateNoticeDismiss"
                Layout.alignment: Qt.AlignTop
                text: "×"
                accent: popup.colors.destructive
                Accessible.name: qsTr("Dismiss this version")
                ToolTip.text: qsTr("Dismiss this version")
                ToolTip.visible: hovered
                enabled: !popup.working
                leftPadding: 8
                rightPadding: 8
                topPadding: 4
                bottomPadding: 4
                onClicked: popup.dismiss()
            }
        }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            GlassButton {
                objectName: "updateNoticeDetails"
                text: qsTr("Review update")
                enabled: !popup.working
                onClicked: popup.review()
            }
            GlassButton {
                objectName: "updateNoticeLater"
                text: qsTr("Later")
                accent: popup.colors.caution
                ToolTip.text: qsTr("Remind me in an hour")
                ToolTip.visible: hovered
                enabled: !popup.working
                onClicked: popup.remindLater()
            }
            GlassButton {
                objectName: "updateNoticeInstall"
                text: qsTr("Download and install")
                accent: popup.colors.positive
                filled: true
                enabled: !popup.working
                onClicked: popup.installUpdate()
            }
        }
    }
}
