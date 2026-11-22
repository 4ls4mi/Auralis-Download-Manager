import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "TransferData.js" as Transfer

QtObject {
    id: root
    property Item popupParent
    property string material: MaterialTheme.current
    property bool autoProgress: true
    signal showProgressRequested(var downloadId)
    signal downloadCompleted(var downloadId)
    signal quitRequested()
    readonly property var colors: MaterialTheme.profile(material)
    property bool polling: false
    property bool exitSeen: false
    property var previousStatuses: null
    property var queuedProgressIds: []
    property var completed: []
    property var settings: ({})
    property int settingRefresh: 0
    property int completionPreferenceRevision: 0

    function refresh() {
        if (!popupParent || !engine.ready || polling)
            return
        if (settingRefresh++ % 10 === 0) {
            const revision = completionPreferenceRevision
            engine.request({query: "glass-settings"}, function (reply, error) {
                if (revision === completionPreferenceRevision && !Transfer.problem(reply, error) && reply) {
                    settings = reply
                    if (settings.show_complete === false)
                        completed = []
                }
            })
        }
        if (question.visible) {
            if (question.kind === "power" && !question.busy)
                refreshPower()
            return
        }
        if (video.visible || links.visible)
            return
        polling = true
        engine.request({query: "glass-file-info"}, function (reply, error) {
            const issue = Transfer.problem(reply, error)
            if (issue) {
                polling = false
                return
            }
            if (reply && reply.info) {
                polling = false
                if (!fileInfo.busy)
                    fileInfo.openForRequest(reply)
                return
            }
            if (fileInfo.visible) {
                if (!fileInfo.busy)
                    fileInfo.hide()
                polling = false
                return
            }
            pollQuestions()
        })
    }

    function refreshPower() {
        polling = true
        engine.request({query: "glass-power"}, function (reply, error) {
            polling = false
            if (Transfer.problem(reply, error) || !reply)
                return
            if (reply.exit && !exitSeen) {
                exitSeen = true
                quitRequested()
            }
            if (!question.visible || question.kind !== "power" || question.busy)
                return
            if (reply.pending && reply.id === question.info.id)
                question.info = {id: reply.id, data: reply.pending}
            else
                question.hide()
        })
    }

    function pollQuestions() {
        engine.request({query: "glass-power"}, function (power, error) {
            if (!Transfer.problem(power, error) && power) {
                if (power.exit && !exitSeen) {
                    exitSeen = true
                    polling = false
                    quitRequested()
                    return
                }
                if (power.pending) {
                    polling = false
                    question.present("power", {id: power.id, data: power.pending})
                    return
                }
            }
            engine.request({query: "glass-prompts"}, function (reply, error) {
                if (!Transfer.problem(reply, error) && reply) {
                    if (reply.duplicate || reply.queue) {
                        polling = false
                        question.present(reply.duplicate ? "duplicate" : "queue", reply.duplicate || reply.queue)
                        return
                    }
                }
                if (!completion.visible && settings.show_complete === true && completed.length > 0) {
                    const file = completed[0]
                    completed = completed.slice(1)
                    completion.present(file)
                }
                pollBrowserPrompts()
            })
        })
    }

    function pollBrowserPrompts() {
        engine.request({query: "glass-videos"}, function (reply, error) {
            if (!Transfer.problem(reply, error) && reply && reply.ids && reply.ids.length) {
                polling = false
                video.present(reply.ids[0])
                return
            }
            engine.request({query: "glass-grabber-status"}, function (data, issue) {
                polling = false
                if (!Transfer.problem(data, issue) && data && data.pending)
                    links.present()
            })
        })
    }

    function showQueuedProgress() {
        const ids = queuedProgressIds
        queuedProgressIds = []
        if (!popupParent || !engine.ready || !autoProgress || settings.show_progress === false)
            return
        const active = new Set((engine.dashboard.downloads || [])
            .filter(item => item.status === "Downloading").map(item => String(item.id)))
        for (const id of ids) {
            if (active.has(String(id)))
                showProgressRequested(id)
        }
    }

    function trackDownloads() {
        const dashboard = engine.dashboard
        if (!dashboard || !dashboard.downloads || !popupParent)
            return
        const next = {}
        const previous = previousStatuses
        let pending = completed.slice()
        const started = []
        for (let file of dashboard.downloads) {
            const id = String(file.id)
            next[id] = file.status
            if (!previous || previous[id] === file.status)
                continue
            if (file.status === "Complete") {
                downloadCompleted(file.id)
                if (settings.show_complete !== false)
                    pending.push(file)
            } else if (file.status === "Downloading" && autoProgress && settings.show_progress !== false) {
                started.push(file.id)
            }
        }
        previousStatuses = next
        completed = pending
        if (started.length) {
            queuedProgressIds = Array.from(new Set(queuedProgressIds.concat(started)))
            // Engine snapshots update dashboard and visual state together.
            // Open a native progress window after those notifications finish.
            Qt.callLater(root.showQueuedProgress)
        }
    }

    property Connections engineState: Connections {
        target: engine
        function onDashboardChanged() { root.trackDownloads() }
    }
    property Timer promptTimer: Timer {
        interval: 850
        running: !!root.popupParent && engine.ready
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    readonly property Window hostWindow: popupParent ? popupParent.Window.window : null

    property AddDownloadDialog fileInfo: AddDownloadDialog {
        hostWindow: root.hostWindow
        material: root.material
    }

    property DownloadCompleteWindow completion: DownloadCompleteWindow {
        hostWindow: root.hostWindow
        material: root.material
        onCompletionPreferenceSaved: show => {
            root.completionPreferenceRevision++
            root.settings = Object.assign({}, root.settings, {show_complete: show})
            if (!show)
                root.completed = []
        }
    }

    property DetachedDialogWindow question: DetachedDialogWindow {
        id: prompt
        hostWindow: root.hostWindow
        material: root.material
        property string kind: ""
        property var info: ({})
        property string failure: ""
        property bool replacing: false
        width: 576
        onDismissRequested: cancel()
        title: kind === "duplicate" ? qsTr("Download already listed") : kind === "queue" ? qsTr("Choose a download queue")
            : qsTr("Download completion action")

        function present(type, data) {
            kind = type
            info = data
            failure = ""
            replacing = false
            if (type === "queue") {
                queueName.currentIndex = 0
                startQueue.checked = false
            }
            open()
        }

        function reply(payload, after) {
            busy = true
            failure = ""
            engine.request(payload, function (result, error) {
                busy = false
                failure = Transfer.problem(result, error)
                if (!failure) {
                    hide()
                    engine.refresh()
                    if (after)
                        after()
                }
            })
        }

        function choose(choice) {
            let response = {kind, lease: info.lease, cancel: choice < 0}
            if (kind === "duplicate")
                response.choice = choice
            else {
                response.name = queueName.currentText
                response.start = startQueue.checked
            }
            reply({action: "glass-prompt", queue: JSON.stringify(response)})
        }

        function power(action) {
            reply({action: "glass-power", queue: JSON.stringify({id: info.id, action})})
        }

        function cancel() {
            if (busy)
                return
            if (kind === "duplicate" || kind === "queue")
                choose(-1)
            else if (kind === "power")
                power("cancel")
            else
                hide()
        }

        bodyContent: [
            Label {
                Layout.fillWidth: true
                color: root.colors.text
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: prompt.kind === "duplicate" ? qsTr("%1 is already in your download list.").arg(prompt.info.file || qsTr("This file"))
                    : prompt.kind === "queue" ? qsTr("%1 download(s) are waiting for a queue.").arg(prompt.info.count || 0)
                    : prompt.kind === "power" && prompt.info.data ? qsTr("%1 in %2 second(s).").arg(prompt.info.data.mode === "ShutDown"
                       ? qsTr("Shut down") : prompt.info.data.mode === "Hibernate" ? qsTr("Hibernate") : qsTr("Sleep")).arg(prompt.info.data.seconds)
                    : prompt.info.file || ""
            },
            GlassComboBox {
                id: queueName
                visible: prompt.kind === "queue"
                Layout.fillWidth: true
                model: prompt.kind === "queue" ? prompt.info.queues || [] : []
                Accessible.name: qsTr("Download queue")
            },
            CheckBox { id: startQueue; visible: prompt.kind === "queue"; text: qsTr("Start the queue now") },
            Label {
                visible: prompt.kind === "duplicate" && prompt.replacing
                Layout.fillWidth: true
                text: qsTr("The existing download and its file will be replaced.")
                wrapMode: Text.WordWrap
                color: root.colors.caution
            },
            Label {
                visible: prompt.failure !== ""
                Layout.fillWidth: true
                text: prompt.failure
                wrapMode: Text.WordWrap
                color: root.colors.destructive
            }
        ]
        footer: Item {
            implicitHeight: promptActions.implicitHeight + 20
            GlassSurface { anchors.fill: parent; material: root.material; role: "footer" }
            Flow {
                id: promptActions
                anchors.fill: parent
                anchors.margins: 10
                spacing: 7
                GlassButton { material: root.material; text: qsTr("Cancel"); enabled: !prompt.busy; onClicked: prompt.cancel() }
                GlassButton { material: root.material; text: qsTr("Use existing"); visible: prompt.kind === "duplicate"; enabled: !prompt.busy; onClicked: prompt.choose(3) }
                GlassButton { material: root.material; text: qsTr("Keep both"); visible: prompt.kind === "duplicate"; enabled: !prompt.busy; onClicked: prompt.choose(1) }
                GlassButton {
                    material: root.material
                    text: prompt.replacing ? qsTr("Confirm replace") : qsTr("Replace existing…")
                    accent: root.colors.destructive
                    visible: prompt.kind === "duplicate"
                    enabled: !prompt.busy
                    onClicked: {
                        if (prompt.replacing)
                            prompt.choose(2)
                        else
                            prompt.replacing = true
                    }
                }
                GlassButton { material: root.material; text: qsTr("Add to queue"); visible: prompt.kind === "queue"; enabled: !prompt.busy && queueName.currentIndex >= 0; onClicked: prompt.choose(0) }
                GlassButton { material: root.material; text: qsTr("Run now"); accent: root.colors.caution; visible: prompt.kind === "power"; enabled: !prompt.busy; onClicked: prompt.power("execute") }
            }
        }
    }

    property VideoRequestDialog video: VideoRequestDialog {
        parent: root.popupParent
        material: root.material
    }
    property BrowserLinksDialog links: BrowserLinksDialog {
        parent: root.popupParent
        material: root.material
    }
}
