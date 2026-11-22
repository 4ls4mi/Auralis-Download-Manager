pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

Window {
    id: popup

    required property var backend
    required property Window anchorWindow
    property bool automaticChecks: true

    readonly property bool canCheck: automaticChecks && Qt.platform.os === "windows" && Boolean(backend && backend.ready)
    readonly property var colors: MaterialTheme.palette
    readonly property bool working: stage !== ""
    readonly property int bottomGap: 148

    property var release: null
    property string offeredVersion: ""
    property string stage: ""
    property string problem: ""

    signal detailsRequested(var update)

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
        problem = "";
        visible = true;
    }

    function checkForUpdate(reminder) {
        if (!canCheck || working)
            return;
        stage = "check";
        backend.request({ shellAction: "update-check" }, function(result, error) {
            popup.stage = "";
            if (error || !result || !popup.canCheck)
                return;
            if (result.state === "latest") {
                popup.visible = false;
                popup.release = null;
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
        detailsRequested(release);
    }

    function installUpdate() {
        if (working || !release)
            return;
        const version = String(release.version);
        problem = "";
        stage = "verify";
        backend.request({ shellAction: "update-check" }, function(result, error) {
            if (error || !result || result.state !== "available" || String(result.version) !== version) {
                popup.stage = "";
                if (result && result.state === "available" && result.version) {
                    popup.release = result;
                    popup.offeredVersion = String(result.version);
                }
                popup.problem = error || qsTr("The available release changed. Review it before installing.");
                return;
            }
            popup.stage = "download";
            popup.backend.request({ shellAction: "update-download" }, function(downloaded, downloadError) {
                if (downloadError || !downloaded || !downloaded.ok) {
                    popup.stage = "";
                    popup.problem = downloadError || qsTr("Could not download and verify the installer.");
                    return;
                }
                popup.stage = "install";
                popup.backend.request({ shellAction: "update-install" }, function(installed, installError) {
                    if (installError || !installed || !installed.ok) {
                        popup.stage = "";
                        popup.problem = installError || qsTr("Could not launch the verified installer.");
                    } else {
                        popup.stage = "closing";
                    }
                });
            });
        });
    }

    Timer {
        interval: 3500
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
            Label {
                Layout.fillWidth: true
                text: popup.title
                color: popup.colors.text
                font.pixelSize: 17
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            GlassButton {
                objectName: "updateNoticeDismiss"
                text: "×"
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
        Label {
            Layout.fillWidth: true
            color: popup.problem ? popup.colors.destructive : popup.colors.muted
            wrapMode: Text.Wrap
            text: popup.problem || ({
                verify: qsTr("Checking the selected release…"),
                download: qsTr("Downloading and verifying the installer…"),
                install: qsTr("Starting the verified installer…"),
                closing: qsTr("Closing Auralis for the update…")
            }[popup.stage]) || qsTr("Version %1 is ready to review.").arg(popup.release ? popup.release.version : "")
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            GlassButton {
                objectName: "updateNoticeDetails"
                text: qsTr("See details")
                enabled: !popup.working
                onClicked: popup.review()
            }
            GlassButton {
                objectName: "updateNoticeLater"
                text: qsTr("Later")
                ToolTip.text: qsTr("Remind me in an hour")
                ToolTip.visible: hovered
                enabled: !popup.working
                onClicked: popup.remindLater()
            }
            Item { Layout.fillWidth: true }
            GlassButton {
                objectName: "updateNoticeInstall"
                text: qsTr("Download and install")
                accent: popup.colors.accent
                highlighted: true
                enabled: !popup.working
                onClicked: popup.installUpdate()
            }
        }
    }
}
