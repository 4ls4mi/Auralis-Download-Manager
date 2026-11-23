pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

DetachedDialogWindow {
    id: root

    property bool automatic: false
    property bool started: false
    property bool offered: false
    property bool deferred: false
    property bool helpersChecked: false
    property bool checkingHelpers: false
    property var helperStatus: null
    property string helperProblem: ""
    property var failures: ({})
    property var queuedHelpers: []
    property string activeHelper: ""
    property bool requestingHelper: false
    readonly property bool canCheck: automatic && engine.ready && Boolean(hostWindow?.visible)
        && hostWindow.active && hostWindow.visibility !== Window.Minimized
    readonly property bool checksComplete: helpersChecked && browserSetup.checked
    readonly property var tools: helperStatus?.tools || []
    readonly property var missingHelpers: tools.filter(tool => !tool.path).map(tool => tool.name)
    readonly property bool installerBusy: helperStatus?.job?.state === "installing"
    readonly property bool batchRunning: requestingHelper || Boolean(activeHelper) || queuedHelpers.length > 0

    title: qsTr("Set up Auralis")
    objectName: "startupSetupWindow"
    width: 560
    minimumHeight: 315

    function checkAtStartup() {
        if (!canCheck)
            return
        if (!started) {
            started = true
            checkHelpers()
            browserSetup.refresh()
        }
        offerIfNeeded()
    }

    function offerIfNeeded() {
        const missingBrowser = browserSetup.needsSetup && !browserSetup.status?.storePreviouslyConnected
        if (canCheck && checksComplete && !offered && !deferred
            && (missingHelpers.length > 0 || helperProblem || missingBrowser || browserSetup.problem
                || browserSetup.needsHostRepair)) {
            offered = true
            open()
        }
    }

    function continueToApp() {
        deferred = true
        browserSetup.cancelConfirmation()
        hide()
    }

    function checkHelpers() {
        if (checkingHelpers || requestingHelper)
            return
        checkingHelpers = true
        engine.request({query: "glass-helpers"}, function(result, error) {
            checkingHelpers = false
            if (error || !result?.tools) {
                helperProblem = error || qsTr("Could not check the installed helpers.")
                helpersChecked = true
                return
            }
            helperProblem = ""
            helperStatus = result
            helpersChecked = true
            if (activeHelper && !requestingHelper && !installerBusy) {
                if (missingHelpers.includes(activeHelper)) {
                    const message = result.job?.name === activeHelper && result.job.state !== "ready"
                        ? result.job.state : qsTr("Could not verify the installation.")
                    rememberFailure(activeHelper, message)
                }
                activeHelper = ""
            }
            installNext()
        })
    }

    function rememberFailure(name, message) {
        const updated = Object.assign({}, failures)
        updated[name] = message
        failures = updated
    }

    function installMissing() {
        if (batchRunning || missingHelpers.length === 0)
            return
        failures = ({})
        queuedHelpers = missingHelpers.slice()
        installNext()
    }

    function installNext() {
        if (!engine.ready || checkingHelpers || requestingHelper || activeHelper || installerBusy || queuedHelpers.length === 0)
            return
        const absent = queuedHelpers.filter(name => missingHelpers.includes(name))
        queuedHelpers = absent.slice(1)
        if (absent.length === 0)
            return
        const name = absent[0]
        activeHelper = name
        requestingHelper = true
        engine.request({action: "glass-helpers", queue: JSON.stringify({name: name})}, function(result, error) {
            requestingHelper = false
            if (error || !result?.ok) {
                rememberFailure(name, error || qsTr("Could not start the installation."))
                activeHelper = ""
            }
            checkHelpers()
        })
    }

    onCanCheckChanged: if (canCheck) Qt.callLater(checkAtStartup)
    onChecksCompleteChanged: offerIfNeeded()
    Component.onCompleted: if (canCheck) Qt.callLater(checkAtStartup)
    onDismissRequested: continueToApp()
    onOpened: continueButton.forceActiveFocus()

    Timer {
        interval: 1100
        repeat: true
        running: engine.ready && (root.batchRunning || (root.visible && root.visibility !== Window.Minimized))
        onTriggered: root.checkHelpers()
    }

    bodyContent: [
        Label {
            Layout.fillWidth: true
            text: qsTr("Optional setup for video, image galleries, and browser download capture. You can continue using Auralis at any time.")
            color: root.colors.muted
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
        },
        Label {
            Layout.fillWidth: true
            Layout.topMargin: 2
            text: qsTr("Video and gallery helpers")
            color: root.colors.ink
            font.pixelSize: TypographyScale.pixels(17)
            font.weight: Font.DemiBold
        },
        Repeater {
            model: root.tools
            delegate: RowLayout {
                id: row
                required property var modelData
                Layout.fillWidth: true
                spacing: 8

                Label {
                    Layout.fillWidth: true
                    color: root.colors.ink
                    text: row.modelData.name === "yt-dlp" ? qsTr("yt-dlp · Video downloads")
                        : row.modelData.name === "ffmpeg" ? qsTr("FFmpeg · Join and convert media")
                        : qsTr("gallery-dl · Image galleries")
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                }

                Label {
                    readonly property string error: root.failures[row.modelData.name] || ""
                    Layout.maximumWidth: 235
                    color: error ? root.colors.destructive : row.modelData.path ? root.colors.positive : root.colors.muted
                    text: error || (root.activeHelper === row.modelData.name ? qsTr("Installing…")
                        : row.modelData.path ? qsTr("Installed") : qsTr("Missing"))
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                }
            }
        },
        Label {
            Layout.fillWidth: true
            visible: Boolean(root.helperProblem) || !root.helpersChecked
            text: root.helperProblem || qsTr("Checking installed helpers…")
            color: root.helperProblem ? root.colors.destructive : root.colors.muted
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
        },
        BrowserSetupOptions {
            id: browserSetup
            objectName: "startupBrowserSetupOptions"
            Layout.fillWidth: true
            Layout.topMargin: 8
            monitoring: root.visible && root.visibility !== Window.Minimized
            installConfirmationDetails: root.missingHelpers.length > 0 && !root.batchRunning && !root.installerBusy
                ? qsTr("This also starts installing the missing video and gallery helpers.") : ""
            onInstallAccepted: root.installMissing()
        },
        Flow {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8
            visible: root.missingHelpers.length > 0

            GlassButton {
                objectName: "installMissingComponents"
                text: root.batchRunning ? qsTr("Installing helpers…") : qsTr("Install missing helpers")
                accent: root.colors.positive
                enabled: engine.ready && !root.batchRunning && !root.installerBusy
                onClicked: root.installMissing()
            }
        }
    ]

    footer: Item {
        implicitHeight: actions.implicitHeight + 20
        GlassSurface { anchors.fill: parent; material: root.material; role: "footer" }
        RowLayout {
            id: actions
            anchors.fill: parent
            anchors.margins: 10
            Label {
                Layout.fillWidth: true
                visible: root.batchRunning
                text: qsTr("Helper installs can finish in the background.")
                color: root.colors.muted
                wrapMode: Text.WordWrap
            }
            Item { Layout.fillWidth: true; visible: !root.batchRunning }
            GlassButton {
                id: continueButton
                objectName: "continueStartupSetup"
                text: qsTr("Continue to Auralis")
                accent: root.colors.accent
                onClicked: root.continueToApp()
            }
        }
    }
}
