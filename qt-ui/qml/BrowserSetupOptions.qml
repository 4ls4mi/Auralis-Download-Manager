pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root

    property bool monitoring: false
    property bool showManualTools: false
    property bool showPolicyChoice: true
    property bool platformSupported: Qt.platform.os === "windows"
    property bool checked: false
    property bool checking: false
    property bool acting: false
    property var status: null
    property string problem: ""
    property string feedback: ""
    property string policyBrowserId: ""
    property string policyBrowserName: ""
    property bool removingPolicy: false
    property string policyConfirmationDetails: ""
    property string policyConfirmText: qsTr("Install through policy")
    readonly property var colors: MaterialTheme.palette
    readonly property bool needsSetup: Boolean(status?.browserSupported && status?.storeUrl
        && !status?.connectedRecently && !status?.extensionPresent && !status?.policyInstalled)
    readonly property bool hasStore: Boolean(status?.browserSupported && status?.storeUrl)
    readonly property bool policyAvailable: needsSetup && Boolean(status?.silentInstallAvailable && status?.browserId)
    readonly property bool policyRemovable: showManualTools && Boolean(status?.policyRemovable && status?.browserId)

    signal policyAccepted()

    spacing: 8

    function refresh() {
        if (!platformSupported) {
            checked = true
            return
        }
        if (checking)
            return
        checking = true
        engine.request({local: "browserExtensionStatus"}, function(value, error) {
            checking = false
            if (!error && value) {
                status = value
                problem = ""
            } else if (!status) {
                problem = error || qsTr("Could not check browser integration.")
            }
            checked = true
        })
    }

    function perform(action, expectedBrowser) {
        if (acting)
            return
        acting = true
        feedback = ""
        const request = {local: action}
        if (expectedBrowser)
            request.expectedBrowser = expectedBrowser
        engine.request(request, function(value, error) {
            acting = false
            if (error || !value?.ok)
                feedback = error || qsTr("Browser setup did not complete.")
            else if (value.message)
                feedback = value.message
            else if (action === "openBrowserExtensionStore")
                feedback = qsTr("Approve the extension in the browser. Open its toolbar menu to verify the connection.")
            else if (action === "installBrowserExtensionPolicy")
                feedback = qsTr("Browser policy saved. Open the browser and its Auralis toolbar menu to verify the connection.")
            else if (action === "removeBrowserExtensionPolicy")
                feedback = qsTr("Auralis removed its browser policy. Review your extensions after the browser applies the change.")
            else if (action === "registerBrowserHost")
                feedback = qsTr("Browser connection registered. Reopen your browser to reconnect.")
            else if (action === "openExtensionFolder")
                feedback = qsTr("Choose the displayed Auralis folder when loading the unpacked extension.")
            refresh()
        })
    }

    function preparePolicy(remove) {
        if (!(remove ? policyRemovable : policyAvailable) || acting)
            return
        removingPolicy = Boolean(remove)
        policyBrowserId = status.browserId
        policyBrowserName = status.browser
    }

    function cancelPolicy() {
        policyBrowserId = ""
        removingPolicy = false
    }

    onMonitoringChanged: {
        if (monitoring)
            refresh()
        else
            cancelPolicy()
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
        color: root.problem ? root.colors.destructive : root.status?.connectedRecently ? root.colors.positive : root.colors.muted
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
                return qsTr("Auralis is installed in a %1 profile. Open its toolbar menu to verify the connection.").arg(browser)
            if (root.status?.policyInstalled)
                return qsTr("Installation is pending in %1. Open the browser and its Auralis toolbar menu to verify the connection.").arg(browser)
            if (root.status?.storePreviouslyConnected)
                return qsTr("The store extension has connected in %1 before. Auralis could not verify that it is still installed.").arg(browser)
            if (root.status?.browserPreviouslyConnected)
                return qsTr("%1 has connected before. Open the Auralis toolbar menu to verify the store extension.").arg(browser)
            return qsTr("%1 is your default browser. Add the extension to send downloads to Auralis.").arg(browser)
        }
    }

    Flow {
        Layout.fillWidth: true
        spacing: 8
        visible: Boolean(root.status?.browserSupported) && !Boolean(root.policyBrowserId)

        GlassButton {
            objectName: "openBrowserExtensionStore"
            text: root.needsSetup ? qsTr("Get the extension") : qsTr("View store listing")
            accent: root.colors.positive
            filled: root.needsSetup
            enabled: root.hasStore && !root.acting
            onClicked: root.perform("openBrowserExtensionStore")
        }

        GlassButton {
            objectName: "manageBrowserExtensions"
            text: qsTr("Manage browser extensions")
            enabled: !root.acting
            onClicked: root.perform("openBrowserExtensions")
        }

        GlassButton {
            objectName: "requestBrowserPolicyInstall"
            text: qsTr("Install through browser policy…")
            visible: root.showPolicyChoice && root.policyAvailable
            enabled: !root.acting
            onClicked: root.preparePolicy()
        }

        GlassButton {
            objectName: "requestBrowserPolicyRemoval"
            text: qsTr("Remove Auralis browser policy…")
            visible: root.policyRemovable
            enabled: !root.acting
            onClicked: root.preparePolicy(true)
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: Boolean(root.policyBrowserId)

        Label {
            Layout.fillWidth: true
            color: root.colors.ink
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.removingPolicy
                ? qsTr("Remove the Auralis policy entry for %1 from your Windows account? Review the browser’s extension settings after it applies the change.").arg(root.policyBrowserName)
                : qsTr("Add the official Auralis extension in %1 using your Windows account’s browser policy? The browser may show that it’s managed. You can disable the extension in the browser’s extension settings.").arg(root.policyBrowserName)
        }

        Label {
            Layout.fillWidth: true
            visible: !root.removingPolicy && Boolean(root.policyConfirmationDetails)
            text: root.policyConfirmationDetails
            color: root.colors.muted
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8
            GlassButton {
                objectName: root.removingPolicy ? "confirmBrowserPolicyRemoval" : "confirmBrowserPolicyInstall"
                text: root.removingPolicy ? qsTr("Remove Auralis policy") : root.policyConfirmText
                enabled: !root.acting && (root.removingPolicy ? root.policyRemovable : root.policyAvailable)
                    && root.status?.browserId === root.policyBrowserId
                accent: root.removingPolicy ? root.colors.destructive : root.colors.positive
                onClicked: {
                    const browserId = root.policyBrowserId
                    const remove = root.removingPolicy
                    root.cancelPolicy()
                    root.perform(remove ? "removeBrowserExtensionPolicy" : "installBrowserExtensionPolicy", browserId)
                    if (!remove)
                        root.policyAccepted()
                }
            }
            GlassButton {
                text: qsTr("Cancel")
                onClicked: root.cancelPolicy()
            }
        }
    }

    Label {
        Layout.fillWidth: true
        visible: Boolean(root.status?.policyProblem) && !root.status?.policyInstalled
        text: root.status?.policyProblem || ""
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        color: root.colors.muted
    }

    Label {
        Layout.fillWidth: true
        Layout.topMargin: 6
        visible: root.showManualTools && root.platformSupported
        color: root.colors.ink
        font.weight: Font.DemiBold
        text: qsTr("Manual setup and repair")
    }

    Label {
        Layout.fillWidth: true
        visible: root.showManualTools && root.platformSupported
        color: root.colors.muted
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: qsTr("To use the bundled copy in Chrome or Edge, enable Developer mode on the Extensions page and choose Load unpacked.")
    }

    Flow {
        Layout.fillWidth: true
        visible: root.showManualTools && root.platformSupported
        spacing: 8
        GlassButton {
            text: qsTr("Open bundled extension folder")
            enabled: !root.acting
            onClicked: root.perform("openExtensionFolder")
        }
        GlassButton {
            text: qsTr("Repair browser connection")
            enabled: !root.acting
            onClicked: root.perform("registerBrowserHost")
        }
    }

    Label {
        Layout.fillWidth: true
        visible: root.acting || Boolean(root.feedback)
        text: root.acting ? qsTr("Preparing browser integration…") : root.feedback
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        color: root.colors.muted
    }
}
