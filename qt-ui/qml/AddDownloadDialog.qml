import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window
import "TransferData.js" as Transfer

DetachedDialogWindow {
    id: root
    objectName: "addDownloadWindow"
    property bool torrentMode: false
    property var requestInfo: null
    readonly property bool confirming: requestInfo !== null
    property string errorMessage: ""
    property bool destinationEdited: false
    property var categoryOptions: []
    property int clipboardRead: 0
    signal downloadAdded(var id, bool later)

    width: 595
    flags: Qt.Window | Qt.WindowTitleHint | Qt.WindowSystemMenuHint | Qt.WindowMinMaxButtonsHint | Qt.WindowCloseButtonHint
    transientParent: null
    modality: Qt.NonModal
    title: confirming ? (requestInfo.info.video ? qsTr("Confirm video download") : qsTr("Download File Info"))
                      : torrentMode ? qsTr("Add torrent") : qsTr("Add URL")

    function openAddress(torrent) {
        const switchedWhileOpen = visible && !confirming && !busy && torrentMode !== torrent
        if (!confirming && !busy) {
            if (torrentMode !== torrent)
                ++clipboardRead
            torrentMode = torrent
        }
        if (visibility === Window.Minimized)
            showNormal()
        open()
        if (switchedWhileOpen)
            prefillAddress()
    }

    function isDownloadAddress(link) {
        return link.length <= 8192 && /^(https?|ftps?|ftpes):\/\//i.test(link)
    }

    function prefillAddress() {
        if (confirming || torrentMode || busy || address.text)
            return
        const read = ++clipboardRead
        engine.request({shellAction: "clipboard-prefill"}, function (reply, error) {
            if (read !== clipboardRead || !visible || visibility === Window.Minimized
                    || confirming || torrentMode || busy || address.text || error)
                return
            if (reply && typeof reply.url === "string" && isDownloadAddress(reply.url))
                address.text = reply.url
        })
    }

    function openForRequest(reply) {
        if (!reply || !reply.info)
            return
        const changed = !requestInfo || requestInfo.id !== reply.id
        requestInfo = reply
        categoryOptions = reply.categories || []
        if (changed) {
            destinationEdited = false
            errorMessage = ""
            description.text = reply.info.description || ""
            remember.checked = reply.info.remember || false
            connectionCount.value = 0
        }
        if (!destinationEdited)
            destination.text = reply.info.save_as || ""
        if (changed || !visible) {
            const index = categoryOptions.findIndex(item => item.key === reply.info.category)
            category.currentIndex = Math.max(0, index)
        }
        if (!visible)
            open()
    }

    function send(command, later) {
        busy = true
        errorMessage = ""
        engine.request(command, function (reply, error) {
            busy = false
            errorMessage = Transfer.problem(reply, error)
            if (errorMessage)
                return
            if (reply && reply.id !== undefined && reply.id !== null)
                downloadAdded(reply.id, later)
            hide()
            engine.refresh()
        })
    }

    function submit(later) {
        if (busy)
            return
        if (confirming) {
            const path = destination.text.trim()
            if (!path) {
                errorMessage = qsTr("Enter a destination file name.")
                return
            }
            send({action: "glass-file-info", category: "commit", ids: [requestInfo.id],
                queue: JSON.stringify({save_as: path, description: description.text,
                    remember: remember.checked, chunks: connectionCount.value || null, later})}, later)
            return
        }
        const link = address.text.trim()
        if (torrentMode ? link.length > 8192 || !(/^magnet:\?/i.test(link)) : !isDownloadAddress(link)) {
            errorMessage = torrentMode ? qsTr("Enter a magnet link, or open a .torrent file.")
                : qsTr("Enter a valid HTTP, HTTPS, FTP, FTPS or FTPES address.")
            return
        }
        // The backend handles duplicate decisions and supplies the live file-info
        // confirmation for regular links. Magnet links use its silent torrent add.
        send({url: link, silent: torrentMode}, false)
    }

    function cancel() {
        if (busy)
            return
        if (confirming)
            send({action: "glass-file-info", category: "cancel", ids: [requestInfo.id]}, true)
        else
            hide()
    }

    onOpened: {
        if (!confirming) {
            address.forceActiveFocus()
            prefillAddress()
        }
    }
    onDismissRequested: cancel()
    onDismissed: {
        ++clipboardRead
        requestInfo = null
        address.clear()
        destination.clear()
        description.clear()
        connectionCount.value = 0
        errorMessage = ""
        destinationEdited = false
    }

    bodyContent: [
        Label {
            Layout.fillWidth: true
            text: root.confirming ? root.requestInfo.info.url
                                  : root.torrentMode ? qsTr("Magnet link") : qsTr("Download address")
            color: root.colors.muted
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
        },
        TextField {
            id: address
            objectName: "downloadAddress"
            Layout.fillWidth: true
            visible: !root.confirming
            placeholderText: root.torrentMode ? "magnet:?xt=urn:btih:…" : "https://example.com/file.zip"
            color: root.colors.text
            background: GlassSurface { material: root.material; role: "field" }
            selectByMouse: true
            onTextEdited: ++root.clipboardRead
            onAccepted: root.submit(false)
            Accessible.name: qsTr("Download address")
        },
        Label {
            visible: !root.confirming && root.torrentMode
            color: root.colors.muted
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            text: qsTr("Starting a torrent contacts BitTorrent peers.")
        },
        Label {
            visible: root.confirming
            color: root.colors.muted
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            text: root.confirming ? root.requestInfo.info.probing
                  ? qsTr("Checking the source…") : qsTr("Size %1").arg(Transfer.bytes(root.requestInfo.info.size)) : ""
        },
        Label {
            visible: root.confirming && !!root.requestInfo.info.error
            Layout.fillWidth: true
            text: root.confirming ? String(root.requestInfo.info.error || "") : ""
            textFormat: Text.PlainText
            color: root.colors.caution
            wrapMode: Text.WordWrap
        },
        Label { visible: root.confirming; text: qsTr("Category"); color: root.colors.muted },
        GlassComboBox {
            id: category
            visible: root.confirming
            Layout.fillWidth: true
            textRole: "name"
            model: root.categoryOptions
            Accessible.name: qsTr("Category")
            onActivated: function (index) {
                if (!root.confirming || !root.categoryOptions[index])
                    return
                const id = root.requestInfo.id
                engine.request({action: "glass-file-info", category: "category", ids: [id],
                    queue: JSON.stringify({category: root.categoryOptions[index].key})}, function (reply, error) {
                    if (root.confirming && root.requestInfo.id === id)
                        root.errorMessage = Transfer.problem(reply, error)
                })
            }
        },
        Label {
            visible: root.confirming
            text: qsTr("Save as")
            color: root.colors.muted
        },
        RowLayout {
            visible: root.confirming
            Layout.fillWidth: true
            TextField {
                id: destination
            objectName: "downloadDestination"
                Layout.fillWidth: true
                placeholderText: qsTr("Destination file name")
                onTextEdited: root.destinationEdited = true
                color: root.colors.text
                font.family: root.fontFamilyForText(text)
                selectByMouse: true
                background: GlassSurface { material: root.material; role: "field" }
                Accessible.name: qsTr("Save as")
            }
            GlassButton {
                material: root.material
                text: qsTr("Browse…")
                onClicked: savePicker.open()
            }
        },
        TextField {
            id: description
            visible: root.confirming
            Layout.fillWidth: true
            placeholderText: qsTr("Description")
            color: root.colors.text
            font.family: root.fontFamilyForText(text)
            background: GlassSurface { material: root.material; role: "field" }
            Accessible.name: qsTr("Description")
        },
        CheckBox { id: remember; visible: root.confirming; text: qsTr("Remember the folder for this category") },
        RowLayout {
            visible: root.confirming
            Label { text: qsTr("Connections"); color: root.colors.muted }
            SpinBox {
                id: connectionCount
                objectName: "downloadConnectionCount"
                from: 0
                to: 128
                editable: true
                Accessible.name: qsTr("Connections")
            }
            Label { text: qsTr("0 uses the default"); color: root.colors.muted }
        },
        Label {
            visible: root.errorMessage !== ""
            Layout.fillWidth: true
            text: root.errorMessage
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.colors.destructive
            Accessible.name: text
        }
    ]

    footer: Item {
        implicitHeight: actions.implicitHeight + 26
        GlassSurface { anchors.fill: parent; material: root.material; role: "footer" }
        RowLayout {
            id: actions
            anchors.fill: parent
            anchors.margins: 14
            spacing: 9
            GlassButton { material: root.material; text: qsTr("Cancel"); enabled: !root.busy; onClicked: root.cancel() }
            Item { Layout.fillWidth: true }
            GlassButton {
                material: root.material
                text: qsTr("Open .torrent…")
                visible: root.torrentMode && !root.confirming
                enabled: !root.busy
                onClicked: torrentPicker.open()
            }
            GlassButton {
                material: root.material
                text: qsTr("Download later")
                visible: root.confirming
                enabled: !root.busy
                onClicked: root.submit(true)
            }
            GlassButton {
                material: root.material
                accent: root.colors.positive
                objectName: "confirmStartDownload"
                text: root.busy ? qsTr("Working…") : root.confirming || root.torrentMode ? qsTr("Start download") : qsTr("Continue")
                enabled: !root.busy
                onClicked: root.submit(false)
            }
        }
    }

    FileDialog {
        id: savePicker
        title: qsTr("Save download as")
        fileMode: FileDialog.SaveFile
        onAccepted: { destination.text = engine.localPath(selectedFile); root.destinationEdited = true }
    }
    FileDialog {
        id: torrentPicker
        title: qsTr("Choose a torrent file to add")
        nameFilters: [qsTr("Torrent files (*.torrent)")]
        onAccepted: root.send({action: "glass-torrent-file", dir: engine.localPath(selectedFile)}, false)
    }
}
