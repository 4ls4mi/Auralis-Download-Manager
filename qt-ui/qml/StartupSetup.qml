pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtCore

DetachedDialogWindow {
    id: root

    property bool automatic: false
    required property var languages
    property bool started: false
    property bool deferred: false
    property string page: ""
    property string languageProblem: ""
    property bool helpersChecked: false
    property bool checkingHelpers: false
    property var helperStatus: null
    property string helperProblem: ""
    property var failures: ({})
    property var queuedHelpers: []
    property string activeHelper: ""
    property bool requestingHelper: false
    readonly property bool canCheck: automatic && engine.ready && Boolean(hostWindow?.visible)
        && hostWindow.visibility !== Window.Minimized
    readonly property bool blockingAnnouncements: automatic && !deferred && (preferences.languagePending || started)
    readonly property bool checksComplete: (preferences.helpersDone || helpersChecked)
        && (preferences.browserDone || browserSetup.checked)
    readonly property var tools: Array.from(helperStatus?.tools ?? [])
    readonly property var missingHelpers: helperProblem ? [] : tools.filter(tool => tool?.name
        && (tool.path === null || tool.path === "")).map(tool => tool.name)
    readonly property bool installerBusy: helperStatus?.job?.state === "installing"
    readonly property bool batchRunning: requestingHelper || Boolean(activeHelper) || queuedHelpers.length > 0
    readonly property bool needHelpers: !preferences.helpersDone
    readonly property bool needBrowser: !preferences.browserDone
    readonly property bool hasFollowingPage: page === "language" ? !checksComplete || needHelpers || needBrowser
        : page === "browser" && needHelpers
    readonly property bool canAdvance: !busy && (page === "language" ? engine.ready && languageSelector.currentIndex >= 0
        : page === "helpers" ? helpersChecked && !batchRunning && missingHelpers.length === 0
        : page === "browser" && !browserSetup.acting && browserSetup.installed)

    title: qsTr("Set up Auralis")
    objectName: "startupSetupWindow"
    width: 720
    minimumWidth: 540
    minimumHeight: 500
    customFrame: true

    Settings {
        id: preferences
        category: "FirstLaunchSetup"
        property int wizardVersion: 0
        property bool languagePending: false
        property bool helpersDone: false
        property bool browserDone: false
    }

    function present() {
        if (busy || batchRunning) {
            open()
            return
        }
        deferred = false
        started = true
        preferences.languagePending = true
        preferences.helpersDone = false
        preferences.browserDone = false
        preferences.sync()
        const selected = languages.findIndex(language => language.value === engine.interfaceLanguage)
        languageSelector.currentIndex = Math.max(0, selected)
        showPage("language")
        checkHelpers()
        browserSetup.refresh()
    }

    function checkAtStartup() {
        if (!canCheck || deferred)
            return
        if (!started) {
            started = true
            if (preferences.languagePending) {
                const selected = languages.findIndex(language => language.value === engine.interfaceLanguage)
                languageSelector.currentIndex = Math.max(0, selected)
                showPage("language")
            }
            if (!preferences.helpersDone)
                checkHelpers()
            if (!preferences.browserDone)
                browserSetup.refresh()
        }
        offerIfNeeded()
    }

    function offerIfNeeded() {
        if (started && !deferred && checksComplete && (page === "checking" || (!page && canCheck)))
            openNextPage()
    }

    function focusStep() {
        if (page === "language")
            languageSelector.forceActiveFocus()
        else if (canAdvance)
            nextButton.forceActiveFocus()
        else
            skipButton.forceActiveFocus()
    }

    function showPage(next) {
        page = next
        if (!visible)
            open()
        Qt.callLater(focusStep)
    }

    function openNextPage() {
        if (!checksComplete)
            showPage("checking")
        else if (needBrowser)
            showPage("browser")
        else if (needHelpers)
            showPage("helpers")
        else
            finishWizard()
    }

    function finishWizard() {
        deferred = true
        browserSetup.cancelConfirmation()
        hide()
    }

    function completePage() {
        if (page === "language")
            preferences.languagePending = false
        else if (page === "helpers")
            preferences.helpersDone = true
        else if (page === "browser")
            preferences.browserDone = true
        preferences.sync()
        openNextPage()
    }

    function skipPage() {
        if (!busy && page !== "checking")
            completePage()
    }

    function closeSetup() {
        if (busy)
            return
        preferences.languagePending = false
        preferences.helpersDone = true
        preferences.browserDone = true
        preferences.sync()
        finishWizard()
    }

    function advance() {
        if (!canAdvance)
            return
        if (page !== "language") {
            completePage()
            return
        }
        busy = true
        languageProblem = ""
        engine.request({action: "glass-setting", category: "language", queue: languageSelector.currentValue},
            function(result, error) {
                busy = false
                if (error || result?.saved !== true) {
                    languageProblem = qsTranslate("SettingsWindow", "Could not change the interface language.")
                    return
                }
                completePage()
            })
    }

    function checkHelpers() {
        if (checkingHelpers || requestingHelper)
            return
        checkingHelpers = true
        engine.request({query: "glass-helpers"}, function(result, error) {
            checkingHelpers = false
            if (error || typeof result?.tools?.length !== "number") {
                helperProblem = error || qsTr("Could not check the installed helpers.")
                helpersChecked = true
                return
            }
            helperStatus = result
            helperProblem = ""
            if (Object.keys(failures).length > 0) {
                const updated = Object.assign({}, failures)
                for (const tool of tools) {
                    if (tool?.path)
                        delete updated[tool.name]
                }
                failures = updated
            }
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
    Component.onCompleted: {
        if (automatic && preferences.wizardVersion < 2) {
            preferences.languagePending = true
            preferences.helpersDone = false
            preferences.browserDone = false
            preferences.wizardVersion = 2
            preferences.sync()
        }
        if (canCheck)
            Qt.callLater(checkAtStartup)
    }
    onDismissRequested: closeSetup()

    Timer {
        interval: 1100
        repeat: true
        running: engine.ready && (root.batchRunning
            || (root.page === "helpers" && root.visible && root.visibility !== Window.Minimized))
        onTriggered: root.checkHelpers()
    }

    bodyContent: [
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                Repeater {
                    model: [qsTr("1 · Language"), qsTr("2 · Browser capture"), qsTr("3 · Media helpers")]
                    delegate: Label {
                        required property int index
                        required property string modelData
                        Layout.fillWidth: true
                        text: modelData
                        font.bold: ["language", "browser", "helpers"][index] === root.page
                        color: font.bold ? root.colors.accent : root.colors.muted
                        wrapMode: Text.WordWrap
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(180, width * .31)
                radius: 12
                color: "#171d2a"
                clip: true
                AnimatedImage {
                    anchors.fill: parent
                    source: "qrc:/auralis/setup/" + (root.page === "language" ? "language" : root.page === "browser" ? "browser" : "helpers") + ".gif"
                    fillMode: Image.PreserveAspectFit
                    playing: root.visible && root.visibility !== Window.Minimized && !MaterialTheme.reducedMotion
                    cache: true
                }
            }
            Label {
                Layout.fillWidth: true
                text: root.page === "language" ? qsTr("Make Auralis yours. Choose the language you use every day.")
                    : root.page === "browser" ? qsTr("Enable the extension in each browser, then send a download to Auralis.")
                    : qsTr("Install optional helpers to download videos, join media, and save galleries.")
                font.pixelSize: TypographyScale.pixels(15)
                color: root.colors.text
                wrapMode: Text.WordWrap
            }
        },
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.page === "language"
            spacing: 8

            Label {
                Layout.fillWidth: true
                text: qsTr("Choose your language")
                color: root.colors.ink
                font.pixelSize: TypographyScale.pixels(17)
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }

            GlassComboBox {
                id: languageSelector
                objectName: "startupLanguageSelector"
                Layout.fillWidth: true
                model: root.languages
                textRole: "label"
                valueRole: "value"
                font.family: root.fontFamilyForText(displayText)
                enabled: !root.busy
                Accessible.name: qsTranslate("SettingsWindow", "Interface language")
            }

            Label {
                Layout.fillWidth: true
                text: root.languageProblem || qsTr("You can change the interface language later in Settings.")
                color: root.languageProblem ? root.colors.destructive : root.colors.muted
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
            }
        },
        Label {
            Layout.fillWidth: true
            visible: root.page === "checking"
            text: qsTr("Checking optional components…")
            color: root.colors.muted
            wrapMode: Text.WordWrap
        },
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.page === "helpers"
            spacing: 8

            Label {
                Layout.fillWidth: true
                text: qsTr("Video and gallery helpers")
                color: root.colors.ink
                font.pixelSize: TypographyScale.pixels(17)
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }

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
            }

            Label {
                Layout.fillWidth: true
                visible: Boolean(root.helperProblem) || !root.helpersChecked
                text: root.helperProblem || qsTr("Checking installed helpers…")
                color: root.helperProblem ? root.colors.destructive : root.colors.muted
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
            }

            GlassButton {
                objectName: "installMissingComponents"
                text: root.batchRunning ? qsTr("Installing helpers…") : qsTr("Install missing helpers")
                accent: root.colors.positive
                visible: root.missingHelpers.length > 0
                enabled: engine.ready && !root.batchRunning && !root.installerBusy
                onClicked: root.installMissing()
            }
        },
        BrowserSetupOptions {
            id: browserSetup
            objectName: "startupBrowserSetupOptions"
            Layout.fillWidth: true
            visible: root.page === "browser"
            monitoring: visible && root.visible && root.visibility !== Window.Minimized
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
                objectName: "closeStartupSetup"
                text: qsTr("Close")
                enabled: !root.busy
                onClicked: root.closeSetup()
            }
            GlassButton {
                id: skipButton
                objectName: "skipStartupSetup"
                text: qsTr("Skip")
                enabled: !root.busy
                visible: root.page !== "checking"
                onClicked: root.skipPage()
            }
            GlassButton {
                id: nextButton
                objectName: "continueStartupSetup"
                text: root.hasFollowingPage ? qsTr("Next") : qsTr("Continue to Auralis")
                accent: root.colors.accent
                filled: true
                enabled: root.canAdvance
                visible: root.page !== "checking"
                onClicked: root.advance()
            }
        }
    }
}
