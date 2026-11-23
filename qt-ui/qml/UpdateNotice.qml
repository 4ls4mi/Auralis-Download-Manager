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
    property string presentation: "toast"
    property var availableUpdate: null

    readonly property bool updateSupported: Qt.platform.os === "windows"
    readonly property bool canCheck: automaticChecks && updateSupported && Boolean(backend)
    readonly property var colors: MaterialTheme.palette
    readonly property bool working: stage !== ""
    readonly property bool updateInProgress: updateWindow.requestInProgress
    readonly property string statusStage: updateInProgress ? updateWindow.statusStage : availableUpdate ? "available" : ""
    readonly property var statusRelease: updateInProgress ? updateWindow.release : availableUpdate
    readonly property int bottomGap: 148

    property var release: null
    property string offeredVersion: ""
    property string stage: ""

    objectName: "updateNotice"
    title: qsTr("Auralis update available")
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.WindowDoesNotAcceptFocus
    modality: Qt.NonModal
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

    onAutomaticChecksChanged: if (!automaticChecks && !working) visible = false
    onPresentationChanged: if (presentation === "quiet" && !working) visible = false

    function checkForUpdate(reminder) {
        if (!canCheck || working || updateWindow.requestInProgress)
            return;
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
        if (updateInProgress) { updateWindow.open(); return; }
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
        onChecked: result => {
            popup.availableUpdate = result.state === "available" ? result : null;
            if (result.state === "available") {
                popup.release = result;
                popup.offeredVersion = String(result.version);
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
        onTriggered: popup.checkForUpdate(false)
    }
    Timer {
        interval: 4 * 60 * 60 * 1000
        repeat: true
        running: popup.canCheck
        onTriggered: popup.checkForUpdate(false)
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
