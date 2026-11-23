pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "TransferData.js" as Transfer

Dialog {
    id: root

    property string material: MaterialTheme.current
    readonly property var colors: MaterialTheme.palette
    property var requestId: null
    readonly property bool manual: requestId === null
    property var lookupResult: ({})
    readonly property var choices: (lookupResult.choices || []).map((choice, index) => ({
        index: index,
        audio: Boolean(choice.audio),
        text: choice.label + (choice.size === null || choice.size === undefined ? "" : " · " + (choice.approx ? "≈ " : "") + Transfer.bytes(choice.size))
    }))
    readonly property bool hasVideo: choices.some(choice => !choice.audio)
    readonly property bool hasAudio: choices.some(choice => choice.audio)
    readonly property var visibleChoices: choices.filter(choice => hasVideo && hasAudio ? choice.audio === (qualityTabs.currentIndex === 1) : true)
    property var subtitles: []
    property bool busy: false
    property string failure: ""
    property string trackedToken: ""

    modal: true
    closePolicy: Popup.NoAutoClose
    anchors.centerIn: parent
    width: Math.min(560, parent ? parent.width - 28 : 560)
    padding: 18
    title: manual ? qsTr("Download video from a page") : qsTr("Download video")

    function clearLookup() {
        lookupResult = {}
        subtitles = [{name: qsTr("No subtitles"), code: "", automatic: false}]
        trackedToken = ""
        failure = ""
        qualityTabs.currentIndex = 0
        language.currentIndex = 0
        embed.checked = false
    }

    function presentLookup() {
        if (busy || visible)
            return
        requestId = null
        clearLookup()
        address.clear()
        cookieHeader.clear()
        cookieMode.currentIndex = 0
        open()
        address.forceActiveFocus()
    }

    function present(id) {
        if (busy || visible)
            return
        requestId = id
        clearLookup()
        open()
        send({query: "glass-video", ids: [requestId]}, reply => acceptResult(reply.result || {}))
    }

    function acceptResult(data) {
        lookupResult = data
        if (data.state !== "ready" || !data.token || trackedToken === data.token)
            return
        trackedToken = data.token
        const token = data.token
        engine.request({query: "glass-video-tracks", queue: token}, (reply, error) => {
            if (!reply || Transfer.problem(reply, error) || trackedToken !== token)
                return
            const list = [{name: qsTr("No subtitles"), code: "", automatic: false}]
            if ((reply.subtitles || []).length)
                list.push({name: qsTr("All available subtitles"), code: "all", automatic: false})
            for (const track of reply.subtitles || [])
                list.push({name: track.name + " (" + track.code + ")", code: track.code, automatic: false})
            if ((reply.automatic || []).length)
                list.push({name: qsTr("All automatic captions"), code: "all", automatic: true})
            for (const track of reply.automatic || [])
                list.push({name: track.name + " (" + track.code + ") · " + qsTr("automatic"), code: track.code, automatic: true})
            subtitles = list
            language.currentIndex = 0
        })
    }

    function send(command, received) {
        if (busy)
            return
        busy = true
        failure = ""
        engine.request(command, (reply, error) => {
            busy = false
            failure = Transfer.problem(reply, error)
            if (!failure)
                received(reply || {})
        })
    }

    function lookup() {
        const url = address.text.trim()
        if (!/^https?:\/\//i.test(url) || url.length > 8192)
            return
        clearLookup()
        const command = {video_lookup: {address: url}}
        if (cookieMode.currentIndex === 1) {
            command.video_cookie_browser = browser.currentText.toLowerCase()
            command.video_explicit_cookies = true
        } else if (cookieMode.currentIndex === 2) {
            const cookies = cookieHeader.text.trim()
            if (!cookies.includes("=") || /[\r\n\0]/.test(cookies)) {
                failure = qsTr("Enter cookies as name=value pairs separated by semicolons.")
                return
            }
            command.cookies = cookies
            command.video_explicit_cookies = true
        }
        send(command, acceptResult)
    }

    function cancel() {
        if (manual)
            close()
        else
            send({action: "glass-video", category: "close", ids: [requestId]}, () => close())
    }

    function commit() {
        const choice = visibleChoices[quality.currentIndex]
        if (!choice || !lookupResult.token)
            return
        const track = subtitles[language.currentIndex] || {}
        const subs = {langs: track.code ? [track.code] : [], automatic: Boolean(track.automatic), embed: !choice.audio && embed.checked}
        const command = manual
            ? {show: "glass-manual-video", video_pick: {token: lookupResult.token, choice: choice.index},
               category: "glass-subtitles", queue: JSON.stringify(subs)}
            : {action: "glass-video", ids: [requestId], queue: JSON.stringify({choice: choice.index, subs: subs})}
        send(command, reply => {
            if (["started", "queued", "sent"].includes(reply.state)) {
                cancel()
                engine.refresh()
            } else {
                acceptResult(reply)
            }
        })
    }

    onClosed: cookieHeader.clear()
    Timer {
        interval: 950
        repeat: true
        running: root.visible && root.lookupResult.state === "pending"
        onTriggered: {
            if (root.lookupResult.token)
                root.send({video_poll: root.lookupResult.token}, root.acceptResult)
        }
    }
    background: GlassSurface { material: root.material; role: "modal" }
    header: Label { text: root.title; color: root.colors.ink; font.pixelSize: 20; font.bold: true; padding: 16; bottomPadding: 4 }
    contentItem: ColumnLayout {
        spacing: 9
        RowLayout {
            visible: root.manual
            Layout.fillWidth: true
            TextField {
                id: address
                objectName: "videoAddress"
                Layout.fillWidth: true
                placeholderText: qsTr("Video page URL")
                Accessible.name: qsTr("Video page URL")
                maximumLength: 8192
                selectByMouse: true
                enabled: !root.busy && root.lookupResult.state !== "pending"
                color: root.colors.ink
                placeholderTextColor: root.colors.muted
                background: GlassSurface { role: "field" }
                onAccepted: root.lookup()
            }
            GlassButton {
                text: qsTr("Fetch qualities")
                accent: root.colors.accent
                enabled: address.enabled && /^https?:\/\//i.test(address.text.trim())
                onClicked: root.lookup()
            }
        }
        RowLayout {
            visible: root.manual
            Layout.fillWidth: true
            Label { text: qsTr("Cookies"); color: root.colors.ink }
            GlassComboBox {
                id: cookieMode
                Layout.fillWidth: true
                Accessible.name: qsTr("Cookies")
                model: [qsTr("Use app settings"), qsTr("Read browser cookies"), qsTr("Paste cookies")]
            }
            GlassComboBox {
                id: browser
                visible: cookieMode.currentIndex === 1
                Accessible.name: qsTr("Browser")
                model: ["Edge", "Chrome", "Firefox", "Brave", "Chromium", "Opera", "Vivaldi"]
            }
        }
        TextField {
            id: cookieHeader
            visible: root.manual && cookieMode.currentIndex === 2
            Layout.fillWidth: true
            echoMode: TextInput.Password
            maximumLength: 8192
            placeholderText: qsTr("name=value; …")
            Accessible.name: qsTr("Cookie header")
            background: GlassSurface { role: "field" }
        }
        Label { visible: Boolean(root.lookupResult.title); text: root.lookupResult.title || ""; textFormat: Text.PlainText; color: root.colors.ink; Layout.fillWidth: true; elide: Text.ElideRight }
        Label {
            visible: (root.lookupResult.state && root.lookupResult.state !== "ready") || root.failure !== ""
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: root.failure ? root.colors.destructive : root.colors.muted
            text: root.failure || (root.lookupResult.state === "pending" ? qsTr("Looking up available qualities…")
                 : root.lookupResult.reason === "no-ytdlp" ? qsTr("Install yt-dlp from Settings → Advanced.")
                 : root.lookupResult.message || root.lookupResult.reason || qsTr("This video could not be loaded."))
            textFormat: Text.PlainText
        }
        TabBar {
            id: qualityTabs
            visible: root.hasAudio && root.hasVideo
            Layout.fillWidth: true
            GlassTabButton { text: qsTr("Video"); material: root.material }
            GlassTabButton { text: qsTr("Audio"); material: root.material; accent: root.colors.secondary }
            onCurrentIndexChanged: quality.currentIndex = root.visibleChoices.length ? 0 : -1
        }
        RowLayout {
            visible: root.subtitles.length > 1
            Layout.fillWidth: true
            Label { text: qsTr("Subtitle language"); color: root.colors.ink }
            GlassComboBox {
                id: language
                Layout.fillWidth: true
                model: root.subtitles
                textRole: "name"
                Accessible.name: qsTr("Subtitle language")
            }
        }
        CheckBox {
            id: embed
            visible: language.visible && root.hasVideo && (!root.hasAudio || qualityTabs.currentIndex === 0)
            enabled: language.currentIndex > 0
            text: qsTr("Embed a selectable subtitle track")
        }
        GlassComboBox {
            id: quality
            objectName: "videoQuality"
            Layout.fillWidth: true
            visible: root.visibleChoices.length > 0
            model: root.visibleChoices
            textRole: "text"
            Accessible.name: qsTr("Quality")
        }
        RowLayout {
            Layout.fillWidth: true
            GlassButton { material: root.material; text: qsTr("Cancel"); enabled: !root.busy; onClicked: root.cancel() }
            Item { Layout.fillWidth: true }
            GlassButton {
                material: root.material
                accent: root.colors.positive
                text: qsTr("Download")
                enabled: !root.busy && root.lookupResult.state === "ready" && quality.currentIndex >= 0
                onClicked: root.commit()
            }
        }
    }
    Shortcut { sequence: "Escape"; enabled: root.visible && !root.busy; onActivated: root.cancel() }
}
