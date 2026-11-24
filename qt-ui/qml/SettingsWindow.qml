pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import QtQuick.Window

AuralisWindow {
    id: root

    title: qsTr("Settings — Auralis Download Manager")
    width: windowLayout.initialWidth
    height: windowLayout.initialHeight
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
    readonly property var colors: MaterialTheme.palette
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
    property var networkAdapters: []
    property string networkAdapterState: "idle"
    property bool saving: false
    property bool reading: false
    property string problem: ""
    property string notice: ""
    property var availableUpdate: null
    signal updateCheckRequested()
    signal setupRequested()
    signal updateDetailsRequested()
    readonly property string updatePresentation: updatePrefs.presentation
    readonly property bool automaticUpdateChecks: updatePrefs.automaticChecks
    readonly property string cookieBrowser: String(advancedFields.find(field => field.key === "video_cookies")?.value ?? "")
    readonly property string term: search.text.trim().toLowerCase()
    readonly property var sections: [
        {id: "General", name: qsTr("General"), detail: qsTr("Startup, notifications, and backups"), terms: qsTr("start backup restore preferences notification window popup"),
            keys: ["language", "start_immediately", "only_add_to_queue", "confirm_delete", "show_progress", "show_complete", "double_click_open",
                "minimize_to_tray", "close_to_tray", "progress_minimize_to_tray"]},
        {id: "Display", name: qsTr("Display & fonts"), detail: qsTr("Interface size, text size, and font previews"), terms: qsTr("interface app UI window scale size zoom DPI fonts typography preview"), keys: []},
        {id: "Downloads", name: qsTr("Downloads"), detail: qsTr("File rules, folders, and archive extraction"), terms: qsTr("file folder category archive duplicates extract"), keys: []},
        {id: "Connection", name: qsTr("Connection"), detail: qsTr("Speed limits, proxy, and DNS"), terms: qsTr("speed throttle proxy dns network adapter login authentication"),
            keys: ["max_connections", "speed_limit_on", "speed_limit_kb", "global_limit_on", "global_limit_kb", "net_adapter"]},
        {id: "Browser Integration", name: qsTr("Browser integration"), detail: qsTr("Extension setup and browser download capture"), terms: qsTr("browser chrome edge firefox brave opera chromium vivaldi extension install capture"),
            keys: ["capture_opened", "advanced_integration", "proxy_from_browser"]},
        {id: "Media Helpers", name: qsTr("Video & gallery helpers"), detail: qsTr("Helper installations, video options, and browser sessions"), terms: qsTr("video gallery ffmpeg yt-dlp gallery-dl quality chapters cookies profile"), keys: []},
        {id: "Torrents", name: qsTr("Torrents"), detail: qsTr("Peer discovery and direct download recovery"), terms: qsTr("peer tracker torrent automatic recovery dht lsd share"),
            keys: ["torrent_keep_sharing", "torrent_dht", "torrent_lsd", "torrent_recovery_mode"]},
        {id: "Scheduler", name: qsTr("Scheduler"), detail: qsTr("Queue size, start times, and completion actions"), terms: qsTr("queue scheduler retry weekday schedule start stop"), keys: []},
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
        clipboard_mode: {
            label: qsTr("When a download link is copied"),
            options: [
                {label: qsTr("Paste when Add URL opens"), value: "paste"},
                {label: qsTr("Download automatically"), value: "download"},
                {label: qsTr("Do nothing"), value: "off"}
            ]
        },
        browsers: {description: qsTr("Capture requires the extension and Advanced browser integration. Chromium, Vivaldi, and Helium use the Google Chrome setting when they identify as Chrome. Opera GX uses the Opera setting.")},
        sounds: {description: qsTr("Choose a WAV file for each download or queue event.")},
        video_chapters: {section: "Media Helpers"},
        video_cookies: {section: "Media Helpers", kind: "select", description: qsTr("Choose the browser where you signed in. Auralis uses the local browser session for media requests when the extension did not send cookies.")},
        video_cookies_file: {section: "Media Helpers", description: qsTr("A Netscape cookies.txt file takes precedence over the browser session. Treat the file like a password.")},
        video_cookies_profile: {section: "Media Helpers", description: qsTr("Use the browser’s default profile, enter its profile name, or choose its directory. In Chrome or Edge, open chrome://version or edge://version and look for Profile Path. In Firefox, open about:profiles and use the Root Directory.")}
    })
    readonly property var chosen: sections.find(section => section.id === category) || sections[0]
    readonly property var hiddenEngineFields: ["update_check", "speed_limit_on"]
    readonly property var visibleFields: matchingFields()
    readonly property bool showingNetworkAdapter: visible && visibleFields.some(field => field.key === "net_adapter")
    readonly property var destinationSections: term ? sections.filter(section => matchesText(section.name + " " + section.detail + " " + section.terms) ||
        visibleFields.some(field => field.section === section.id)) : sections

    Settings {
        id: windowLayout
        category: "SettingsWindowLayout"
        property int initialWidth: 675
        property int initialHeight: 520
    }

    Settings {
        id: updatePrefs
        category: "UpdateNotices"
        property bool automaticChecks: true
        property string presentation: "toast"
    }

    function load() {
        if (reading || !engine.ready) return
        reading = true
        engine.request({query: "glass-settings"}, function(result, error) {
            if (result) config = result
            if (error) problem = error
            engine.request({query: "glass-original-settings"}, function(data, legacyError) {
                if (data) advancedFields = data.fields || []
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
            if (error || !reply || reply.ok === false) {
                if (field.key === "language") {
                    problem = qsTr("Could not change the interface language.")
                    load()
                } else {
                    problem = error || qsTr("Could not save this setting.")
                    if (field.key === "browsers") load()
                }
                return
            }
            if (field.key !== "language")
                notice = qsTr("Settings saved")
            load()
        })
    }

    function showCategory(section) {
        if (!sections.some(item => item.id === section)) return
        search.clear()
        category = section
        scrollViewport.contentY = 0
        show()
        raise()
        requestActivate()
    }

    function toggleMaximize() {
        if (visibility === Window.Maximized) showNormal()
        else showMaximized()
    }

    onVisibleChanged: if (visible) load()
    onShowingNetworkAdapterChanged: if (showingNetworkAdapter) Qt.callLater(loadNetworkAdapters)
    onCategoryChanged: if (category === "Scheduler" && engine.ready && !scheduler.queues.length) scheduler.load()
    onTermChanged: if (scrollViewport) scrollViewport.contentY = 0

    Connections {
        target: engine
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
            anchors.fill: parent
            visible: MaterialTheme.wideSweepEnabled && root.visible && root.visibility !== Window.Minimized
            sidebar: navigationSidebar
            pane: settingsPane
            viewport: navigation
            geometryHost: settingsLayout
            backdropAvailable: settingsBackdrop.backdropAvailable
            selectedRow: root.selectedNavigationButton
            selectedColor: root.selectedNavigationButton?.engagedFace || root.colors.accent
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
        padding: 14
        background: GlassSurface { role: "content"; roundedPanel: true; backdropAvailable: settingsBackdrop.backdropAvailable }
    }

    header: ColumnLayout {
        spacing: 0
        ToolBar {
            Layout.fillWidth: true
            padding: 0
            leftInset: 8
            rightInset: 8
            topInset: 5
            bottomInset: 2
            background: GlassSurface { role: "title"; roundedPanel: true; backdropAvailable: settingsBackdrop.backdropAvailable }

            contentItem: RowLayout {
                id: settingsTitleRow
                spacing: 7
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 45
                    BrandMark {
                        id: settingsBrand
                        anchors.left: parent.left
                        anchors.leftMargin: Math.max(15, root.frameSafeInset)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        anchors.left: settingsBrand.right
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.title
                        elide: Text.ElideRight
                        font.weight: Font.DemiBold
                        color: root.colors.text
                    }
                    CaptionMoveArea {
                        objectName: "settingsTitleDragArea"
                        hostWindow: root
                        anchors.fill: parent
                        onDoubleClickRequested: root.toggleMaximize()
                    }
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
            objectName: "settingsCommands"
            Layout.fillWidth: true
            leftPadding: Math.max(root.resizeInset + 2, root.frameSafeInset)
            rightPadding: Math.max(root.resizeInset + 2, root.frameSafeInset)
            topPadding: 4
            bottomPadding: 5
            leftInset: 8
            rightInset: 8
            topInset: 2
            bottomInset: 1
            background: GlassSurface { role: "toolbar"; roundedPanel: true; backdropAvailable: settingsBackdrop.backdropAvailable }
            contentItem: RowLayout {
                spacing: 8
                Label {
                    Layout.fillWidth: true
                    text: root.saving ? qsTr("Saving…") : root.reading ? qsTr("Loading settings…") : root.notice ||
                        (engine.ready ? qsTr("Auralis %1").arg(engine.version) : engine.status)
                    elide: Text.ElideRight
                    color: root.colors.muted
                }
                GlassButton {
                    objectName: "openSetupWizard"
                    text: qsTranslate("StartupSetup", "Set up Auralis")
                    enabled: engine.ready
                    onClicked: root.setupRequested()
                }
                GlassButton {
                    objectName: "settingsDone"
                    text: qsTr("Done")
                    accent: root.colors.positive
                    highlighted: true
                    onClicked: root.close()
                }
            }
        }
    }

    RowLayout {
        id: settingsLayout
        anchors.fill: parent
        anchors.margins: 12
        anchors.rightMargin: root.resizeInset
        anchors.bottomMargin: root.resizeInset
        spacing: 12

        Frame {
            id: navigationSidebar
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
                            readonly property color navigationInk: flatSelection
                                ? MaterialTheme.controlTextInk(root.colors.sidebarInk || root.colors.text, engagedFace)
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
            Layout.fillWidth: true
            Layout.fillHeight: true
            padding: 13
            background: GlassSurface {
                visible: !root.wideSweepVisible
                role: "content"
                roundedPanel: true
                backdropAvailable: settingsBackdrop.backdropAvailable
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 10

                TextField {
                    id: search
                    objectName: "settingsSearch"
                    Layout.fillWidth: true
                    placeholderText: qsTr("Search settings…")
                    Accessible.name: placeholderText
                    selectByMouse: true
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
                        spacing: 12

                        Label {
                            Layout.fillWidth: true
                            text: root.term ? qsTr("Search results") : root.chosen.name
                            color: root.colors.text
                            font.pixelSize: TypographyScale.pixels(26)
                            font.weight: Font.Bold
                        }

                        PaneCopy { visible: !root.term; text: root.chosen.detail }
                        PaneCopy {
                            visible: Boolean(root.term) && !root.visibleFields.length
                            text: root.destinationSections.length ? qsTr("Open a matching section from the sidebar.") : qsTr("No matching settings.")
                        }

                        Card {
                            visible: root.visibleFields.length > 0
                            ColumnLayout {
                                width: parent.width
                                spacing: 12
                                Repeater {
                                    model: root.visibleFields
                                    delegate: SettingsField {
                                        required property var modelData
                                        Layout.fillWidth: true
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
                                                property string restartProblem: ""
                                                readonly property bool restartRequired: root.fontSettings?.interfaceScalePercent
                                                    !== root.fontSettings?.activeInterfaceScalePercent

                                                Layout.fillWidth: true
                                                from: root.fontSettings?.interfaceScaleMinimum ?? 85
                                                to: root.fontSettings?.interfaceScaleMaximum ?? 150
                                                stepSize: 1
                                                snapMode: Slider.SnapAlways
                                                live: false
                                                value: root.fontSettings?.interfaceScalePercent ?? 100
                                                palette.highlight: root.colors.accent
                                                Accessible.name: qsTr("Interface size")

                                                function saveSelection() {
                                                    const percent = Math.round(value)
                                                    if (percent === root.fontSettings.interfaceScalePercent)
                                                        return
                                                    restartProblem = ""
                                                    saveFailed = !root.fontSettings.setInterfaceScalePercent(percent)
                                                    if (saveFailed)
                                                        value = Qt.binding(() => root.fontSettings.interfaceScalePercent)
                                                }
                                                onMoved: if (!pressed) saveSelection()
                                                onPressedChanged: if (!pressed) saveSelection()
                                            }

                                            NumeralLabel {
                                                valueText: qsTr("%1%").arg(Math.round(interfaceSize.valueAt(interfaceSize.position)))
                                                color: root.colors.text
                                            }
                                        }

                                        PaneCopy {
                                            text: interfaceSize.restartRequired
                                                ? qsTr("Saved %2% for the next launch. The current size is %1%. Quit Auralis and reopen it to apply.")
                                                    .arg(root.fontSettings?.activeInterfaceScalePercent)
                                                    .arg(root.fontSettings?.interfaceScalePercent)
                                                : qsTr("Resizes controls, text, and spacing throughout Auralis after you quit and reopen the app.")
                                        }

                                        GlassButton {
                                            objectName: "restartForInterfaceScale"
                                            visible: interfaceSize.restartRequired
                                            enabled: !engine.quitting
                                            text: engine.quitting ? qsTr("Restarting…") : qsTr("Restart Auralis")
                                            accent: root.colors.accent
                                            filled: true
                                            onClicked: {
                                                interfaceSize.restartProblem = ""
                                                engine.requestRestart()
                                            }
                                        }

                                        Connections {
                                            target: engine
                                            function onRestartFailed(message) {
                                                interfaceSize.restartProblem = qsTranslate("BackendErrors", message)
                                            }
                                        }

                                        PaneCopy {
                                            visible: interfaceSize.restartRequired && interfaceSize.restartProblem !== ""
                                            text: interfaceSize.restartProblem
                                            textFormat: Text.PlainText
                                            color: root.colors.destructive
                                        }

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

                        SettingsUpdates {
                            Layout.fillWidth: true
                            visible: !root.term && root.category === "Updates"
                            backdropAvailable: settingsBackdrop.backdropAvailable
                            updatePresentation: root.updatePresentation
                            automaticChecks: root.automaticUpdateChecks
                            onUpdatePresentationRequested: value => updatePrefs.presentation = value
                            onAutomaticChecksRequested: value => updatePrefs.automaticChecks = value
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
        windowMouseEvents: true
        borderSize: 11
        cornerSize: 19
        showGrip: true
        gripColor: root.colors.muted
    }
}
