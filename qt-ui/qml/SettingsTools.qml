import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root

    property string section: "Advanced"
    property var helpers: null
    property bool loadingHelpers: false
    property bool helperRequest: false
    property bool browserRequest: false
    property var release: null
    property string updateStage: ""
    property string extensionMessage: ""
    property string helperProblem: ""
    property string updateProblem: ""
    readonly property bool browserSection: section === "Browser Integration"
    readonly property bool hasWindowsIntegration: Qt.platform.os === "windows"
    readonly property bool installingHelper: Boolean(helpers && helpers.job && helpers.job.state === "installing")
    readonly property var colors: MaterialTheme.palette

    spacing: 14

    function loadHelpers() {
        if (browserSection || loadingHelpers)
            return
        loadingHelpers = true
        engine.request({query: "glass-helpers"}, function(result, error) {
            loadingHelpers = false
            if (error || !result) {
                if (!helpers)
                    helperProblem = error || qsTr("Could not load media helpers.")
                return
            }
            if (!helpers)
                helperProblem = ""
            helpers = result
        })
    }

    function installHelper(name) {
        if (helperRequest || installingHelper)
            return
        helperRequest = true
        helperProblem = ""
        engine.request({action: "glass-helpers", queue: JSON.stringify({name: name})}, function(result, error) {
            helperRequest = false
            if (error || !result || !result.ok)
                helperProblem = error || qsTr("Could not start the helper installation.")
            loadHelpers()
        })
    }

    function extensionAction(action) {
        if (browserRequest)
            return
        browserRequest = true
        extensionMessage = ""
        engine.request({local: action}, function(result, error) {
            browserRequest = false
            extensionMessage = error || (!result || !result.ok ? qsTr("Browser setup did not complete.") : "") || (result && result.message)
                || (action === "registerBrowserHost"
                    ? qsTr("Browser connection registered. Restart the browser to reconnect.")
                    : qsTr("Choose the displayed Auralis folder when loading the unpacked extension."))
        })
    }

    function checkForUpdate() {
        if (updateStage)
            return
        updateStage = "check"
        updateProblem = ""
        release = null
        engine.request({shellAction: "update-check"}, function(result, error) {
            updateStage = ""
            if (error || !result || !["available", "latest"].includes(result.state)) {
                updateProblem = error || (result && result.message) || qsTr("Could not check for Auralis updates.")
                return
            }
            release = result
        })
    }

    function downloadUpdate() {
        if (updateStage || !release || release.state !== "available")
            return
        updateStage = "download"
        updateProblem = ""
        engine.request({shellAction: "update-download"}, function(result, error) {
            if (error || !result || !result.ok) {
                updateStage = ""
                updateProblem = error || qsTr("Could not download and verify the update.")
                return
            }
            updateStage = "install"
            engine.request({shellAction: "update-install"}, function(installed, installError) {
                if (installError || !installed || !installed.ok) {
                    updateStage = ""
                    updateProblem = installError || qsTr("Could not launch the verified installer.")
                } else {
                    updateStage = "closing"
                }
            })
        })
    }

    Component.onCompleted: if (visible) loadHelpers()
    onVisibleChanged: if (visible) loadHelpers()
    onSectionChanged: if (visible) loadHelpers()

    Timer {
        interval: 1500
        repeat: true
        running: root.visible && !root.browserSection
        onTriggered: root.loadHelpers()
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.browserSection
        spacing: 8

        Label {
            Layout.fillWidth: true
            text: qsTr("Auralis browser extension")
            color: root.colors.text
            font.pixelSize: 17
            font.weight: Font.DemiBold
        }

        Label {
            Layout.fillWidth: true
            color: root.colors.muted
            wrapMode: Text.WordWrap
            text: root.hasWindowsIntegration
                ? qsTr("Open the bundled extension folder. In Chrome or Edge, go to Extensions, enable Developer mode, then choose Load unpacked. Register the browser connection if the extension cannot reach Auralis.")
                : qsTr("Bundled browser connection registration is available on Windows.")
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8

            GlassButton {
                text: qsTr("Open extension folder")
                enabled: root.hasWindowsIntegration && !root.browserRequest
                onClicked: root.extensionAction("openExtensionFolder")
            }
            GlassButton {
                text: qsTr("Register browser connection")
                enabled: root.hasWindowsIntegration && !root.browserRequest
                onClicked: root.extensionAction("registerBrowserHost")
            }
        }

        Label {
            Layout.fillWidth: true
            visible: root.browserRequest || root.extensionMessage.length > 0
            text: root.browserRequest ? qsTr("Preparing browser integration…") : root.extensionMessage
            color: root.colors.muted
            wrapMode: Text.WordWrap
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: !root.browserSection
        spacing: 8

        Label {
            Layout.fillWidth: true
            text: qsTr("Video and gallery helpers")
            color: root.colors.text
            font.pixelSize: 17
            font.weight: Font.DemiBold
        }

        Repeater {
            model: root.helpers ? root.helpers.tools : []

            delegate: RowLayout {
                id: tool
                required property var modelData
                Layout.fillWidth: true

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Label {
                        text: tool.modelData.name
                        color: root.colors.text
                        font.weight: Font.DemiBold
                    }
                    Label {
                        Layout.fillWidth: true
                        text: tool.modelData.version
                            ? qsTr("%1 · %2").arg(tool.modelData.version).arg(tool.modelData.path)
                            : qsTr("Not installed")
                        color: root.colors.muted
                        elide: Text.ElideMiddle
                    }
                }

                GlassButton {
                    text: tool.modelData.version ? qsTr("Check for update") : qsTr("Install")
                    enabled: !root.helperRequest && !root.installingHelper
                    onClicked: root.installHelper(tool.modelData.name)
                }
            }
        }

        Label {
            Layout.fillWidth: true
            visible: Boolean(root.helpers && root.helpers.job) || root.helperRequest || (root.loadingHelpers && !root.helpers)
            wrapMode: Text.WordWrap
            color: root.colors.muted
            text: {
                const job = root.helpers && root.helpers.job
                if (root.helperRequest) return qsTr("Starting helper installation…")
                if (!job) return qsTr("Checking installed helpers…")
                if (job.state === "installing") return qsTr("Installing %1…").arg(job.name)
                if (job.state === "ready") return qsTr("%1 is ready.").arg(job.name)
                return qsTr("%1 · %2").arg(job.name).arg(job.state)
            }
        }

        Label {
            Layout.fillWidth: true
            visible: root.helperProblem.length > 0
            text: root.helperProblem
            color: root.colors.destructive
            wrapMode: Text.WordWrap
        }

        Label {
            Layout.fillWidth: true
            Layout.topMargin: 12
            text: qsTr("Auralis updates")
            color: root.colors.text
            font.pixelSize: 17
            font.weight: Font.DemiBold
        }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: root.colors.muted
            text: {
                if (!root.hasWindowsIntegration) return qsTr("The installer updater is available on Windows.")
                if (root.updateStage === "check") return qsTr("Checking for updates…")
                if (root.updateStage === "download") return qsTr("Downloading and verifying the installer…")
                if (root.updateStage === "install") return qsTr("Opening the verified installer…")
                if (root.updateStage === "closing") return qsTr("Closing Auralis for installation…")
                if (!root.release) return ""
                if (root.release.state === "available") return qsTr("Auralis %1 is available.").arg(root.release.version)
                return qsTr("Auralis is up to date.")
            }
            visible: text.length > 0
        }

        ProgressBar {
            Layout.fillWidth: true
            visible: root.updateStage === "download"
            indeterminate: true
            Accessible.name: qsTr("Downloading Auralis update")
        }

        Flow {
            id: updateButtons
            Layout.fillWidth: true
            spacing: 8
            visible: root.hasWindowsIntegration

            GlassButton {
                text: qsTr("Check for updates")
                enabled: !root.updateStage
                onClicked: root.checkForUpdate()
            }

            GlassButton {
                text: qsTr("Show release notes")
                visible: Boolean(root.release && root.release.notes)
                onClicked: releaseNotes.open()
            }

            GlassButton {
                text: qsTr("Download and install")
                visible: Boolean(root.release && root.release.state === "available")
                enabled: !root.updateStage
                onClicked: root.downloadUpdate()
            }
        }

        Dialog {
            id: releaseNotes
            title: qsTr("Release notes")
            modal: true
            standardButtons: Dialog.Close

            ScrollView {
                implicitWidth: 440
                implicitHeight: 290
                clip: true
                TextArea {
                    text: root.release && root.release.notes ? root.release.notes : ""
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                }
            }
        }

        Label {
            Layout.fillWidth: true
            visible: root.updateProblem.length > 0
            text: root.updateProblem
            color: root.colors.destructive
            wrapMode: Text.WordWrap
        }
    }
}
