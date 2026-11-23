pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import "TransferData.js" as Transfer

DetachedDialogWindow {
    id: root
    objectName: "downloadCompleteWindow"
    title: qsTr("Download complete")
    width: 660
    modality: Qt.NonModal

    property var backend: engine
    property var download: null
    property var file: null
    property bool fetching: false
    property string failure: ""
    property string moveTarget: ""
    property bool moved: false
    property bool suppressFuture: false
    readonly property bool canUseFile: file !== null && Boolean(file.path) && !file.moved_away
        && !file.moving && !moveTarget && !busy
    readonly property string exactBytes: file ? file.downloaded_exact : ""
    readonly property string byteCount: {
        const value = Number(exactBytes)
        return Number.isSafeInteger(value) ? value.toLocaleString(Qt.locale(), "f", 0) : exactBytes
    }
    signal completionPreferenceSaved(bool show)

    function present(entry) {
        download = entry
        file = null
        fetching = false
        failure = ""
        moveTarget = ""
        moved = false
        suppressFuture = false
        suppress.checked = false
        open()
        loadFile()
    }

    function loadFile() {
        if (!visible || !download || fetching)
            return
        const entry = download
        const requestedMove = moveTarget
        fetching = true
        root.backend.request({query: "glass-completion-details", ids: [entry.id]}, function (reply, error) {
            if (root.download !== entry || !root.visible)
                return
            fetching = false
            const issue = Transfer.problem(reply, error)
            if (issue || !reply) {
                if (!file)
                    failure = issue || qsTr("The completed download could not be found.")
                return
            }
            const oldPath = file ? file.path : entry.path
            if (!file)
                failure = ""
            file = reply
            if (requestedMove && requestedMove === moveTarget && !reply.moving) {
                moved = reply.path === moveTarget && !reply.moved_away
                failure = moved ? "" : qsTr("The file could not be moved. Check that the destination is writable.")
                moveTarget = ""
            } else if (oldPath && reply.path !== oldPath && !reply.moved_away) {
                moved = true
            }
        })
    }

    function useFile(operation) {
        if (!canUseFile)
            return
        const entry = download
        busy = true
        failure = ""
        root.backend.request({query: "glass-completion-details", ids: [entry.id]}, function (reply, error) {
            busy = false
            const issue = Transfer.problem(reply, error)
            if (issue || !reply || reply.moved_away || reply.moving || !reply.path) {
                failure = issue || qsTr("The saved file is being moved or is no longer at its saved location.")
                return
            }
            file = reply
            switch (operation) {
            case "move":
                movePicker.selectedFile = root.backend.localFileUrl(reply.path)
                movePicker.open()
                return
            case "open-with":
                busy = true
                root.backend.request({action: "glass-item", category: "open-with", ids: [entry.id]}, finishOpening)
                return
            case "folder":
                if (root.backend.openFolder(reply.path))
                    hide()
                else
                    failure = qsTr("The download folder could not be opened.")
                return
            default:
                if (root.backend.openPath(reply.path))
                    hide()
                else
                    failure = qsTr("The saved file could not be opened.")
            }
        })
    }

    function finishOpening(reply, error) {
        busy = false
        failure = Transfer.problem(reply, error)
        if (!failure)
            hide()
    }

    function moveFile(target) {
        if (!canUseFile || !target || target === file.path)
            return
        busy = true
        moved = false
        failure = ""
        root.backend.request({action: "glass-item", category: "move", ids: [download.id], queue: target}, function (reply, error) {
            busy = false
            failure = Transfer.problem(reply, error)
            if (!failure) {
                moveTarget = target
                loadFile()
            }
        })
    }

    function savePreference(checked) {
        failure = ""
        busy = true
        root.backend.request({action: "glass-setting", category: "show_complete", queue: checked ? "false" : "true"},
            function (reply, error) {
                busy = false
                failure = Transfer.problem(reply, error)
                if (!failure && reply && reply.saved) {
                    suppressFuture = checked
                    completionPreferenceSaved(!checked)
                } else {
                    suppress.checked = suppressFuture
                    if (!failure)
                        failure = qsTr("The completion window preference could not be saved.")
                }
            })
    }

    function startFileDrag() {
        if (!canUseFile)
            return
        failure = ""
        const entry = download
        root.backend.dragCompletedFile(root, entry.id, function (reply, error) {
            if (root.download === entry && root.visible)
                failure = Transfer.problem(reply, error)
        })
    }

    onDismissRequested: hide()
    onOpened: closeButton.forceActiveFocus()

    Timer {
        interval: 850
        repeat: true
        running: root.visible
        onTriggered: root.loadFile()
    }
    FileDialog {
        id: movePicker
        title: qsTr("Move download to an unused file name")
        fileMode: FileDialog.SaveFile
        onAccepted: root.moveFile(root.backend.localPath(selectedFile))
    }

    component CompletionField: TextField {
        id: field
        Layout.fillWidth: true
        readOnly: true
        selectByMouse: true
        color: root.colors.ink
        font.family: root.fontFamilyForText(text)
        padding: 10
        background: GlassSurface { material: root.material; role: "field" }
        PlainTextToolTip {
            visible: field.hovered && field.contentWidth > field.width - field.leftPadding - field.rightPadding
            text: field.text
        }
    }

    component CompletionButton: GlassButton {
        id: button
        property string symbol: ""
        material: root.material
        contentItem: Row {
            spacing: 6
            transform: Translate { y: button.faceOffset }
            DashboardIcon {
                visible: button.symbol !== ""
                symbol: button.symbol
                width: 17
                height: 17
                relief: button.enabled
                ink: button.iconInk
                surface: button.faceColor
                anchors.verticalCenter: parent.verticalCenter
            }
            Label {
                text: button.text
                font: button.font
                color: button.buttonInk
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    bodyContent: [
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            spacing: 12
            DashboardIcon {
                symbol: "complete"
                ink: root.colors.positive
                bold: true
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Label {
                    Layout.fillWidth: true
                    text: root.title
                    font.pixelSize: 23
                    font.bold: true
                    color: root.colors.ink
                    wrapMode: Text.Wrap
                }
                Label {
                    objectName: "completedDownloadSize"
                    Layout.fillWidth: true
                    text: root.exactBytes === "" ? qsTr("Loading download details…")
                        : root.exactBytes === "1" ? qsTr("Downloaded 1 byte")
                        : qsTr("Downloaded %1 (%2 bytes)").arg(Transfer.bytes(root.exactBytes)).arg(root.byteCount)
                    color: root.colors.muted
                    wrapMode: Text.Wrap
                }
            }
        },
        Label { text: qsTr("Address"); color: root.colors.ink },
        CompletionField {
            objectName: "completedDownloadAddress"
            Accessible.name: qsTr("Address")
            text: root.file ? root.file.url : root.download ? root.download.url : ""
        },
        Label { text: qsTr("The file saved as"); color: root.colors.ink; Layout.topMargin: 4 },
        CompletionField {
            objectName: "completedDownloadPath"
            Accessible.name: qsTr("The file saved as")
            text: root.file ? root.file.path : root.download ? root.download.path : ""
        },
        Flow {
            Layout.fillWidth: true
            Layout.topMargin: 8
            spacing: 7
            CompletionButton {
                objectName: "completedDownloadOpen"
                text: qsTr("Open")
                symbol: "file"
                accent: root.colors.positive
                filled: true
                enabled: root.canUseFile
                onClicked: root.useFile("open")
            }
            CompletionButton {
                objectName: "completedDownloadOpenWith"
                text: qsTr("Open with…")
                visible: Qt.platform.os === "windows"
                accent: root.colors.secondary
                enabled: root.canUseFile
                onClicked: root.useFile("open-with")
            }
            CompletionButton {
                objectName: "completedDownloadOpenFolder"
                text: qsTr("Open folder")
                symbol: "folder"
                accent: root.colors.caution
                enabled: root.canUseFile
                onClicked: root.useFile("folder")
            }
            CompletionButton {
                objectName: "completedDownloadMove"
                text: qsTr("Move file…")
                symbol: "move"
                enabled: root.canUseFile
                onClicked: root.useFile("move")
            }
            CompletionButton {
                id: closeButton
                objectName: "completedDownloadClose"
                text: qsTr("Close")
                symbol: "close"
                enabled: !root.busy
                onClicked: root.hide()
            }
        },
        Label {
            Layout.fillWidth: true
            visible: Boolean(text)
            text: root.failure || (root.file && root.file.moved_away ? qsTr("The file was moved, but Windows could not report its new location.")
                : root.moveTarget || root.file && root.file.moving ? qsTr("Moving the downloaded file…")
                : root.moved ? qsTr("The saved file location was updated.") : "")
            color: root.failure || root.file && root.file.moved_away ? root.colors.destructive : root.colors.muted
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        },
        Label {
            Layout.fillWidth: true
            visible: Boolean(text)
            text: root.file && root.file.notices ? root.file.notices.join("\n") : ""
            color: root.colors.caution
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
        }
    ]
    footer: Item {
        implicitHeight: footerItems.implicitHeight + 20
        GlassSurface { anchors.fill: parent; material: root.material; role: "footer" }
        Flow {
            id: footerItems
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8
            CheckBox {
                id: suppress
                objectName: "hideDownloadCompletion"
                width: Math.min(implicitWidth, footerItems.width)
                enabled: !root.busy
                text: qsTr("Don’t show this dialog again")
                onToggled: root.savePreference(checked)
            }
            CompletionButton {
                id: dragButton
                objectName: "completedDownloadDrag"
                text: qsTr("Drag file")
                symbol: "move"
                accent: root.colors.positive
                visible: Qt.platform.os === "windows"
                enabled: root.canUseFile
                focusPolicy: Qt.NoFocus
                ToolTip.visible: hovered && enabled
                ToolTip.text: qsTr("Drag the file into a folder or an app")
                HoverHandler { cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor }
                DragHandler {
                    id: drag
                    target: null
                    acceptedButtons: Qt.LeftButton
                    enabled: dragButton.enabled
                    onActiveChanged: if (active) root.startFileDrag()
                }
            }
        }
    }
}
