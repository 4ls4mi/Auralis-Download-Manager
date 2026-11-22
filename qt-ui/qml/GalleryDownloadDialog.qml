pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import "TransferData.js" as Transfer

Dialog {
    id: root
    readonly property var colors: MaterialTheme.palette
    property bool busy: false
    property string failure: ""
    signal helpersRequested()

    title: qsTr("Download a gallery")
    modal: true
    closePolicy: busy ? Popup.NoAutoClose : Popup.CloseOnEscape
    anchors.centerIn: parent
    width: Math.min(520, parent ? parent.width - 28 : 520)
    padding: 17

    function present() {
        address.clear()
        folder.clear()
        limit.clear()
        failure = ""
        open()
        address.forceActiveFocus()
    }

    function add(start) {
        busy = true
        failure = ""
        const payload = {url: address.text.trim(), folder: folder.text.trim(), limit: limit.text ? Number(limit.text) : null, start: start}
        engine.request({action: "glass-gallery", queue: JSON.stringify(payload)}, (reply, error) => {
            busy = false
            failure = Transfer.problem(reply, error)
            if (!failure) {
                engine.refresh()
                close()
            }
        })
    }
    FolderDialog {
        id: chooseFolder
        title: qsTr("Choose a gallery destination")
        onAccepted: {
            const url = decodeURIComponent(selectedFolder.toString())
            folder.text = url.startsWith("file:///") ? url.slice(7).replace(/^\/(?=[A-Za-z]:\/)/, "") : url.slice(5)
        }
    }
    background: GlassSurface { role: "modal" }
    header: Label { text: root.title; color: root.colors.ink; font.pixelSize: 20; font.bold: true; padding: 16; bottomPadding: 4 }
    contentItem: ColumnLayout {
        spacing: 8
        TextField {
            id: address
            objectName: "galleryAddress"
            Layout.fillWidth: true
            placeholderText: qsTr("Gallery page URL")
            Accessible.name: placeholderText
            maximumLength: 8192
        }
        RowLayout {
            Layout.fillWidth: true
            TextField {
                id: folder
                objectName: "galleryFolder"
                Layout.fillWidth: true
                placeholderText: qsTr("Default download folder")
                Accessible.name: qsTr("Save in folder")
            }
            GlassButton { text: qsTr("Choose folder…"); onClicked: chooseFolder.open() }
        }
        TextField {
            id: limit
            objectName: "galleryLimit"
            Layout.fillWidth: true
            placeholderText: qsTr("Maximum number of files (optional)")
            Accessible.name: placeholderText
            validator: IntValidator { bottom: 1 }
        }
        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root.failure || qsTr("Gallery downloads use gallery-dl and save to a separate folder.")
            color: root.failure ? root.colors.destructive : root.colors.muted
        }
        RowLayout {
            Layout.fillWidth: true
            GlassButton { text: qsTr("Cancel"); enabled: !root.busy; onClicked: root.close() }
            GlassButton { text: qsTr("Helpers…"); enabled: !root.busy; onClicked: { root.close(); root.helpersRequested() } }
            Item { Layout.fillWidth: true }
            GlassButton {
                text: qsTr("Download later")
                enabled: !root.busy && /^https?:\/\//i.test(address.text.trim()) && (!limit.text || limit.acceptableInput)
                onClicked: root.add(false)
            }
            GlassButton {
                text: qsTr("Download now")
                accent: root.colors.positive
                enabled: !root.busy && /^https?:\/\//i.test(address.text.trim()) && (!limit.text || limit.acceptableInput)
                onClicked: root.add(true)
            }
        }
    }
}
