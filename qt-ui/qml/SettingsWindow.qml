pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import QtQuick.Window
import "LanguageCatalog.js" as LanguageCatalog

AuralisWindow {
    id: root

    title: qsTr("Settings — Auralis Download Manager")
    width: 675
    height: 520
    minimumWidth: 650
    minimumHeight: 440
    visible: false
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    palette.windowText: colors.text
    palette.text: colors.text
    palette.buttonText: colors.text
    palette.base: colors.background
    palette.button: colors.background
    palette.highlight: colors.accent

    readonly property int resizeInset: 14
    readonly property bool roundedFrame: frameCornerRadius > 0
    readonly property var colors: MaterialTheme.palette
    readonly property bool classicLayout: MaterialTheme.mdmAppearance
    readonly property color classicPageFace: colors.contentOverride || colors.mdm?.tabPage
        || colors.roleFaces?.content || colors.background
    readonly property color classicTabFace: colors.mdm?.tab || colors.background
    readonly property color classicTabBorder: colors.mdm?.headerLine || colors.divider
    readonly property color classicPageInk: MaterialTheme.controlTextInk(colors.textOverride || colors.text, classicPageFace)
    readonly property color captionInk: (classicLayout && !active ? colors.titleMuted : colors.titleInk) || colors.text
    readonly property var classicFrontTabs: ["General", "Browser Integration", "Downloads",
        "Connection", "File types", "Save to", "Appearance", "Updates", "Remote"]
    readonly property var classicBackTabs: ["Advanced", "Media Helpers", "Accounts", "Torrents", "Display", "Scheduler"]
    readonly property int classicTabsColumns: Math.max(classicFrontTabs.length, classicBackTabs.length)
    readonly property var classicTabs: classicFrontTabs.concat(classicBackTabs).map(id => sections.find(section => section.id === id))
    readonly property var classicPageIcons: ({
        "General": "page-general", "Browser Integration": "page-general", "Downloads": "page-downloads",
        "Connection": "page-connection", "Appearance": "page-regional", "Updates": "page-remote",
        "Advanced": "page-proxy", "Media Helpers": "page-logins", "Accounts": "page-logins",
        "Torrents": "page-file-types", "Display": "page-regional", "Scheduler": "page-archives",
        "Remote": "page-remote"
    })
    readonly property bool wideSweepVisible: wideSweep.visible && wideSweep.available
    readonly property GlassButton selectedNavigationButton: {
        if (!term) {
            for (const row of navigationContent.children) {
                const button = row as GlassButton
                if (button && button.highlighted)
                    return button
            }
        }
        return null
    }
    property string category: "General"
    property var config: null
    property var advancedFields: []
    property var availableLanguages: LanguageCatalog.languages
    property var networkAdapters: []
    property string networkAdapterState: "idle"
    property bool saving: false
    property bool reading: false
    property string problem: ""
    property string notice: ""
    property var remotePair: null
    property bool remotePairing: false
    property string remoteProblem: ""
    property int preferredVisibility: Window.Windowed
    property bool windowLayoutReady: false
    property int pendingInterfaceScalePercent: 100
    property var availableUpdate: null
    property alias donationAction: donatePatreon
    signal updateCheckRequested()
    signal setupRequested()
    signal updateDetailsRequested()
    readonly property string updatePresentation: updatePrefs.presentation
    readonly property bool automaticUpdateChecks: updatePrefs.automaticChecks
    readonly property bool automaticUpdateInstall: updatePrefs.automaticInstall
    readonly property string cookieBrowser: String(advancedFields.find(field => field.key === "video_cookies")?.value ?? "")
    readonly property string term: search.text.trim().toLowerCase()
    readonly property var sections: [
        {id: "General", name: qsTr("General"), detail: qsTr("Startup, notifications, and backups"), terms: qsTr("start backup restore preferences notification window popup"),
            keys: ["language", "start_immediately", "only_add_to_queue", "confirm_delete", "show_progress", "show_complete", "double_click_open",
                "minimize_to_tray", "close_to_tray", "progress_minimize_to_tray"]},
        {id: "Display", name: qsTr("Display & fonts"), detail: qsTr("Interface size, text size, and font previews"), terms: qsTr("interface app UI window scale size zoom DPI fonts typography preview"), keys: []},
        {id: "Save to", name: qsTr("Save to"), detail: qsTr("Default download folders for each category"), terms: qsTr("save destination location path folder remember category directory"), keys: []},
        {id: "File types", name: qsTr("File types"), detail: qsTr("Automatic capture, excluded sites, and file-size rules"), terms: qsTr("extensions types capture exclude sites addresses minimum size"), keys: []},
        {id: "Downloads", name: qsTr("Downloads"), detail: qsTr("File rules, folders, and archive extraction"), terms: qsTr("file folder category archive duplicates extract"), keys: []},
        {id: "Connection", name: qsTr("Connection"), detail: qsTr("Speed limits, proxy, and DNS"), terms: qsTr("speed throttle proxy dns network adapter login authentication"),
            keys: ["max_connections", "speed_limit_on", "speed_limit_kb", "global_limit_on", "global_limit_kb", "net_adapter"]},
        {id: "Browser Integration", name: qsTr("Browser integration"), detail: qsTr("Extension setup and browser download capture"), terms: qsTr("browser chrome edge firefox brave opera chromium vivaldi extension install capture"),
            keys: ["capture_opened", "advanced_integration", "proxy_from_browser"]},
        {id: "Media Helpers", name: qsTr("Video & gallery helpers"), detail: qsTr("Helper installations, video options, and browser sessions"), terms: qsTr("video gallery ffmpeg yt-dlp gallery-dl quality chapters cookies profile"), keys: []},
        {id: "Torrents", name: qsTr("Torrents"), detail: qsTr("Peer discovery and direct download recovery"), terms: qsTr("peer tracker torrent automatic recovery dht lsd share"),
            keys: ["torrent_keep_sharing", "torrent_dht", "torrent_lsd", "torrent_recovery_mode"]},
        {id: "Scheduler", name: qsTr("Scheduler"), detail: qsTr("Queue size, start times, and completion actions"), terms: qsTr("queue scheduler retry weekday schedule start stop"), keys: []},
        {id: "Remote", name: qsTr("Remote control"), detail: qsTr("Pair a phone or another computer on your local network"), terms: qsTr("remote phone mobile computer pair device network control"), keys: []},
        {id: "Accounts", name: qsTr("Accounts"), detail: qsTr("File hosts and supported service accounts"), terms: qsTr("account debrid host sign in token api"), keys: []},
        {id: "Appearance", name: qsTr("Appearance"), detail: qsTr("Materials, translucent backgrounds, and indicators"), terms: qsTr("theme tint glass dark light opacity translucent color material background indicator progress motion"), keys: []},
        {id: "Advanced", name: qsTr("Advanced"), detail: qsTr("Other preferences and compatibility options"), terms: qsTr("preferences sounds notification format compatibility"), keys: []},
        {id: "Updates", name: qsTr("Updates & about"), detail: qsTr("Version, update preferences, and release notes"), terms: qsTr("application about update release changelog version notification"), keys: []}
    ]
    readonly property var recoveryChoices: [
        {label: qsTr("Off — search manually"), value: "off"},
        {label: qsTr("Search and ask me"), value: "ask"},
        {label: qsTr("Continue automatically when unambiguous"), value: "auto"}
    ]
    readonly property var common: ({
        language: {label: qsTr("Interface language"), kind: "select", options: [
            {label: "English", value: "en"},
            {label: "العربية", value: "ar"},
            {label: "Español", value: "es"},
            {label: "简体中文", value: "zh-hans"}
        ]},
        start_immediately: {label: qsTr("Start new downloads automatically"), kind: "boolean"},
        only_add_to_queue: {label: qsTr("Add new requests to the queue"), kind: "boolean"},
        confirm_delete: {label: qsTr("Confirm before deleting"), kind: "boolean"},
        show_progress: {label: qsTr("Open the download progress window automatically"), kind: "boolean"},
        show_complete: {label: qsTr("Show the download completion window"), kind: "boolean"},
        double_click_open: {label: qsTr("Open completed files on double-click"), kind: "boolean"},
        minimize_to_tray: {label: qsTr("Minimize the main window to the tray"), kind: "boolean"},
        close_to_tray: {label: qsTr("Keep Auralis in the tray when closing the main window"), kind: "boolean"},
        progress_minimize_to_tray: {label: qsTr("Minimize transfer windows to the tray"), kind: "boolean"},
        max_connections: {label: qsTr("Maximum connections per file"), kind: "number", minimum: 1, maximum: 128},
        speed_limit_on: {label: qsTr("Enable the speed limiter"), kind: "boolean"},
        speed_limit_kb: {label: qsTr("Speed limit (KB/s)"), kind: "number", maximum: 10000000},
        global_limit_on: {label: qsTr("Enable the total download limit"), kind: "boolean"},
        global_limit_kb: {label: qsTr("Total download limit (KB)"), kind: "number", maximum: 10000000},
        net_adapter: {label: qsTr("Network adapter"), kind: "select",
            description: qsTr("Use the system route or select a specific adapter. Downloads pause if that adapter disconnects.")},
        capture_opened: {label: qsTr("Capture browser-opened downloads"), kind: "boolean"},
        advanced_integration: {label: qsTr("Advanced browser integration"), kind: "boolean"},
        proxy_from_browser: {label: qsTr("Use browser-provided proxy"), kind: "boolean"},
        torrent_keep_sharing: {label: qsTr("Keep sharing completed torrents"), kind: "boolean"},
        torrent_dht: {label: qsTr("Enable distributed hash table (DHT)"), kind: "boolean"},
        torrent_lsd: {label: qsTr("Enable local peer discovery"), kind: "boolean"},
        torrent_recovery_mode: {label: qsTr("Torrent recovery after a direct download fails"), kind: "select", options: recoveryChoices,
            description: qsTr("Search sends filename words to Internet Archive. Automatic continuation uses BitTorrent peers only after one candidate passes the required piece checks. Auralis keeps the original partial for manual recovery.")}
    })
    readonly property var browserChoices: [
        {label: qsTr("None"), value: ""},
        {label: "Chrome", value: "chrome"},
        {label: "Edge", value: "edge"},
        {label: "Firefox", value: "firefox"},
        {label: "Brave", value: "brave"},
        {label: "Chromium", value: "chromium"},
        {label: "Opera", value: "opera"},
        {label: "Vivaldi", value: "vivaldi"},
        {label: "Whale", value: "whale"}
    ].concat(Qt.platform.os === "osx" ? [{label: "Safari", value: "safari"}] : [])
    readonly property var extraDetails: ({
        category_dirs: {section: "Save to", description: qsTr("Choose a category and its default download folder. General is used for files without a matching category. Browse for folders, then save your changes.")},
        change_folder_on_last: {section: "Save to"},
        set_creation_date: {section: "Save to"},
        clipboard_mode: {
            label: qsTr("When a download link is copied"),
            options: [
                {label: qsTr("Paste when Add URL opens"), value: "paste"},
                {label: qsTr("Download automatically"), value: "download"},
                {label: qsTr("Do nothing"), value: "off"}
            ]
        },
        browsers: {description: qsTr("Capture requires the extension and Advanced browser integration. Auralis supports Chrome, Edge, Brave, Chromium, Vivaldi, Opera, Helium, Thorium, Firefox and its supported forks, plus Safari on macOS. Install and enable the extension in each browser you use.")},
        sounds: {description: qsTr("Choose a WAV file for each download or queue event.")},
        video_chapters: {section: "Media Helpers"},
        video_cookies: {section: "Media Helpers", kind: "select", description: qsTr("Choose the browser where you signed in. Auralis uses the local browser session for media requests when the extension did not send cookies.")},
        video_cookies_file: {section: "Media Helpers", description: qsTr("A Netscape cookies.txt file takes precedence over the browser session. Treat the file like a password.")},
        video_cookies_profile: {section: "Media Helpers", description: qsTr("Use the browser’s default profile, enter its profile name, or choose its directory. In Chrome or Edge, open chrome://version or edge://version and look for Profile Path. In Firefox, open about:profiles and use the Root Directory.")}
    })
    readonly property var chosen: sections.find(section => section.id === category) || sections[0]
    readonly property var hiddenEngineFields: ["update_check", "speed_limit_on", "category_dirs", "change_folder_on_last"]
    readonly property bool remoteControlEnabled: Boolean(advancedFields.find(field => field.key === "remote_on")?.value)
    readonly property var visibleFields: matchingFields()
    readonly property bool showingNetworkAdapter: visible && visibleFields.some(field => field.key === "net_adapter")
    readonly property var destinationSections: term ? sections.filter(section => matchesText(section.name + " " + section.detail + " " + section.terms) ||
        visibleFields.some(field => field.section === section.id)) : sections

    Settings {
        id: windowLayout
        category: "SettingsWindowLayout"
    }

    Settings {
        id: updatePrefs
        category: "UpdateNotices"
        property bool automaticChecks: true
        property bool automaticInstall: false
        property string presentation: "toast"
    }

    function setAutomaticUpdateInstall(enabled) {
        if (enabled)
            updatePrefs.automaticChecks = true
        updatePrefs.automaticInstall = enabled
        updatePrefs.sync()
    }

    function load() {
        if (reading || !engine.ready) return
        reading = true
        engine.request({query: "glass-settings"}, function(result, error) {
            if (result) config = result
            if (error) problem = error
            engine.request({query: "glass-original-settings"}, function(data, legacyError) {
                if (data) { advancedFields = data.fields || []; if (data.languages) availableLanguages = data.languages }
                if (legacyError) problem = legacyError
                reading = false
            })
        })
    }

    function matchesText(value) {
        if (!term) return true
        const text = String(value || "").toLowerCase()
        return term.split(/\s+/).every(part => text.includes(part))
    }

    function loadNetworkAdapters() {
        if (!showingNetworkAdapter || !engine.ready || networkAdapterState === "loading")
            return
        networkAdapterState = "loading"
        engine.request({query: "glass-network-adapters"}, function(result, error) {
            if (error || typeof result?.adapters?.length !== "number") {
                networkAdapterState = "failed"
                return
            }
            networkAdapters = Array.from(result.adapters)
            networkAdapterState = "loaded"
        })
    }

    function adapterKey(name) {
        return name.replace(/[A-Z]/g, letter => letter.toLowerCase())
    }

    function networkAdapterChoices(saved) {
        const choices = [{label: qsTr("System default"), value: ""}]
        for (const adapter of networkAdapters) {
            const name = String(adapter?.name ?? "")
            if (!name.trim())
                continue
            const value = adapterKey(name) === adapterKey(saved) ? saved : name
            const label = adapter.address
                ? qsTr("%1 · %2").arg(name).arg(adapter.address)
                : qsTr("%1 (no address)").arg(name)
            choices.push({label, value})
        }
        if (saved && !choices.some(choice => choice.value === saved)) {
            const adapter = networkAdapters.find(item => item?.address === saved)
            const label = adapter ? qsTr("%1 · %2 (saved address)").arg(adapter.name).arg(saved)
                : networkAdapterState === "loaded" ? qsTr("%1 (saved, not listed)").arg(saved)
                : qsTr("%1 (saved)").arg(saved)
            choices.push({label, value: saved})
        }
        return choices
    }

    function networkAdapterNote() {
        switch (networkAdapterState) {
        case "loading": return qsTr("Checking for network adapters…")
        case "failed": return qsTr("Could not list network adapters. System default is still available.")
        case "loaded": return networkAdapters.length ? "" : qsTr("No network adapters were reported.")
        default: return ""
        }
    }

    function localizeBackendField(field, translateOptions = true) {
        const entry = Object.assign({}, field)
        if (entry.label)
            entry.label = qsTranslate("BackendSettings", entry.label)
        if (entry.description)
            entry.description = qsTranslate("BackendSettings", entry.description)
        if (entry.options && translateOptions) {
            entry.options = entry.options.map(option => typeof option === "string"
                ? qsTranslate("BackendSettings", option) : localizeBackendField(option))
        }
        if (entry.columns)
            entry.columns = entry.columns.map(column => localizeBackendField(column, field.key !== "category_dirs"))
        return entry
    }

    function matchingFields() {
        const entries = []
        if (config) {
            for (const section of sections) {
                if (!term && category !== section.id) continue
                for (const key of section.keys) {
                    if (config[key] === undefined || !common[key]) continue
                    const field = common[key]
                    if (!matchesText(key + " " + field.label + " " + (field.description || "")))
                        continue
                    const entry = Object.assign({}, field, {key: key, value: config[key], section: section.id, basic: true})
                    if (key === "language") entry.options = availableLanguages
                    if (key === "max_connections") {
                        const extended = advancedFields.find(field => field.key === "many_connections")?.value === true
                        const limit = extended ? 128 : 32
                        entry.kind = "select"
                        entry.value = Math.min(limit, Math.max(1, Number(entry.value)))
                        entry.options = Array.from({length:limit}, (_,i) => ({label:String(i+1),value:i+1}))
                        entry.description = extended ? qsTr("Choose 1–128 connections per download.")
                            : qsTr("Choose 1–32. Enable Allow more than 32 connections below to raise the limit to 128.")
                    }
                    if (key === "net_adapter") {
                        entry.value = String(entry.value ?? "").trim()
                        entry.options = networkAdapterChoices(entry.value)
                        const note = networkAdapterNote()
                        if (note)
                            entry.description += "\n" + note
                    }
                    entries.push(entry)
                }
            }
        }
        for (const field of advancedFields) {
            if (hiddenEngineFields.includes(field.key)) continue
            const details = extraDetails[field.key]
            const entry = Object.assign(localizeBackendField(field), details || {})
            if (!term && entry.section !== category) continue
            if (field.key === "video_cookies") {
                const stored = String(entry.value || "").trim().toLowerCase()
                entry.value = stored
                entry.options = stored && !browserChoices.some(browser => browser.value === stored)
                    ? browserChoices.concat([{label: stored, value: stored}]) : browserChoices
            }
            const browserNames = field.key === "browsers" ? (entry.captureBrowsers || []).map(row => row.name).join(" ") : ""
            if (matchesText(entry.key + " " + entry.label + " " + field.label + " " + (entry.description || "") + " " + browserNames))
                entries.push(entry)
        }
        return entries
    }

    function save(field, value, options) {
        if (!engine.ready || saving || backups.busy) return
        saving = true
        problem = ""
        notice = ""
        const payload = Object.assign({key: field.key, value: value}, options || {})
        const command = field.basic ? {action: "glass-setting", category: field.key, queue: String(value)}
            : {action: "glass-original-setting", queue: JSON.stringify(payload)}
        engine.request(command, function(reply, error) {
            saving = false
            if (error || !reply || reply.ok === false || reply.error) {
                if (field.key === "language") {
                    problem = qsTr("Could not change the interface language.")
                    load()
                } else {
                    problem = error || reply?.error || qsTr("Could not save this setting.")
                    if (field.key === "browsers") load()
                }
                return
            }
            if (field.key !== "language")
                notice = qsTr("Settings saved")
            load()
        })
    }

    function pairRemoteDevice() {
        if (!remoteControlEnabled || remotePairing)
            return
        remotePairing = true
        remoteProblem = ""
        engine.request({pair: true}, function(reply, error) {
            remotePairing = false
            if (error || reply?.error) {
                remoteProblem = error || reply.error
                remotePair = null
                return
            }
            remotePair = reply
        })
    }

    function present() {
        if (!visible || visibility === Window.Minimized) {
            if (preferredVisibility === Window.Maximized)
                showMaximized()
            else if (preferredVisibility === Window.FullScreen)
                showFullScreen()
            else
                show()
        }
        raise()
        requestActivate()
    }

    function showCategory(section) {
        if (!sections.some(item => item.id === section)) return
        search.clear()
        category = section
        scrollViewport.contentY = 0
        present()
    }

    function queueWindowSizeSave() {
        if (windowLayoutReady && visibility === Window.Windowed)
            windowSizeSave.restart()
    }

    function flushWindowSize() {
        windowSizeSave.stop()
        if (windowLayoutReady && visibility === Window.Windowed)
            saveWindowSize()
    }

    function saveWindowSize() {
        if (Number(windowLayout.value("initialWidth")) === width
            && Number(windowLayout.value("initialHeight")) === height)
            return
        windowLayout.setValue("initialWidth", width)
        windowLayout.setValue("initialHeight", height)
        windowLayout.sync()
    }

    function toggleMaximize() {
        flushWindowSize()
        if (visibility === Window.Maximized) showNormal()
        else showMaximized()
    }

    Component.onCompleted: {
        width = Math.max(minimumWidth, Number(windowLayout.value("initialWidth", width)) || width)
        height = Math.max(minimumHeight, Number(windowLayout.value("initialHeight", height)) || height)
        windowLayoutReady = true
    }
    onWidthChanged: queueWindowSizeSave()
    onHeightChanged: queueWindowSizeSave()
    onClosing: flushWindowSize()
    onVisibleChanged: if (visible) load()
    onVisibilityChanged: {
        if (visibility !== Window.Windowed && windowLayoutReady)
            windowSizeSave.stop()
        if (visibility === Window.Windowed || visibility === Window.Maximized || visibility === Window.FullScreen)
            preferredVisibility = visibility
    }

    Timer {
        id: windowSizeSave
        interval: 150
        onTriggered: if (root.visibility === Window.Windowed) root.saveWindowSize()
    }
    onShowingNetworkAdapterChanged: if (showingNetworkAdapter) Qt.callLater(loadNetworkAdapters)
    onCategoryChanged: if (category === "Scheduler" && engine.ready && !scheduler.queues.length) scheduler.load()
    onTermChanged: if (scrollViewport) scrollViewport.contentY = 0

    Timer {
        id: interfaceScalePreview
        interval: 16
        repeat: false
        onTriggered: root.fontSettings.previewInterfaceScalePercent(root.pendingInterfaceScalePercent)
    }

    Connections {
        target: engine
        function onQuittingChanged() {
            if (engine.quitting)
                root.flushWindowSize()
        }
        function onReadyChanged() {
            if (root.visible && engine.ready) {
                root.load()
                if (root.showingNetworkAdapter)
                    Qt.callLater(root.loadNetworkAdapters)
            }
        }
    }

    background: WindowBackdrop {
        id: settingsBackdrop
        hostWindow: root
        target: "details"

        WideSweep {
            id: wideSweep
            objectName: "settingsWideSweep"
            anchors.fill: parent
            visible: !root.classicLayout && MaterialTheme.wideSweepEnabled && root.visible && root.visibility !== Window.Minimized
            sidebar: navigationSidebar
            pane: settingsPane
            viewport: navigation
            geometryHost: settingsLayout
            backdropAvailable: settingsBackdrop.backdropAvailable
            selectedRow: root.selectedNavigationButton
            selectedColor: root.selectedNavigationButton?.ribbonFace || root.colors.accent
        }
    }

    component PaneCopy: Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: root.colors.muted
    }

    component SettingsScrollBar: Basic.ScrollBar {
        id: grip
        readonly property color trackColor: MaterialTheme.mix(root.colors.background, root.colors.divider, .40, 1)

        implicitWidth: 14
        width: implicitWidth
        padding: 2
        minimumSize: Math.min(1, 28 / Math.max(28, height - topPadding - bottomPadding))
        interactive: true
        hoverEnabled: true
        contentItem: Rectangle {
            implicitWidth: 10
            radius: width / 2
            color: MaterialTheme.controlIconInk(grip.pressed || grip.hovered ? root.colors.accent : root.colors.secondary,
                grip.trackColor)
        }
        background: Rectangle {
            radius: width / 2
            color: grip.trackColor
            border.color: root.colors.divider
        }
    }

    component SettingsViewport: Flickable {
        id: viewport
        required property string scrollbarName
        required property string scrollbarLabel
        readonly property bool overflowing: contentHeight > height + 1
        readonly property real columnWidth: Math.max(0, width - 20)

        clip: true
        contentWidth: width
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: SettingsScrollBar {
            objectName: viewport.scrollbarName
            Accessible.name: viewport.scrollbarLabel
            policy: viewport.overflowing ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            visible: viewport.overflowing
            z: 1
        }
    }

    component Card: Frame {
        Layout.fillWidth: true
        padding: root.classicLayout ? 6 : 14
        background: Item {
            GlassSurface {
                anchors.fill: parent
                visible: !root.classicLayout
                role: "content"
                roundedPanel: true
                backdropAvailable: settingsBackdrop.backdropAvailable
            }
            Rectangle {
                anchors.fill: parent
                visible: root.classicLayout
                color: root.classicPageFace
                border.color: root.classicTabBorder
            }
        }
    }

    Action {
        id: donatePatreon
        text: qsTranslate("SettingsUpdates", "Donate on Patreon")
        onTriggered: Qt.openUrlExternally("https://www.patreon.com/c/Alsamii")
    }

    header: ColumnLayout {
        id: headerStack
        spacing: 0
        ToolBar {
            Layout.fillWidth: true
            padding: 0
            leftInset: root.classicLayout || root.roundedFrame ? 0 : 8
            rightInset: leftInset
            topInset: root.classicLayout || root.roundedFrame ? 0 : 5
            bottomInset: root.classicLayout || root.roundedFrame ? 0 : 2
            background: GlassSurface {
                role: "title"
                roundedPanel: !root.classicLayout && !root.roundedFrame
                radius: roundedPanel ? Math.max(12, profile.radius) : 0
                backdropAvailable: settingsBackdrop.backdropAvailable
            }

            contentItem: RowLayout {
                id: settingsTitleRow
                spacing: 7
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.classicLayout ? 27 : 45
                    BrandMark {
                        id: settingsBrand
                        anchors.left: parent.left
                        anchors.leftMargin: Math.max(root.classicLayout ? 7 : 15, root.frameSafeInset)
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.classicLayout ? 15 : implicitWidth
                        height: width
                    }
                    Label {
                        anchors.left: settingsBrand.right
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.title
                        elide: Text.ElideRight
                        font.weight: root.classicLayout ? Font.Normal : Font.DemiBold
                        font.pixelSize: root.classicLayout ? TypographyScale.pixels(12) : root.font.pixelSize
                        color: root.captionInk
                    }
                    CaptionMoveArea {
                        objectName: "settingsTitleDragArea"
                        hostWindow: root
                        anchors.fill: parent
                        onDoubleClickRequested: root.toggleMaximize()
                    }
                }
                GlassButton {
                    id: settingsDonateButton
                    objectName: "settingsHeaderDonatePatreon"
                    visible: true
                    action: donatePatreon
                    Layout.preferredHeight: root.classicLayout ? 23 : 30
                    Layout.preferredWidth: root.classicLayout ? 30 : implicitWidth
                    topPadding: 0
                    bottomPadding: 0
                    contentItem: RowLayout {
                        spacing: 6
                        DashboardIcon {
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 18
                            symbol: "support"
                            solid: true
                            ink: settingsDonateButton.buttonInk
                        }
                        Label {
                            visible: !root.classicLayout
                            text: settingsDonateButton.text
                            color: settingsDonateButton.buttonInk
                            font: settingsDonateButton.font
                        }
                    }
                    leftPadding: root.classicLayout ? 3 : 9
                    rightPadding: root.classicLayout ? 3 : 9
                    accent: root.colors.secondary
                    Accessible.role: Accessible.Link
                }
                CaptionControls {
                    maximized: root.visibility === Window.Maximized
                    closeLabel: qsTr("Close settings")
                    onMinimizeRequested: root.showMinimized()
                    onMaximizeRequested: root.toggleMaximize()
                    onCloseRequested: root.close()
                }
                Item { Layout.preferredWidth: Math.max(root.resizeInset, root.frameSafeInset - settingsTitleRow.spacing) }
            }
        }
        ToolBar {
            parent: root.classicLayout ? classicFooter : headerStack
            objectName: "settingsCommands"
            Layout.fillWidth: true
            leftPadding: root.classicLayout ? 8 : Math.max(root.resizeInset + 2, root.frameSafeInset)
            rightPadding: root.classicLayout ? 8 : Math.max(root.resizeInset + 2, root.frameSafeInset)
            topPadding: root.classicLayout ? 2 : 4
            bottomPadding: 5
            leftInset: root.classicLayout || root.roundedFrame ? 0 : 8
            rightInset: leftInset
            topInset: root.roundedFrame ? 0 : 2
            bottomInset: root.roundedFrame ? 0 : 1
            background: GlassSurface {
                role: root.classicLayout ? "footer" : "toolbar"
                roundedPanel: !root.classicLayout && !root.roundedFrame
                radius: roundedPanel ? Math.max(12, profile.radius) : 0
                backdropAvailable: settingsBackdrop.backdropAvailable
            }
            contentItem: RowLayout {
                spacing: 8
                Label {
                    Layout.fillWidth: true
                    text: root.saving ? qsTr("Saving…") : root.reading ? qsTr("Loading settings…") : root.notice ||
                        (engine.ready ? qsTr("Auralis %1").arg(engine.version) : engine.status)
                    elide: Text.ElideRight
                    font.pixelSize: root.classicLayout ? TypographyScale.pixels(11) : root.font.pixelSize
                    color: root.classicLayout ? root.colors.footerMuted || root.colors.muted : root.colors.muted
                }
                GlassButton {
                    objectName: "openSetupWizard"
                    Layout.preferredHeight: root.classicLayout ? 23 : implicitHeight
                    font.pixelSize: TypographyScale.pixels(root.classicLayout ? 11 : 13)
                    text: qsTranslate("StartupSetup", "Set up Auralis")
                    enabled: engine.ready
                    onClicked: root.setupRequested()
                }
                GlassButton {
                    objectName: "settingsDone"
                    Layout.preferredWidth: root.classicLayout ? 73 : implicitWidth
                    Layout.preferredHeight: root.classicLayout ? 23 : implicitHeight
                    font.pixelSize: TypographyScale.pixels(root.classicLayout ? 11 : 13)
                    text: root.classicLayout ? qsTr("OK") : qsTr("Done")
                    accent: root.colors.positive
                    highlighted: true
                    onClicked: root.close()
                }
                GlassButton {
                    visible: root.classicLayout
                    Layout.preferredWidth: 73
                    Layout.preferredHeight: 23
                    font.pixelSize: TypographyScale.pixels(11)
                    text: qsTr("Help")
                    onClicked: Qt.openUrlExternally("https://github.com/4ls4mi/Auralis-Download-Manager#guides-and-feedback")
                }
            }
        }
    }

    footer: ColumnLayout {
        id: classicFooter
        visible: root.classicLayout
        spacing: 0
    }

    GridLayout {
        id: settingsLayout
        anchors.fill: parent
        anchors.margins: root.classicLayout ? 7 : 12
        anchors.rightMargin: root.classicLayout ? 7 : root.resizeInset
        anchors.bottomMargin: root.classicLayout ? 4 : Math.max(root.resizeInset, root.frameSafeInset)
        columns: 2
        columnSpacing: 12
        rowSpacing: 0

        GridLayout {
            objectName: "classicSettingsTabs"
            Accessible.role: Accessible.PageTabList
            visible: root.classicLayout
            Layout.row: 0
            Layout.column: 0
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.leftMargin: 2
            Layout.rightMargin: 2
            columns: root.classicTabsColumns
            rowSpacing: 1
            columnSpacing: 1
            uniformCellWidths: true

            Repeater {
                id: classicTabsRepeater
                model: root.classicLayout ? root.classicTabs : []
                delegate: Basic.TabButton {
                    id: classicTab
                    required property var modelData
                    required property int index
                    readonly property bool selected: root.category === modelData.id && !root.term
                    readonly property bool firstRow: (index < root.classicFrontTabs.length)
                        !== root.classicFrontTabs.includes(root.category)
                    readonly property color face: selected ? root.classicPageFace
                        : hovered ? root.colors.mdm?.tabHot || root.classicTabFace : root.classicTabFace
                    readonly property color ink: MaterialTheme.controlTextInk(root.colors.textOverride || root.colors.text, face)

                    Layout.row: firstRow ? 0 : 1
                    Layout.column: index % root.classicTabsColumns
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredHeight: Math.max(19, implicitContentHeight + 4)
                    padding: 2
                    leftPadding: 4
                    rightPadding: 4
                    hoverEnabled: true
                    checkable: false
                    text: modelData.name
                    font.pixelSize: TypographyScale.pixels(11)
                    focusPolicy: selected || root.term ? Qt.StrongFocus : Qt.ClickFocus
                    Accessible.role: Accessible.PageTab
                    Accessible.selected: selected
                    Accessible.description: modelData.detail
                    ToolTip.visible: hovered && tabTitle.truncated
                    ToolTip.text: text
                    onClicked: root.showCategory(modelData.id)

                    Keys.onPressed: event => {
                        if (root.term)
                            return
                        const step = root.LayoutMirroring.enabled ? -1 : 1
                        const last = root.classicTabs.length - 1
                        let next
                        switch (event.key) {
                        case Qt.Key_Home: next = 0; break
                        case Qt.Key_End: next = last; break
                        case Qt.Key_Left: next = index - step; break
                        case Qt.Key_Right: next = index + step; break
                        default: return
                        }
                        const target = classicTabsRepeater.itemAt(Math.max(0, Math.min(last, next)))
                        if (target) {
                            root.showCategory(target.modelData.id)
                            target.forceActiveFocus(Qt.TabFocusReason)
                            event.accepted = true
                        }
                    }

                    contentItem: Label {
                        id: tabTitle
                        text: classicTab.text
                        font: classicTab.font
                        color: classicTab.ink
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    background: Rectangle {
                        color: classicTab.face
                        border.color: classicTab.visualFocus ? root.colors.accent : root.classicTabBorder
                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 1
                            anchors.bottomMargin: 0
                            height: 1
                            visible: classicTab.selected
                            color: classicTab.face
                        }
                    }
                }
            }
        }

        Frame {
            id: navigationSidebar
            visible: !root.classicLayout
            Layout.row: 0
            Layout.column: 0
            Layout.fillHeight: true
            Layout.preferredWidth: 188
            padding: 9
            background: GlassSurface {
                visible: !root.wideSweepVisible
                role: "sidebar"
                roundedPanel: true
                backdropAvailable: settingsBackdrop.backdropAvailable
            }

            SettingsViewport {
                id: navigation
                objectName: "settingsNavigationViewport"
                anchors.fill: parent
                contentHeight: navigationContent.implicitHeight
                scrollbarName: "settingsNavigationScrollbar"
                scrollbarLabel: qsTr("Scroll settings categories")

                ColumnLayout {
                    id: navigationContent
                    width: navigation.columnWidth
                    spacing: 4
                    Repeater {
                        model: root.destinationSections
                        delegate: GlassButton {
                            id: navigationButton
                            required property var modelData
                            required property int index
                            readonly property bool flatSelection: root.wideSweepVisible && highlighted
                            readonly property color ribbonFace: customTint || engagedFace
                            readonly property color navigationInk: flatSelection
                                ? MaterialTheme.controlTextInk(root.colors.sidebarInk || root.colors.text, ribbonFace)
                                : buttonInk

                            Layout.fillWidth: true
                            text: modelData.name
                            accent: MaterialTheme.navigationColor(index, root.colors.light)
                            highlighted: root.category === modelData.id && !root.term
                            palette.buttonText: navigationInk
                            palette.brightText: navigationInk
                            palette.highlightedText: navigationInk
                            onClicked: root.showCategory(modelData.id)
                            Accessible.description: modelData.detail

                            Binding {
                                target: navigationButton.background
                                property: "visible"
                                value: !navigationButton.flatSelection
                            }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                visible: navigationButton.flatSelection && navigationButton.visualFocus
                                radius: Math.min(10, root.colors.radius)
                                color: "transparent"
                                border.color: navigationButton.navigationInk
                                border.width: 2
                            }
                        }
                    }
                }
            }
        }

        Frame {
            id: settingsPane
            Layout.minimumWidth: 0
            Layout.row: root.classicLayout ? 1 : 0
            Layout.column: root.classicLayout ? 0 : 1
            Layout.columnSpan: root.classicLayout ? 2 : 1
            Layout.fillWidth: true
            Layout.fillHeight: true
            padding: root.classicLayout ? 7 : 13
            background: Item {
                GlassSurface {
                    anchors.fill: parent
                    visible: !root.classicLayout && !root.wideSweepVisible
                    role: "content"
                    roundedPanel: true
                    backdropAvailable: settingsBackdrop.backdropAvailable
                }
                Rectangle {
                    anchors.fill: parent
                    visible: root.classicLayout
                    color: root.classicPageFace
                    border.color: root.classicTabBorder
                }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: root.classicLayout ? 5 : 10

                TextField {
                    id: search
                    objectName: "settingsSearch"
                    Layout.fillWidth: true
                    placeholderText: qsTr("Search settings…")
                    Accessible.name: placeholderText
                    selectByMouse: true
                    font.pixelSize: root.classicLayout ? TypographyScale.pixels(11) : root.font.pixelSize
                    color: root.colors.text
                    placeholderTextColor: root.colors.muted
                    background: GlassSurface { role: "field"; backdropAvailable: settingsBackdrop.backdropAvailable }
                }

                SettingsViewport {
                    id: scrollViewport
                    objectName: "settingsPageViewport"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: settingsContent.implicitHeight
                    scrollbarName: "settingsPageScrollbar"
                    scrollbarLabel: qsTr("Scroll settings page")

                    ColumnLayout {
                        id: settingsContent
                        width: scrollViewport.columnWidth
                        spacing: root.classicLayout ? 6 : 12

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Loader {
                                active: root.classicLayout && !root.term
                                visible: active
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                sourceComponent: ClassicToolbarIcon {
                                    iconName: root.classicPageIcons[root.category] || "page-general"
                                    ink: root.classicPageInk
                                }
                            }
                            Label {
                                Layout.fillWidth: true
                                text: root.term ? qsTr("Search results") : root.chosen.name
                                color: root.classicLayout ? root.classicPageInk : root.colors.text
                                font.pixelSize: TypographyScale.pixels(root.classicLayout ? 13 : 26)
                                font.weight: Font.Bold
                                horizontalAlignment: root.classicLayout ? Text.AlignRight : Text.AlignLeft
                                Accessible.description: root.term ? "" : root.chosen.detail
                            }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            visible: root.classicLayout
                            color: root.classicTabBorder
                        }

                        PaneCopy { visible: !root.term && !root.classicLayout; text: root.chosen.detail }
                        PaneCopy {
                            visible: Boolean(root.term) && !root.visibleFields.length
                            text: root.destinationSections.length
                                ? root.classicLayout ? qsTr("Open a matching settings tab.") : qsTr("Open a matching section from the sidebar.")
                                : qsTr("No matching settings.")
                        }

                        Card {
                            visible: root.visibleFields.length > 0
                            ColumnLayout {
                                width: parent.width
                                spacing: root.classicLayout ? 4 : 12
                                Repeater {
                                    model: root.visibleFields
                                    delegate: SettingsField {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: root.classicLayout ? 3 : 8
                                        field: modelData
                                        cookieBrowser: root.cookieBrowser
                                        busy: root.saving || !engine.ready || backups.busy
                                        onCommit: (value, options) => root.save(field, value, options)
                                    }
                                }
                            }
                        }

                        SettingsBackup {
                            id: backups
                            Layout.fillWidth: true
                            visible: !root.term && root.category === "General"
                            backdrop: settingsBackdrop
                            onSettingsRestored: root.load()
                        }

                        SettingsAppearance {
                            Layout.fillWidth: true
                            visible: !root.term && root.category === "Appearance"
                            backdrop: settingsBackdrop
                        }

                        Loader {
                            Layout.fillWidth: true
                            visible: !root.term && root.category === "Display" && root.fontSettings !== null
                            active: visible
                            sourceComponent: ColumnLayout {
                                spacing: 12

                                Card {
                                    ColumnLayout {
                                        width: parent.width
                                        spacing: 8

                                        Label {
                                            Layout.fillWidth: true
                                            text: qsTr("Interface size")
                                            color: root.colors.text
                                            font.weight: Font.DemiBold
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true

                                            GlassSlider {
                                                id: interfaceSize
                                                objectName: "settingsInterfaceSize"
                                                property bool saveFailed: false
                                                Layout.fillWidth: true
                                                from: root.fontSettings?.interfaceScaleMinimum ?? 85
                                                to: root.fontSettings?.interfaceScaleMaximum ?? 150
                                                stepSize: 1
                                                snapMode: Slider.SnapAlways
                                                live: true
                                                value: root.fontSettings?.interfaceScalePercent ?? 100
                                                palette.highlight: root.colors.accent
                                                Accessible.name: qsTr("Interface size")

                                                function saveSelection() {
                                                    interfaceScalePreview.stop()
                                                    const percent = Math.round(value)
                                                    root.pendingInterfaceScalePercent = percent
                                                    root.fontSettings.previewInterfaceScalePercent(percent)
                                                    saveFailed = !root.fontSettings.setInterfaceScalePercent(percent)
                                                    if (saveFailed)
                                                        value = Qt.binding(() => root.fontSettings.interfaceScalePercent)
                                                }
                                                onMoved: {
                                                    root.pendingInterfaceScalePercent = Math.round(value)
                                                    if (pressed && !interfaceScalePreview.running)
                                                        interfaceScalePreview.start()
                                                    if (!pressed) saveSelection()
                                                }
                                                onPressedChanged: if (!pressed) saveSelection()
                                            }

                                            NumeralLabel {
                                                valueText: qsTr("%1%").arg(Math.round(interfaceSize.valueAt(interfaceSize.position)))
                                                color: root.colors.text
                                            }
                                        }

                                        PaneCopy { text: qsTr("Resizes controls, text, and spacing throughout Auralis as you move the slider.") }

                                        PaneCopy {
                                            visible: interfaceSize.saveFailed
                                            text: qsTr("Could not save the interface size.")
                                            color: root.colors.destructive
                                        }
                                    }
                                }

                                SettingsTypography {
                                    Layout.fillWidth: true
                                    fontSettings: root.fontSettings
                                }
                            }
                        }

                        SettingsScheduler {
                            id: scheduler
                            Layout.fillWidth: true
                            visible: !root.term && root.category === "Scheduler"
                        }

                        SettingsSaveTo {
                            Layout.fillWidth: true
                            visible: !root.term && root.category === "Save to"
                            onSaved: root.load()
                        }
                        SettingsAccounts {
                            Layout.fillWidth: true
                            visible: !root.term && root.category === "Accounts"
                        }

                        BrowserSetupOptions {
                            objectName: "settingsBrowserSetupOptions"
                            Layout.fillWidth: true
                            visible: !root.term && root.category === "Browser Integration"
                            monitoring: Qt.platform.os === "windows" && visible
                                && root.visible && root.visibility !== Window.Minimized
                            showManualTools: true
                        }

                        SettingsTools {
                            Layout.fillWidth: true
                            visible: !root.term && root.category === "Media Helpers"
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: !root.term && root.category === "Remote"
                            spacing: 10

                            PaneCopy {
                                text: qsTr("Turn on remote control, then create a one-time pairing code. On your phone or another computer on the same local network, open one of the addresses and enter that code. Connections use HTTPS.")
                            }

                            GlassButton {
                                objectName: "pairRemoteDevice"
                                text: root.remotePairing ? qsTr("Creating pairing code…") : qsTr("Pair a device")
                                accent: root.colors.accent
                                filled: true
                                enabled: root.remoteControlEnabled && !root.remotePairing && engine.ready
                                onClicked: root.pairRemoteDevice()
                            }

                            Card {
                                visible: Boolean(root.remotePair)
                                ColumnLayout {
                                    width: parent.width
                                    spacing: 8
                                    Label {
                                        text: qsTr("Enter this code on the device")
                                        color: root.colors.text
                                        font.weight: Font.DemiBold
                                    }
                                    Label {
                                        objectName: "remotePairingCode"
                                        text: root.remotePair?.code || ""
                                        color: root.colors.accent
                                        font.pixelSize: TypographyScale.pixels(26)
                                        font.weight: Font.Bold
                                        font.family: "monospace"
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        text: qsTr("Pairing code expires after %1 minutes and can be used once.").arg(root.remotePair?.minutes || 10)
                                        color: root.colors.muted
                                        wrapMode: Text.WordWrap
                                    }
                                    Repeater {
                                        model: root.remotePair?.urls || []
                                        delegate: Label {
                                            required property string modelData
                                            Layout.fillWidth: true
                                            text: modelData
                                            color: root.colors.text
                                            wrapMode: Text.WrapAnywhere
                                        }
                                    }
                                }
                            }

                            PaneCopy {
                                visible: !root.remoteControlEnabled
                                text: qsTr("Remote control is off. Enable it above to let devices join after you give them a pairing code.")
                            }

                            PaneCopy {
                                visible: Boolean(root.remoteProblem)
                                text: root.remoteProblem
                                textFormat: Text.PlainText
                                color: root.colors.destructive
                            }
                        }

                        SettingsUpdates {
                            Layout.fillWidth: true
                            donationAction: donatePatreon
                            visible: !root.term && root.category === "Updates"
                            backdropAvailable: settingsBackdrop.backdropAvailable
                            updatePresentation: root.updatePresentation
                            automaticChecks: root.automaticUpdateChecks
                            automaticInstall: root.automaticUpdateInstall
                            onUpdatePresentationRequested: value => updatePrefs.presentation = value
                            onAutomaticChecksRequested: value => {
                                if (!value) updatePrefs.automaticInstall = false
                                updatePrefs.automaticChecks = value
                            }
                            onAutomaticInstallRequested: value => root.setAutomaticUpdateInstall(value)
                            release: root.availableUpdate
                            onUpdateCheckRequested: root.updateCheckRequested()
                            onUpdateDetailsRequested: root.updateDetailsRequested()
                        }

                        PaneCopy {
                            visible: Boolean(root.problem)
                            text: root.problem
                            color: root.colors.destructive
                        }
                    }
                }
            }
        }
    }

    WindowResizeHandles {
        hostWindow: root
        coalesceGeometry: true
        windowMouseEvents: false
        borderSize: 11
        cornerSize: 19
        showGrip: true
        gripColor: root.colors.muted
        onResizingChanged: if (!resizing) root.flushWindowSize()
    }
}
