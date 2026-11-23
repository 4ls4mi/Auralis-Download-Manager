pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ColumnLayout {
    id: root

    property string section: "Advanced"
    property string updatePresentation: "toast"
    property bool automaticChecks: true
    signal updatePresentationRequested(string value)
    signal automaticChecksRequested(bool value)
    signal updateCheckRequested()
    signal updateDetailsRequested()
    readonly property var presentationOptions: [
        {label: qsTr("Show in Auralis only"), value: "quiet"},
        {label: qsTr("Auralis corner popup"), value: "toast"},
        {label: qsTr("Windows notification and Auralis corner popup"), value: "notify"},
        {label: qsTr("Open update details immediately"), value: "dialog"}
    ]
    property var helpers: null
    property bool loadingHelpers: false
    property bool helperRequest: false
    property bool browserRequest: false
    property bool checkingChrome: false
    property var chromeStatus: null
    property var release: null
    property string extensionMessage: ""
    property string chromeProblem: ""
    property string helperProblem: ""
    readonly property bool browserSection: section === "Browser Integration"
    readonly property bool hasWindowsIntegration: Qt.platform.os === "windows"
    readonly property bool browserSetupVisible: browserSection && hasWindowsIntegration && visible
        && Boolean(Window.window?.visible) && Window.window.visibility !== Window.Minimized
    readonly property bool chromeStoreAvailable: Boolean(chromeStatus?.storeUrl)
    readonly property bool chromeVerifiedRecently: Boolean(chromeStatus?.connectedRecently)
    readonly property bool chromeStoreUsed: Boolean(chromeVerifiedRecently || chromeStatus?.storePreviouslyConnected)
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
            if (error || !result?.ok) {
                extensionMessage = error || qsTr("Browser setup did not complete.")
            } else if (action === "openChromeExtensionStore") {
                extensionMessage = result.openedInChrome
                    ? qsTr("Continue in Chrome to install or manage the extension.")
                    : qsTr("The listing opened in your default browser. Use Google Chrome to install Auralis.")
            } else if (action === "openChromeExtensions") {
                extensionMessage = qsTr("In Chrome’s extension manager, turn on Developer mode and select Update to check for updates now.")
            } else {
                extensionMessage = result.message || (action === "registerBrowserHost"
                    ? qsTr("Browser connection registered. Restart the browser to reconnect.")
                    : qsTr("Choose the displayed Auralis folder when loading the unpacked extension."))
            }
            loadChromeStatus()
        })
    }

    function loadChromeStatus() {
        if (!browserSetupVisible || checkingChrome)
            return
        checkingChrome = true
        engine.request({local: "chromeExtensionStatus"}, function(result, error) {
            checkingChrome = false
            if (!browserSetupVisible)
                return
            chromeStatus = error || !result ? null : result
            chromeProblem = chromeStatus ? "" : error || qsTr("Could not check Chrome integration.")
        })
    }

    Component.onCompleted: if (visible) loadHelpers()
    onVisibleChanged: if (visible) loadHelpers()
    onSectionChanged: if (visible) loadHelpers()
    onBrowserSetupVisibleChanged: {
        if (browserSetupVisible) {
            loadChromeStatus()
        } else {
            chromeStatus = null
            chromeProblem = ""
        }
    }

    Timer {
        interval: 1500
        repeat: true
        running: root.visible && !root.browserSection
        onTriggered: root.loadHelpers()
    }

    Timer {
        interval: 2500
        repeat: true
        running: root.browserSetupVisible
        onTriggered: root.loadChromeStatus()
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
            textFormat: Text.PlainText
            text: root.hasWindowsIntegration
                ? qsTr("Choose Add to Chrome on the listing, then open Auralis from Chrome’s Extensions menu to verify the connection. Chrome updates the store extension automatically.")
                : qsTr("Chrome Web Store setup and bundled browser registration are available on Windows.")
        }

        Flow {
            Layout.fillWidth: true
            visible: root.hasWindowsIntegration
            spacing: 8

            GlassButton {
                objectName: "openChromeExtensionStore"
                text: root.chromeStoreUsed ? qsTr("View in Chrome Web Store") : qsTr("Get from Chrome Web Store")
                accent: root.colors.positive
                filled: !root.chromeStoreUsed
                enabled: root.chromeStoreAvailable && !root.browserRequest
                onClicked: root.extensionAction("openChromeExtensionStore")
            }

            GlassButton {
                objectName: "openChromeExtensions"
                text: qsTr("Manage Chrome extensions")
                enabled: Boolean(root.chromeStatus?.chromeDetected) && !root.browserRequest
                onClicked: root.extensionAction("openChromeExtensions")
            }
        }

        Label {
            Layout.fillWidth: true
            visible: root.hasWindowsIntegration
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            color: root.chromeProblem ? root.colors.destructive : root.colors.muted
            text: root.chromeProblem || (!root.chromeStatus ? qsTr("Checking for Google Chrome…")
                : root.chromeStatus.chromeDetected ? qsTr("Google Chrome detected.")
                : qsTr("Auralis could not locate Chrome. You can still open the store listing."))
        }

        Label {
            Layout.fillWidth: true
            visible: root.chromeStoreAvailable || root.chromeVerifiedRecently
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            color: root.chromeVerifiedRecently ? root.colors.positive : root.colors.muted
            text: {
                if (root.chromeVerifiedRecently)
                    return qsTr("Chrome Web Store extension connection verified recently.")
                if (root.chromeStoreUsed)
                    return qsTr("The store extension has connected before. Open Auralis in Chrome to verify the connection now.")
                if (root.chromeStatus?.chromePreviouslyConnected)
                    return qsTr("Chrome has connected before. The store extension connection is still unverified.")
                return qsTr("Waiting for the Chrome Web Store extension to connect.")
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.topMargin: 6
            visible: root.hasWindowsIntegration
            color: root.colors.ink
            font.weight: Font.DemiBold
            text: qsTr("Manual setup and repair")
        }

        Label {
            Layout.fillWidth: true
            visible: root.hasWindowsIntegration
            color: root.colors.muted
            wrapMode: Text.WordWrap
            text: qsTr("For the bundled extension, open Extensions in Chrome or Edge, enable Developer mode, and choose Load unpacked. Use Repair browser connection if the extension cannot reach Auralis.")
        }

        Flow {
            Layout.fillWidth: true
            visible: root.hasWindowsIntegration
            spacing: 8

            GlassButton {
                text: qsTr("Open extension folder")
                enabled: !root.browserRequest
                onClicked: root.extensionAction("openExtensionFolder")
            }
            GlassButton {
                text: qsTr("Repair browser connection")
                enabled: !root.browserRequest
                onClicked: root.extensionAction("registerBrowserHost")
            }
        }

        Label {
            Layout.fillWidth: true
            visible: root.browserRequest || root.extensionMessage.length > 0
            text: root.browserRequest ? qsTr("Preparing browser integration…") : root.extensionMessage
            textFormat: Text.PlainText
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

        Switch {
            visible: root.hasWindowsIntegration
            text: qsTr("Check for Auralis updates automatically")
            checked: root.automaticChecks
            onToggled: root.automaticChecksRequested(checked)
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.hasWindowsIntegration
            Label {
                Layout.fillWidth: true
                text: qsTr("Update notification")
                color: root.colors.text
                wrapMode: Text.WordWrap
            }
            GlassComboBox {
                Layout.fillWidth: true
                Layout.preferredWidth: 275
                model: root.presentationOptions
                textRole: "label"
                valueRole: "value"
                currentIndex: Math.max(0, root.presentationOptions.findIndex(choice => choice.value === root.updatePresentation))
                enabled: root.automaticChecks
                Accessible.name: qsTr("Update notification")
                onActivated: root.updatePresentationRequested(currentValue)
            }
        }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: root.colors.muted
            text: {
                if (!root.hasWindowsIntegration) return qsTr("The installer updater is available on Windows.")
                return root.release ? qsTr("Auralis %1 is available.").arg(root.release.version) : ""
            }
            visible: text.length > 0
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8
            visible: root.hasWindowsIntegration

            GlassButton {
                text: qsTr("Check for updates")
                onClicked: root.updateCheckRequested()
            }

            GlassButton {
                text: qsTr("Review update")
                visible: Boolean(root.release && root.release.state === "available")
                onClicked: root.updateDetailsRequested()
            }
        }
    }
}
