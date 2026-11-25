pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root

    property bool monitoring: false
    property bool showManualTools: false
    property bool platformSupported: Qt.platform.os === "windows"
    property bool checked: false
    property bool checking: false
    property string activeAction: ""
    property var status: null
    property string preferredBrowser: ""
    readonly property var installedBrowsers: Array.from(status?.installedBrowsers || [])
    property string problem: ""
    property string feedback: ""
    property bool feedbackFailed: false
    property string removalAction: ""
    property string removalBrowserId: ""
    readonly property var colors: MaterialTheme.palette
    readonly property bool acting: activeAction.length > 0
    readonly property bool hasStore: Boolean(!problem && status?.browserSupported && status?.storeUrl)
    readonly property bool installed: status?.extensionDiscovery !== "missing"
        && Boolean(status?.connectedRecently || status?.extensionPresent)
    readonly property bool legacySetup: Boolean(hasStore && status?.legacyPolicyRemovable)
    readonly property bool chromeOffer: Boolean(hasStore && status?.browserId === "chrome"
        && status?.externalOfferRegistered)
    readonly property bool canOffer: hasStore && !installed && !legacySetup && status?.browserId === "chrome"
        && Boolean(status?.externalOfferAvailable)
    readonly property bool offerAtStartup: hasStore && !installed && !chromeOffer && !legacySetup
        && (status?.extensionDiscovery === "missing" || canOffer)
        && !status?.extensionPreviouslyConnected && !status?.storePreviouslyConnected
        && !status?.browserPreviouslyConnected
    readonly property bool canReset: showManualTools && hasStore
    readonly property bool confirming: removalAction.length > 0
    readonly property bool canConfirmRemoval: canReset && removalBrowserId === status?.browserId
        && (removalAction === "removeLegacyBrowserExtensionPolicy" ? legacySetup : Boolean(status?.externalOfferRemovable))
    readonly property bool hostNeedsAttention: Boolean(hasStore && status?.nativeHostRegistered === false
        && status?.nativeHostProblem)
    readonly property bool canRepairHost: hostNeedsAttention && status?.nativeHostCanRegister === true

    spacing: 8

    function cancelConfirmation() {
        removalAction = ""
        removalBrowserId = ""
    }

    function refresh(reportReset = false) {
        if (!platformSupported) {
            checked = true
            return
        }
        if (checking || acting)
            return
        checking = true
        engine.request({local: "browserExtensionStatus", browserExecutable: preferredBrowser}, function(value, error) {
            if (error || !value) {
                problem = qsTr("Could not check your browser setup.")
            } else {
                const browserChanged = status?.browserExecutable !== value.browserExecutable
                const previouslyInstalled = installed
                if (preferredBrowser && preferredBrowser !== value.browserExecutable)
                    preferredBrowser = ""
                status = value
                problem = ""
                if (browserChanged || (!previouslyInstalled && installed)) {
                    feedback = ""
                    feedbackFailed = false
                }
                if (confirming && !canConfirmRemoval)
                    cancelConfirmation()
                if (reportReset && !browserChanged) {
                    feedback = installed
                        ? qsTr("To remove Auralis, use the Extensions page in %1.").arg(value.browser)
                        : qsTr("Browser setup checked again.")
                    feedbackFailed = false
                }
            }
            checking = false
            checked = true
        })
    }

    function resetSetup() {
        if (!canReset || checking || acting || confirming)
            return
        if (legacySetup || status.externalOfferRemovable) {
            removalBrowserId = status.browserId
            removalAction = legacySetup ? "removeLegacyBrowserExtensionPolicy" : "removeBrowserExtensionOffer"
        } else {
            refresh(true)
        }
    }

    function perform(action, browserId) {
        if (acting || checking || !browserId || status?.browserId !== browserId)
            return
        activeAction = action
        feedback = ""
        feedbackFailed = false
        engine.request({local: action, expectedBrowser: browserId,
            browserExecutable: status.browserExecutable}, function(value, error) {
            if (error || !value?.ok) {
                feedbackFailed = true
                feedback = error || value?.message || qsTr("Could not complete browser setup.")
            } else if (action === "offerBrowserExtension" && !value.alreadyInstalled && !value.browserOpened) {
                feedback = qsTr("Open Chrome to check for the extension offer.")
            } else if (action === "openBrowserExtensionStore") {
                feedback = installed ? qsTr("Opened the Auralis extension page.")
                    : browserId === "edge" ? qsTr("Open the Chrome Web Store in Edge and follow its prompts. If Edge asks, allow extensions from other stores, then add Auralis.")
                    : qsTr("Follow the browser prompts to add the extension, then open the Auralis toolbar icon to verify the connection.")
                if (value.nativeHostRegistered === false)
                    feedback += " " + qsTr("If it cannot connect, return here to repair the connection.")
            } else if (action === "removeBrowserExtensionOffer") {
                feedback = qsTr("Chrome’s extension offer was removed. If Auralis is still listed, remove it from Chrome’s Extensions page.")
            } else if (action === "removeLegacyBrowserExtensionPolicy") {
                feedback = value.refreshRequested
                    ? qsTr("Automatic setup was removed. Auralis asked %1 to reload its settings.").arg(status.browser)
                    : qsTr("Automatic setup was removed. Reopen your browser to apply the change.")
            } else if (action === "registerBrowserHost") {
                feedback = qsTr("Browser connection repaired. Reopen your browser and open the Auralis toolbar icon.")
            }
            activeAction = ""
            refresh()
        })
    }

    onMonitoringChanged: {
        if (monitoring)
            refresh()
        else
            cancelConfirmation()
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

    GlassComboBox {
        objectName: "installedBrowserSelector"
        Layout.fillWidth: true
        visible: root.installedBrowsers.length > 1
        enabled: visible && !root.acting && !root.checking && !root.confirming
        model: root.installedBrowsers
        textRole: "name"
        valueRole: "executable"
        currentIndex: root.installedBrowsers.findIndex(browser => browser.executable === root.status?.browserExecutable)
        Accessible.name: qsTr("Installed browsers")
        onActivated: {
            root.preferredBrowser = currentValue
            root.refresh()
        }
    }

    Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: root.colors.muted
        text: qsTr("With the Auralis extension installed, download capture supports Chrome, Edge, Brave, Chromium, Vivaldi, Opera and Opera GX, Helium, Thorium, Firefox, Zen, LibreWolf, Floorp, and Waterfox. Safari is supported on macOS. Install the extension separately in each browser.")
    }

    Label {
        objectName: "browserSetupStatus"
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        color: root.problem ? root.colors.destructive : root.installed && root.status?.connectedRecently
            ? root.colors.positive : root.colors.muted
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
                return qsTr("The Chrome Web Store listing is unavailable in %1. Choose a Chromium browser such as Brave, Chrome, or Edge.").arg(browser)
            if (root.installed && root.status?.connectedRecently)
                return qsTr("Verified the Auralis extension connection in %1.").arg(browser)
            if (root.installed && root.hostNeedsAttention)
                return qsTr("Auralis found the extension in %1, but its browser connection is unavailable.").arg(browser)
            if (root.installed && root.chromeOffer && !root.legacySetup)
                return qsTr("If Chrome shows New extension added, choose Enable extension. Then open Auralis’s toolbar icon to verify the connection.")
            if (root.installed)
                return qsTr("Auralis found the extension in %1. Open its toolbar icon to verify the connection.").arg(browser)
            if (root.legacySetup)
                return qsTr("Clear the previous automatic setup in Browser integration.")
            if (root.activeAction === "offerBrowserExtension")
                return qsTr("Preparing the extension offer in Chrome…")
            if (root.chromeOffer)
                return qsTr("Check Chrome’s menu for New extension added, then choose Enable extension. Reopen Chrome if the offer is missing.")
            return qsTr("Install the extension in %1 to send browser downloads to Auralis.").arg(browser)
        }
    }

    Label {
        Layout.fillWidth: true
        visible: !root.confirming && (root.canOffer || (root.legacySetup && root.showManualTools))
        text: root.legacySetup
            ? qsTr("Reset extension setup clears the previous setting Auralis saved.")
            : qsTr("Chrome asks for your confirmation before enabling the extension.")
        color: root.colors.muted
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
    }

    Flow {
        Layout.fillWidth: true
        spacing: 8
        visible: !root.confirming && !root.problem

        GlassButton {
            objectName: "offerBrowserExtension"
            text: root.chromeOffer ? qsTr("Open Chrome") : qsTr("Offer in Chrome")
            visible: root.canOffer
            enabled: !root.acting && !root.checking
            accent: root.colors.positive
            filled: true
            onClicked: root.perform("offerBrowserExtension", root.status.browserId)
        }

        GlassButton {
            objectName: "openBrowserExtensionStore"
            text: root.installed ? qsTr("Open Chrome Web Store") : qsTr("Install")
            visible: root.hasStore
            enabled: !root.acting && !root.checking
            accent: root.colors.positive
            filled: !root.installed && !root.canOffer
            onClicked: root.perform("openBrowserExtensionStore", root.status.browserId)
        }

        GlassButton {
            objectName: "resetBrowserSetup"
            text: qsTr("Reset extension setup")
            visible: root.canReset
            enabled: !root.acting && !root.checking
            onClicked: root.resetSetup()
        }

        GlassButton {
            objectName: "repairDetectedBrowserHost"
            text: qsTr("Repair browser connection")
            visible: root.canRepairHost
            enabled: !root.acting && !root.checking
            onClicked: root.perform("registerBrowserHost", root.status.browserId)
        }
    }

    Label {
        readonly property string detail: root.hostNeedsAttention ? root.status?.nativeHostProblem || ""
            : root.hasStore && !root.installed && !root.legacySetup && !root.canOffer
                ? root.status?.externalOfferProblem || "" : ""
        Layout.fillWidth: true
        visible: !root.confirming && detail.length > 0 && detail !== root.feedback
        text: detail
        color: root.colors.muted
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.confirming

        Label {
            Layout.fillWidth: true
            color: root.colors.ink
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            text: root.removalAction === "removeLegacyBrowserExtensionPolicy"
                ? qsTr("Clear the previous automatic setup Auralis saved for %1?").arg(root.status?.browser || "")
                : qsTr("Remove the extension offer that Auralis registered in Chrome?")
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8
            GlassButton {
                objectName: "confirmBrowserSetupRemoval"
                text: qsTr("Reset setup")
                enabled: root.canConfirmRemoval && !root.acting && !root.checking
                accent: root.colors.destructive
                onClicked: {
                    const action = root.removalAction
                    const browserId = root.removalBrowserId
                    root.cancelConfirmation()
                    root.perform(action, browserId)
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
        visible: root.feedback.length > 0 && !root.confirming
        text: root.feedback
        color: root.feedbackFailed ? root.colors.destructive : root.colors.muted
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
    }
}
