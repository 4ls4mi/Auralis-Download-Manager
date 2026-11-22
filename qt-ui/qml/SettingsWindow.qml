pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ApplicationWindow {
    id: root

    title: qsTr("Settings — Auralis Download Manager")
    width: 1050
    height: 760
    minimumWidth: 710
    minimumHeight: 540
    visible: false
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    palette.windowText: colors.text
    palette.text: colors.text
    palette.buttonText: colors.text
    palette.base: colors.background
    palette.button: colors.background
    palette.highlight: colors.accent

    readonly property var colors: MaterialTheme.palette
    property string category: "General"
    property var config: null
    property var advancedFields: []
    property bool saving: false
    property bool reading: false
    property string problem: ""
    property string notice: ""
    property var availableUpdate: null
    property bool showUpdateAfterLoad: false
    readonly property string updatePresentation: updatePrefs.presentation
    readonly property bool automaticUpdateChecks: updatePrefs.automaticChecks
    readonly property string cookieBrowser: String(advancedFields.find(field => field.key === "video_cookies")?.value ?? "")
    readonly property string term: search.text.trim().toLowerCase()
    readonly property var sections: [
        {id: "General", name: qsTr("General"), detail: qsTr("Startup, notifications, and backups"), terms: qsTr("start backup restore preferences notification window popup"),
            keys: ["start_immediately", "only_add_to_queue", "confirm_delete", "show_progress", "show_complete", "double_click_open",
                "minimize_to_tray", "close_to_tray", "progress_minimize_to_tray"]},
        {id: "Downloads", name: qsTr("Downloads"), detail: qsTr("File rules, folders, and archive extraction"), terms: qsTr("file folder category archive duplicates extract"), keys: []},
        {id: "Connection", name: qsTr("Connection"), detail: qsTr("Speed limits, proxy, and DNS"), terms: qsTr("speed throttle proxy dns network adapter login authentication"),
            keys: ["max_connections", "speed_limit_on", "speed_limit_kb", "global_limit_on", "global_limit_kb", "net_adapter"]},
        {id: "Browser Integration", name: qsTr("Browser integration"), detail: qsTr("Extension setup and browser download capture"), terms: qsTr("chrome edge connector install extension capture video subtitles cookies"),
            keys: ["capture_opened", "advanced_integration", "proxy_from_browser"]},
        {id: "Torrents", name: qsTr("Torrents"), detail: qsTr("Peer discovery and direct download recovery"), terms: qsTr("peer tracker torrent automatic recovery dht lsd share"),
            keys: ["torrent_keep_sharing", "torrent_dht", "torrent_lsd", "torrent_recovery_mode"]},
        {id: "Scheduler", name: qsTr("Scheduler"), detail: qsTr("Queue size, start times, and completion actions"), terms: qsTr("queue scheduler retry weekday schedule start stop"), keys: []},
        {id: "Accounts", name: qsTr("Accounts"), detail: qsTr("File hosts and supported service accounts"), terms: qsTr("account debrid host sign in token api"), keys: []},
        {id: "Appearance", name: qsTr("Appearance"), detail: qsTr("Materials, translucent backgrounds, and indicators"), terms: qsTr("theme tint glass dark light opacity translucent color material background indicator progress motion"), keys: []},
        {id: "Advanced", name: qsTr("Advanced"), detail: qsTr("Application updates, media helpers, and other preferences"), terms: qsTr("update release media helper ffmpeg yt-dlp tools preferences"), keys: []}
    ]
    readonly property var recoveryChoices: [
        {label: qsTr("Off — search manually"), value: "off"},
        {label: qsTr("Search and ask me"), value: "ask"},
        {label: qsTr("Continue automatically when unambiguous"), value: "auto"}
    ]
    readonly property var common: ({
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
        net_adapter: {label: qsTr("Network adapter"), kind: "text", description: qsTr("Leave empty to use the system default.")},
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
        sounds: {description: qsTr("Choose a WAV file for each download or queue event.")},
        video_cookies: {kind: "select", description: qsTr("Choose the browser where you signed in. Auralis uses the local browser session for media requests when the extension did not send cookies.")},
        video_cookies_file: {description: qsTr("A Netscape cookies.txt file takes precedence over the browser session. Treat the file like a password.")},
        video_cookies_profile: {description: qsTr("Use the browser’s default profile, enter its profile name, or choose its directory. In Chrome or Edge, open chrome://version or edge://version and look for Profile Path. In Firefox, open about:profiles and use the Root Directory.")}
    })
    readonly property var chosen: sections.find(section => section.id === category) || sections[0]
    readonly property var hiddenEngineFields: ["update_check", "speed_limit_on"]
    readonly property var visibleFields: matchingFields()
    readonly property var destinationSections: term ? sections.filter(section => matchesText(section.name + " " + section.terms) ||
        visibleFields.some(field => field.section === section.id)) : sections

    Settings {
        id: updatePrefs
        category: "UpdateNotices"
        property bool automaticChecks: true
        property string presentation: "toast"
    }

    onAvailableUpdateChanged: {
        if (availableUpdate && !tools.updateStage) tools.release = availableUpdate
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
                if (showUpdateAfterLoad) {
                    showUpdateAfterLoad = false
                    Qt.callLater(positionUpdateHeading)
                }
            })
        })
    }

    function matchesText(value) {
        if (!term) return true
        const text = String(value || "").toLowerCase()
        return term.split(/\s+/).every(part => text.includes(part))
    }

    function matchingFields() {
        const entries = []
        if (config) {
            for (const section of sections) {
                if (!term && category !== section.id) continue
                for (const key of section.keys) {
                    if (config[key] === undefined || !common[key]) continue
                    const field = common[key]
                    if (matchesText(key + " " + field.label + " " + (field.description || "")))
                        entries.push(Object.assign({}, field, {key: key, value: config[key], section: section.id, basic: true}))
                }
            }
        }
        for (const field of advancedFields) {
            if (hiddenEngineFields.includes(field.key)) continue
            if (!term && field.section !== category) continue
            const details = extraDetails[field.key]
            const entry = details ? Object.assign({}, field, details) : field
            if (field.key === "video_cookies") {
                const stored = String(entry.value || "").trim().toLowerCase()
                entry.value = stored
                entry.options = stored && !browserChoices.some(browser => browser.value === stored)
                    ? browserChoices.concat([{label: stored, value: stored}]) : browserChoices
            }
            if (matchesText(entry.key + " " + entry.label + " " + (entry.description || "")))
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
            if (error || !reply || reply.ok === false) problem = error || qsTr("Could not save this setting.")
            else { notice = qsTr("Settings saved"); load() }
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

    function positionUpdateHeading() {
        if (category !== "Advanced" || term)
            return
        const headingY = tools.updatesAnchor.mapToItem(scrollViewport.contentItem, 0, 0).y
        scrollViewport.contentY = Math.max(0, Math.min(headingY - 8,
            scrollViewport.contentHeight - scrollViewport.height))
    }

    function showUpdate(release) {
        if (release) tools.release = release
        showCategory("Advanced")
        showUpdateAfterLoad = reading
        Qt.callLater(positionUpdateHeading)
    }

    function toggleMaximize() {
        if (visibility === Window.Maximized) showNormal()
        else showMaximized()
    }

    onVisibleChanged: if (visible) load()
    onCategoryChanged: if (category === "Scheduler" && engine.ready && !scheduler.queues.length) scheduler.load()

    Connections {
        target: engine
        function onReadyChanged() {
            if (root.visible && engine.ready) root.load()
        }
    }

    background: WindowBackdrop {
        id: settingsBackdrop
        hostWindow: root
        target: "details"
    }

    component PaneCopy: Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: root.colors.muted
    }

    component SettingsScrollBar: ScrollBar {
        id: grip
        implicitWidth: 7
        padding: 1
        minimumSize: .08
        policy: ScrollBar.AsNeeded
        contentItem: Rectangle {
            implicitWidth: 5
            radius: width / 2
            color: root.colors.secondary
            opacity: grip.pressed ? .96 : grip.active ? .82 : .58
        }
        background: Item {}
    }

    component Card: Frame {
        Layout.fillWidth: true
        padding: 14
        background: GlassSurface { role: "content"; backdropAvailable: settingsBackdrop.backdropAvailable }
    }

    header: ToolBar {
        padding: 0
        background: GlassSurface { role: "title"; radius: 0; backdropAvailable: settingsBackdrop.backdropAvailable }

        contentItem: RowLayout {
            spacing: 7
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 45
                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: 15
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.title
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
            Item { Layout.preferredWidth: 4 }
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        Frame {
            Layout.fillHeight: true
            Layout.preferredWidth: 188
            padding: 9
            background: GlassSurface { role: "sidebar"; backdropAvailable: settingsBackdrop.backdropAvailable }

            ScrollView {
                id: navigation
                anchors.fill: parent
                clip: true
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical: SettingsScrollBar {}

                ColumnLayout {
                    width: navigation.availableWidth
                    spacing: 4
                    Repeater {
                        model: root.destinationSections
                        delegate: GlassButton {
                            required property var modelData
                            Layout.fillWidth: true
                            text: modelData.name
                            highlighted: root.category === modelData.id && !root.term
                            onClicked: root.showCategory(modelData.id)
                            Accessible.description: modelData.detail
                        }
                    }
                }
            }
        }

        Frame {
            Layout.fillWidth: true
            Layout.fillHeight: true
            padding: 13
            background: GlassSurface { role: "content"; backdropAvailable: settingsBackdrop.backdropAvailable }

            ColumnLayout {
                anchors.fill: parent
                spacing: 10

                TextField {
                    id: search
                    Layout.fillWidth: true
                    placeholderText: qsTr("Search settings…")
                    Accessible.name: placeholderText
                    selectByMouse: true
                    color: root.colors.text
                    placeholderTextColor: root.colors.muted
                    background: GlassSurface { role: "field"; backdropAvailable: settingsBackdrop.backdropAvailable }
                }

                ScrollView {
                    id: scroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: availableWidth
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ScrollBar.vertical: SettingsScrollBar {}

                    Flickable {
                        id: scrollViewport
                        contentWidth: width
                        contentHeight: settingsContent.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: settingsContent
                            width: scroll.availableWidth
                            spacing: 12

                            Label {
                                Layout.fillWidth: true
                                text: root.term ? qsTr("Search results") : root.chosen.name
                                color: root.colors.text
                                font.pixelSize: 26
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

                            SettingsScheduler {
                                id: scheduler
                                Layout.fillWidth: true
                                visible: !root.term && root.category === "Scheduler"
                            }

                            SettingsAccounts {
                                Layout.fillWidth: true
                                visible: !root.term && root.category === "Accounts"
                            }

                            SettingsTools {
                                id: tools
                                hostWindow: root
                                Layout.fillWidth: true
                                visible: !root.term && (root.category === "Advanced" || root.category === "Browser Integration")
                                section: root.category
                                updatePresentation: root.updatePresentation
                                automaticChecks: root.automaticUpdateChecks
                                onUpdatePresentationRequested: value => updatePrefs.presentation = value
                                onAutomaticChecksRequested: value => updatePrefs.automaticChecks = value
                                onReleaseChecked: value => root.availableUpdate = value.state === "available" ? value : null
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
    }

    WindowResizeHandles {
        parent: root.contentItem
        anchors.fill: parent
        hostWindow: root
        z: 20
    }

    footer: ToolBar {
        background: GlassSurface { role: "footer"; radius: 0; backdropAvailable: settingsBackdrop.backdropAvailable }
        contentItem: RowLayout {
            spacing: 8
            Label {
                Layout.fillWidth: true
                text: root.saving ? qsTr("Saving…") : root.reading ? qsTr("Loading settings…") : root.notice ||
                    (engine.ready ? qsTr("Auralis %1").arg(engine.version) : engine.status)
                elide: Text.ElideRight
                color: root.colors.muted
            }
            GlassButton { text: qsTr("Done"); highlighted: true; onClicked: root.close() }
        }
    }
}
