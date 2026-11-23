pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root

    property bool monitoring: false
    property bool showManualTools: false
    property bool platformSupported: Qt.platform.os === "windows"
    property int verificationTimeout: 90000
    property bool checked: false
    property bool checking: false
    property string activeAction: ""
    property var status: null
    property string problem: ""
    property string feedback: ""
    property bool feedbackFailed: false
    property string confirmationBrowserId: ""
    property string confirmationBrowserName: ""
    property string removalBrowserId: ""
    property string removalBrowserName: ""
    property string installConfirmationDetails: ""
    property bool advancedOpen: false
    property var attempts: ({})
    readonly property var colors: MaterialTheme.palette
    readonly property bool acting: activeAction.length > 0
    readonly property bool hasStore: Boolean(!problem && status?.browserSupported && status?.storeUrl)
    readonly property bool installed: Boolean(status?.connectedRecently || status?.extensionPresent)
    readonly property bool needsSetup: hasStore && !installed && !status?.policyInstalled
    readonly property bool supportedBrowser: status?.browserId === "chrome" || status?.browserId === "edge"
    readonly property bool needsHostRepair: Boolean(!problem && status?.browserSupported && supportedBrowser
        && status?.nativeHostRegistered === false && status?.nativeHostProblem
        && (installed || status?.policyInstalled))
    readonly property bool automaticAvailable: needsSetup && supportedBrowser && Boolean(status?.silentInstallAvailable)
    readonly property bool canUndo: showManualTools && !problem && supportedBrowser && Boolean(status?.policyRemovable)
    readonly property var attempt: attempts[status?.browserId]
    readonly property bool pending: !installed && attempt?.state === "pending"
    readonly property bool manualAvailable: hasStore && !installed && Boolean(attempt?.state && !pending)
    readonly property bool confirming: Boolean(confirmationBrowserId || removalBrowserId)

    signal installAccepted()

    spacing: 8

    function recordAttempt(browserId, state) {
        const expires = state === "pending" ? Date.now() + verificationTimeout : 0
        attempts = Object.assign({}, attempts, {[browserId]: state ? {state: state, expires: expires} : null})
    }

    function refresh() {
        if (!platformSupported) {
            checked = true
            return
        }
        if (checking || acting)
            return
        checking = true
        engine.request({local: "browserExtensionStatus"}, function(value, error) {
            if (!error && value) {
                if (status?.browserId !== value.browserId) {
                    cancelConfirmation()
                    advancedOpen = false
                    feedback = ""
                    feedbackFailed = false
                }
                status = value
                problem = ""
                const browserId = value.browserId
                const previous = attempts[browserId]
                if (confirmationBrowserId) {
                    if (installed || value.policyInstalled) {
                        cancelConfirmation()
                    } else if (!automaticAvailable) {
                        cancelConfirmation()
                        recordAttempt(browserId, "unavailable")
                    }
                }
                if (previous && (value.extensionPresent || value.connectedRecently)) {
                    recordAttempt(browserId, "")
                    feedback = ""
                    feedbackFailed = false
                } else if (previous?.state === "pending") {
                    if (value.policyState === "blocked")
                        recordAttempt(browserId, "failed")
                    else if (Date.now() >= previous.expires)
                        recordAttempt(browserId, "timeout")
                } else if (browserId && value.policyInstalled && !installed && !previous) {
                    recordAttempt(browserId, "pending")
                }
            } else {
                problem = qsTr("Could not check your browser setup.")
            }
            checking = false
            checked = true
        })
    }

    function offerInstall(browserId) {
        if (!needsSetup || acting || checking || status?.browserId !== browserId)
            return
        feedback = ""
        feedbackFailed = false
        if (!automaticAvailable) {
            recordAttempt(browserId, "unavailable")
            return
        }
        confirmationBrowserId = browserId
        confirmationBrowserName = status.browser
    }

    function cancelConfirmation() {
        confirmationBrowserId = ""
        confirmationBrowserName = ""
        removalBrowserId = ""
        removalBrowserName = ""
    }

    function perform(action, browserId) {
        if (acting || checking || !browserId || status?.browserId !== browserId)
            return
        const install = action === "installBrowserExtensionPolicy"
        const undo = action === "removeBrowserExtensionPolicy"
        const openStore = action === "openBrowserExtensionStore"
        const repair = action === "registerBrowserHost"
        activeAction = action
        feedback = ""
        feedbackFailed = false
        engine.request({local: action, expectedBrowser: browserId}, function(value, error) {
            if (error || !value?.ok) {
                if (install) {
                    recordAttempt(browserId, "failed")
                } else {
                    feedbackFailed = true
                    feedback = undo ? qsTr("Could not undo the automatic extension setup.")
                        : repair ? qsTr("Could not repair the browser connection.")
                        : qsTr("Could not open your browser.")
                }
            } else if (install) {
                recordAttempt(browserId, "pending")
            } else if (openStore) {
                feedback = qsTr("Follow the browser prompts to add the extension, then open the Auralis toolbar icon to verify the connection.")
                if (value.nativeHostRegistered === false)
                    feedback += " " + qsTr("If it cannot connect, return here to repair the connection.")
            } else if (undo) {
                recordAttempt(browserId, "")
                feedback = qsTr("Automatic setup was removed. Reopen your browser to apply the change.")
            } else if (repair) {
                feedback = qsTr("Browser connection repaired. Reopen your browser and open the Auralis toolbar icon.")
            }
            activeAction = ""
            refresh()
        })
    }

    onMonitoringChanged: {
        if (monitoring)
            refresh()
        else {
            cancelConfirmation()
            advancedOpen = false
        }
    }
    Component.onCompleted: if (monitoring) refresh()

    Timer {
        interval: 2500
        repeat: true
        running: root.monitoring && root.platformSupported
        onTriggered: root.refresh()
    }

    Label {
        Layout.fillWidth: true
        text: qsTr("Auralis browser extension")
        color: root.colors.ink
        font.pixelSize: TypographyScale.pixels(17)
        font.weight: Font.DemiBold
    }

    Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        color: root.problem || root.manualAvailable ? root.colors.destructive
            : root.status?.connectedRecently ? root.colors.positive : root.colors.muted
        text: {
            const browser = root.status?.browser
            if (!root.platformSupported)
                return qsTr("Guided browser extension setup is available on Windows.")
            if (root.problem)
                return root.problem
            if (!root.checked)
                return qsTr("Checking your default browser…")
            if (!browser)
                return qsTr("Auralis could not detect your default browser.")
            if (!root.status?.browserSupported)
                return qsTr("Guided extension setup is unavailable for your default browser, %1.").arg(browser)
            if (root.status?.connectedRecently)
                return qsTr("Verified the Auralis extension connection in %1.").arg(browser)
            if (root.status?.extensionPresent)
                return qsTr("Auralis found the extension in %1. Open its toolbar icon to verify the connection.").arg(browser)
            if (root.activeAction === "installBrowserExtensionPolicy")
                return qsTr("Starting extension installation in %1…").arg(browser)
            if (root.pending)
                return qsTr("Close all %1 windows, then reopen the browser to finish installing. Open the Auralis toolbar icon to verify the connection.").arg(browser)
            if (root.manualAvailable) {
                if (root.attempt.state === "unavailable")
                    return qsTr("Automatic installation is unavailable in %1. You can install the extension manually.").arg(browser)
                if (root.attempt.state === "timeout")
                    return qsTr("Auralis could not verify installation in %1. You can install the extension manually.").arg(browser)
                return qsTr("Automatic installation did not complete in %1. You can install the extension manually.").arg(browser)
            }
            if (root.status?.storePreviouslyConnected)
                return qsTr("The extension previously connected in %1. Open its toolbar icon if it’s still installed.").arg(browser)
            if (root.status?.browserPreviouslyConnected)
                return qsTr("%1 has connected before. Open the Auralis toolbar icon to verify the extension.").arg(browser)
            return qsTr("Install the extension in %1 to send browser downloads to Auralis.").arg(browser)
        }
    }

    Flow {
        Layout.fillWidth: true
        spacing: 8
        visible: !root.confirming && !root.problem

        GlassButton {
            objectName: "installBrowserExtension"
            text: qsTr("Install extension")
            visible: root.needsSetup && !root.manualAvailable && !root.pending
            enabled: !root.acting && !root.checking
            accent: root.colors.positive
            filled: true
            onClicked: root.offerInstall(root.status?.browserId)
        }

        GlassButton {
            objectName: "openBrowserExtensionStore"
            text: qsTr("Install manually")
            visible: root.manualAvailable
            enabled: !root.acting && !root.checking
            accent: root.colors.positive
            filled: true
            onClicked: root.perform("openBrowserExtensionStore", root.status?.browserId)
        }

        GlassButton {
            objectName: "manageBrowserExtensions"
            text: qsTr("Manage browser extensions")
            visible: root.hasStore && root.installed
            enabled: !root.acting && !root.checking
            onClicked: root.perform("openBrowserExtensions", root.status?.browserId)
        }

        GlassButton {
            objectName: "repairDetectedBrowserHost"
            text: qsTr("Repair browser connection")
            visible: root.needsHostRepair && (root.installed || root.advancedOpen)
            enabled: !root.acting && !root.checking
            onClicked: root.perform("registerBrowserHost", root.status?.browserId)
        }

        GlassButton {
            text: qsTr("Advanced options")
            visible: root.canUndo || root.showManualTools && root.needsHostRepair && root.manualAvailable
            enabled: !root.acting
            checkable: true
            checked: root.advancedOpen
            onToggled: root.advancedOpen = checked
        }

        GlassButton {
            objectName: "requestBrowserPolicyRemoval"
            text: qsTr("Undo automatic setup…")
            visible: root.canUndo && root.advancedOpen
            enabled: !root.acting && !root.checking
            onClicked: {
                root.removalBrowserId = root.status.browserId
                root.removalBrowserName = root.status.browser
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.confirming

        Label {
            Layout.fillWidth: true
            color: root.colors.ink
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.removalBrowserId
                ? qsTr("Remove the Auralis extension setup setting for %1 from your Windows account? Reopen the browser to apply the change.").arg(root.removalBrowserName)
                : qsTr("Auralis will save an extension installation setting for %1 in your Windows account. The browser may show a notice that it is managed and ask you to restart or approve the installation.").arg(root.confirmationBrowserName)
        }

        Label {
            Layout.fillWidth: true
            visible: Boolean(root.confirmationBrowserId && root.installConfirmationDetails)
            text: root.installConfirmationDetails
            color: root.colors.muted
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8
            GlassButton {
                objectName: "confirmBrowserPolicyInstall"
                text: qsTr("Install extension")
                visible: Boolean(root.confirmationBrowserId)
                enabled: root.automaticAvailable && !root.acting && !root.checking
                    && root.confirmationBrowserId === root.status?.browserId
                accent: root.colors.positive
                filled: true
                onClicked: {
                    const browserId = root.confirmationBrowserId
                    root.cancelConfirmation()
                    root.perform("installBrowserExtensionPolicy", browserId)
                    root.installAccepted()
                }
            }
            GlassButton {
                objectName: "confirmBrowserPolicyRemoval"
                text: qsTr("Undo setup")
                visible: Boolean(root.removalBrowserId)
                enabled: root.canUndo && !root.acting && !root.checking && root.removalBrowserId === root.status?.browserId
                accent: root.colors.destructive
                onClicked: {
                    const browserId = root.removalBrowserId
                    root.cancelConfirmation()
                    root.perform("removeBrowserExtensionPolicy", browserId)
                }
            }
            GlassButton {
                text: qsTr("Cancel")
                onClicked: root.cancelConfirmation()
            }
        }
    }

    Label {
        Layout.fillWidth: true
        visible: Boolean(root.feedback)
        text: root.feedback
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        color: root.feedbackFailed ? root.colors.destructive : root.colors.muted
    }
}
