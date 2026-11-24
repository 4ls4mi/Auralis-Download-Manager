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
    property string removalBrowserId: ""
    property string removalBrowserName: ""
    property bool removalForReset: false
    property var resetRemoval: null
    property string installDetails: ""
    property bool advancedOpen: false
    property var attempts: ({})
    readonly property var colors: MaterialTheme.palette
    readonly property bool acting: activeAction.length > 0
    readonly property bool hasStore: Boolean(!problem && status?.browserSupported && status?.storeUrl)
    readonly property bool installed: status?.extensionDiscovery !== "missing"
        && Boolean(status?.connectedRecently || status?.extensionPresent)
    readonly property bool needsSetup: hasStore && !installed
    readonly property bool savedSetup: needsSetup && Boolean(status?.policyInstalled)
    readonly property bool extensionMissing: !installed && status?.extensionDiscovery === "missing"
    readonly property bool supportedBrowser: status?.browserId === "chrome" || status?.browserId === "edge"
    readonly property bool hostNeedsAttention: Boolean(!problem && status?.browserSupported && supportedBrowser
        && status?.nativeHostRegistered === false && status?.nativeHostProblem)
    readonly property bool automaticAvailable: needsSetup && supportedBrowser
        && Boolean(status?.silentInstallAvailable)
    readonly property bool offerAtStartup: needsSetup && !savedSetup && (extensionMissing || automaticAvailable)
        && !status?.extensionPreviouslyConnected && !status?.storePreviouslyConnected
        && !status?.browserPreviouslyConnected
    readonly property bool canUndo: showManualTools && !problem && supportedBrowser && Boolean(status?.policyRemovable)
    readonly property bool canReset: showManualTools && hasStore && supportedBrowser
    readonly property bool canConfirmRemoval: removalForReset ? canReset : canUndo
    readonly property var attempt: attempts[status?.browserId]
    readonly property bool pending: !installed && attempt?.state === "pending"
    readonly property bool automaticBlocked: needsSetup && !savedSetup && supportedBrowser && !automaticAvailable
    readonly property bool attemptNeedsAttention: !installed && Boolean(attempt?.state && !pending)
    readonly property string attemptError: attempt?.state === "failed" ? attempt.detail || "" : ""
    readonly property bool needsHostRepair: hostNeedsAttention && status?.nativeHostCanRegister === true
        && (installed || status?.policyInstalled || automaticBlocked || attemptNeedsAttention)
    readonly property string setupDetail: {
        if (problem)
            return ""
        if (automaticBlocked || attemptNeedsAttention) {
            const detail = status?.policyState === "blocked" ? status?.policyProblem || ""
                : hostNeedsAttention ? status.nativeHostProblem : ""
            return detail === attemptError ? "" : detail
        }
        return hostNeedsAttention && (installed || status?.policyInstalled) ? status.nativeHostProblem : ""
    }
    readonly property bool confirming: Boolean(removalBrowserId)
    readonly property string feedbackText: {
        if (!resetRemoval)
            return feedback
        const browser = status?.browser || ""
        if (resetRemoval.setupRemoved)
            return removedSetupMessage(browser, resetRemoval.refreshRequested) + " "
                + qsTr("If Auralis is still listed, remove it from the Extensions page in %1.").arg(browser)
        return qsTr("Open the Extensions page in %1, remove Auralis, and confirm in the browser.").arg(browser)
    }

    signal installAccepted()

    spacing: 8

    function removedSetupMessage(browser, refreshRequested) {
        return refreshRequested ? qsTr("Automatic setup was removed. Auralis asked %1 to reload its settings.").arg(browser)
            : qsTr("Automatic setup was removed. Reopen your browser to apply the change.")
    }

    function recordAttempt(browserId, state, detail = "", refreshRequested = false) {
        const expires = state === "pending" ? Date.now() + verificationTimeout : 0
        attempts = Object.assign({}, attempts, {[browserId]: state ? {state, expires, detail, refreshRequested} : null})
    }

    function refresh(afterCheck = null) {
        if (!platformSupported) {
            checked = true
            return
        }
        if (checking || acting)
            return
        checking = true
        engine.request({local: "browserExtensionStatus"}, function(value, error) {
            if (!error && value) {
                const browserId = value.browserId
                const sameBrowser = status?.browserId === browserId
                const newlySaved = sameBrowser && !status?.policyInstalled && value.policyInstalled
                const previouslyInstalled = installed
                const previouslyConnected = Boolean(status?.connectedRecently)
                if (!sameBrowser) {
                    cancelConfirmation()
                    advancedOpen = false
                    feedback = ""
                    feedbackFailed = false
                    resetRemoval = null
                }
                status = value
                problem = ""
                const previous = attempts[browserId]
                if (removalBrowserId && !canConfirmRemoval)
                    cancelConfirmation()
                if (installed) {
                    if (previous)
                        recordAttempt(browserId, "")
                    if (previous || !previouslyInstalled || (value.connectedRecently && !previouslyConnected)) {
                        feedback = ""
                        feedbackFailed = false
                    }
                } else if (previous?.state === "pending") {
                    if (value.policyState === "blocked")
                        recordAttempt(browserId, "failed", value.policyProblem || "")
                    else if (!value.policyInstalled)
                        recordAttempt(browserId, "failed", qsTr("Auralis could no longer find the saved automatic setup."))
                    else if (Date.now() >= previous.expires)
                        recordAttempt(browserId, "timeout")
                } else if (previous?.state === "failed" && newlySaved) {
                    recordAttempt(browserId, "")
                }
                if (resetRemoval && extensionMissing) {
                    resetRemoval = null
                    feedback = qsTr("The Auralis extension is no longer detected in %1.").arg(value.browser)
                }
            } else {
                problem = qsTr("Could not check your browser setup.")
            }
            checking = false
            checked = true
            if (afterCheck && !error && value)
                afterCheck()
        })
    }

    function installAutomatically() {
        if (!automaticAvailable || pending || acting || checking || confirming)
            return
        perform("installBrowserExtensionPolicy", status.browserId)
        installAccepted()
    }

    function cancelConfirmation() {
        removalBrowserId = ""
        removalBrowserName = ""
        removalForReset = false
    }

    function offerRemoval(forReset = false) {
        if (acting || checking || !(forReset ? canReset : canUndo))
            return
        cancelConfirmation()
        removalForReset = forReset
        removalBrowserId = status.browserId
        removalBrowserName = status.browser
    }

    function resetSetup() {
        if (!canReset || acting || checking || confirming)
            return
        const browserId = status.browserId
        refresh(function() {
            if (!visible || !canReset || status?.browserId !== browserId)
                return
            if (installed || status.policyRemovable) {
                offerRemoval(true)
            } else {
                recordAttempt(browserId, "")
                resetRemoval = null
                feedbackFailed = false
                feedback = extensionMissing
                    ? qsTr("Auralis found no extension setup to reset in %1.").arg(status.browser)
                    : qsTr("Browser setup checked again.")
            }
        })
    }

    function perform(action, browserId) {
        if (acting || checking || !browserId || status?.browserId !== browserId)
            return
        const install = action === "installBrowserExtensionPolicy"
        const undo = action === "removeBrowserExtensionPolicy"
        const reset = action === "resetBrowserExtensionSetup"
        const openStore = action === "openBrowserExtensionStore"
        const repair = action === "registerBrowserHost"
        activeAction = action
        feedback = ""
        feedbackFailed = false
        resetRemoval = null
        const command = {local: action, expectedBrowser: browserId}
        engine.request(command, function(value, error) {
            if (error || !value?.ok) {
                if (install) {
                    recordAttempt(browserId, "failed", error || value?.message || "")
                } else {
                    feedbackFailed = true
                    feedback = undo ? (error || value?.message || qsTr("Could not undo the automatic extension setup."))
                        : reset ? (error || value?.message || qsTr("Could not reset the Auralis extension setup."))
                        : repair ? qsTr("Could not repair the browser connection.")
                        : qsTr("Could not open your browser.")
                }
            } else if (install) {
                if (value.pending && !value.alreadyInstalled)
                    recordAttempt(browserId, "pending", "", Boolean(value.refreshRequested))
                else
                    recordAttempt(browserId, "")
            } else if (openStore) {
                feedback = installed ? qsTr("Opened the Auralis extension page.")
                    : browserId === "edge" ? qsTr("Open the Chrome Web Store in Edge and follow its prompts. If Edge asks, allow extensions from other stores, then add Auralis.")
                    : qsTr("Follow the browser prompts to add the extension, then open the Auralis toolbar icon to verify the connection.")
                if (value.nativeHostRegistered === false)
                    feedback += " " + qsTr("If it cannot connect, return here to repair the connection.")
            } else if (undo) {
                recordAttempt(browserId, "")
                feedback = removedSetupMessage(status.browser, value.refreshRequested)
            } else if (reset) {
                recordAttempt(browserId, "")
                if (value.removalNeeded)
                    resetRemoval = {refreshRequested: Boolean(value.refreshRequested), setupRemoved: Boolean(value.setupRemoved)}
                else if (value.setupRemoved)
                    feedback = removedSetupMessage(status.browser, value.refreshRequested)
                else
                    feedback = qsTr("Browser setup checked again.")
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
        objectName: "browserSetupStatus"
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        color: root.problem || root.attemptNeedsAttention || root.automaticBlocked ? root.colors.destructive
            : !root.resetRemoval && root.installed && root.status?.connectedRecently ? root.colors.positive : root.colors.muted
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
            if (root.activeAction === "resetBrowserExtensionSetup")
                return qsTr("Resetting Auralis extension setup in %1…").arg(browser)
            if (root.resetRemoval)
                return qsTr("Waiting for %1 to confirm removal.").arg(browser)
            if (root.installed && root.status?.connectedRecently)
                return qsTr("Verified the Auralis extension connection in %1.").arg(browser)
            if (root.installed && root.status?.extensionPresent && root.needsHostRepair)
                return qsTr("Auralis found the extension in %1. Repair the browser connection, then open the Auralis toolbar icon to verify it.").arg(browser)
            if (root.installed && root.status?.extensionPresent && root.hostNeedsAttention)
                return qsTr("Auralis found the extension in %1, but its browser connection is unavailable.").arg(browser)
            if (root.installed)
                return qsTr("Auralis found the extension in %1. Open its toolbar icon to verify the connection.").arg(browser)
            if (root.activeAction === "installBrowserExtensionPolicy")
                return qsTr("Starting extension installation in %1…").arg(browser)
            if (root.pending && root.attempt?.refreshRequested)
                return qsTr("Auralis asked %1 to check the saved installation request. If the extension doesn’t appear, close and reopen the browser.").arg(browser)
            if (root.pending || (root.savedSetup && !root.attemptNeedsAttention))
                return qsTr("An installation request was saved for %1. If the extension doesn’t appear, close and reopen the browser to apply the request.").arg(browser)
            if (root.attemptNeedsAttention && root.attempt) {
                if (root.attemptError)
                    return root.attemptError
                if (root.attempt.state === "timeout" && root.status?.policyInstalled)
                    return qsTr("Automatic setup was saved for %1, but Auralis could not verify the installation. You can install the extension manually.").arg(browser)
                if (root.attempt.state === "timeout")
                    return qsTr("Auralis could not verify installation in %1. You can install the extension manually.").arg(browser)
                return qsTr("Automatic installation did not complete in %1. You can install the extension manually.").arg(browser)
            }
            if (root.automaticBlocked)
                return qsTr("Automatic installation is unavailable in %1. You can install the extension manually.").arg(browser)
            if (!root.extensionMissing && (root.status?.extensionPreviouslyConnected || root.status?.storePreviouslyConnected))
                return qsTr("The extension previously connected in %1. Open its toolbar icon if it’s still installed.").arg(browser)
            if (!root.extensionMissing && root.status?.browserPreviouslyConnected)
                return qsTr("%1 has connected before. Open the Auralis toolbar icon to verify the extension.").arg(browser)
            return qsTr("Install the extension in %1 to send browser downloads to Auralis.").arg(browser)
        }
    }

    Label {
        Layout.fillWidth: true
        visible: root.automaticAvailable && !root.confirming && !root.acting && !root.pending
            && !root.attemptNeedsAttention && (!root.savedSetup || Boolean(root.installDetails))
        text: {
            if (!visible)
                return ""
            if (root.savedSetup)
                return root.installDetails
            const description = qsTr("Auralis will save an extension installation setting for %1 in your Windows account. The browser may show a notice that it is managed and ask you to restart or approve the installation.").arg(root.status.browser)
            return root.installDetails ? description + "\n" + root.installDetails : description
        }
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: root.colors.muted
    }

    Flow {
        Layout.fillWidth: true
        spacing: 8
        visible: !root.removalBrowserId && !root.problem

        GlassButton {
            objectName: "installBrowserExtension"
            text: root.savedSetup ? qsTr("Finish setup") : qsTr("Install automatically")
            visible: root.hasStore && root.supportedBrowser && !root.installed
            enabled: root.automaticAvailable && !root.pending && !root.confirming && !root.acting && !root.checking
            accent: root.colors.positive
            filled: true
            onClicked: root.installAutomatically()
        }

        GlassButton {
            objectName: "openBrowserExtensionStore"
            text: root.installed ? qsTr("Open Chrome Web Store") : qsTr("Install manually")
            visible: root.hasStore && root.supportedBrowser
            enabled: !root.acting && !root.checking
            accent: root.colors.positive
            filled: !root.installed && !root.automaticAvailable
            onClicked: {
                root.cancelConfirmation()
                root.perform("openBrowserExtensionStore", root.status?.browserId)
            }
        }

        GlassButton {
            objectName: "resetBrowserSetup"
            text: qsTr("Reset extension setup")
            visible: root.canReset && !root.confirming
            enabled: !root.acting && !root.checking
            onClicked: root.resetSetup()
        }

        GlassButton {
            objectName: "repairDetectedBrowserHost"
            text: qsTr("Repair browser connection")
            visible: root.needsHostRepair && !root.confirming
            enabled: !root.acting && !root.checking
            onClicked: root.perform("registerBrowserHost", root.status?.browserId)
        }

        GlassButton {
            text: qsTr("Advanced options")
            visible: root.canUndo && !root.confirming
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
            onClicked: root.offerRemoval()
        }
    }

    Label {
        objectName: "browserSetupDetails"
        Layout.fillWidth: true
        visible: !root.confirming && text.length > 0
        text: root.setupDetail
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: root.colors.muted
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.confirming

        Label {
            Layout.fillWidth: true
            color: root.colors.ink
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.removalForReset
                ? qsTr("Reset Auralis extension setup for %1? Auralis will clear any automatic setup it created. If the extension is installed, remove it from the browser’s Extensions page and confirm in the browser.").arg(root.removalBrowserName)
                : qsTr("Remove the Auralis extension setup setting for %1 from your Windows account? Reopen the browser to apply the change.").arg(root.removalBrowserName)
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8
            GlassButton {
                objectName: "confirmBrowserPolicyRemoval"
                text: root.removalForReset ? qsTr("Reset setup") : qsTr("Undo setup")
                visible: Boolean(root.removalBrowserId)
                enabled: root.canConfirmRemoval && !root.acting && !root.checking && root.removalBrowserId === root.status?.browserId
                accent: root.colors.destructive
                onClicked: {
                    const browserId = root.removalBrowserId
                    const forReset = root.removalForReset
                    root.cancelConfirmation()
                    root.perform(forReset ? "resetBrowserExtensionSetup" : "removeBrowserExtensionPolicy", browserId)
                }
            }
            GlassButton {
                objectName: "cancelBrowserSetupConfirmation"
                text: qsTr("Cancel")
                onClicked: root.cancelConfirmation()
            }
        }
    }

    Label {
        Layout.fillWidth: true
        visible: Boolean(root.feedbackText)
        text: root.feedbackText
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        color: root.feedbackFailed ? root.colors.destructive : root.colors.muted
    }
}
