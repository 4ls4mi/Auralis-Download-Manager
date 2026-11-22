pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "TransferData.js" as Transfer

Dialog {
    id: root
    property string material: MaterialTheme.current
    readonly property var colors: MaterialTheme.palette
    property var links: []
    property var packages: []
    property bool hidePages: true
    property bool busy: false
    property string failure: ""
    readonly property bool hasSelection: links.some(link => link.selected)
    readonly property var editingPackage: packages[packageMenu.currentIndex] || null
    title: qsTr("Link grabber")
    modal: true
    closePolicy: Popup.NoAutoClose
    anchors.centerIn: parent
    width: Math.min(650, parent ? parent.width - 28 : 650)
    padding: 16

    function present() {
        if (visible || busy)
            return
        failure = ""
        pasted.clear()
        packages = []
        links = []
        open()
        load()
    }

    function load() {
        if (busy)
            return
        busy = true
        engine.request({query: "glass-grabber-state"}, (reply, error) => {
            busy = false
            failure = Transfer.problem(reply, error)
            if (failure)
                return
            const state = reply && reply.data ? reply.data : {}
            links = state.links || []
            packages = state.packages || []
            hidePages = state.hide_pages !== false
        })
    }

    function update(payload, done) {
        if (busy)
            return
        busy = true
        engine.request({action: "glass-grabber", queue: JSON.stringify(payload)}, (reply, error) => {
            busy = false
            failure = Transfer.problem(reply, error)
            if (failure)
                return
            if (payload.operation === "import")
                pasted.clear()
            if (done) {
                close()
                engine.refresh()
            } else {
                load()
            }
        })
    }

    function showPackage() {
        if (!editingPackage)
            return
        packageName.text = editingPackage.name || ""
        packageFolder.text = editingPackage.folder || ""
        packageExtract.checked = editingPackage.extract === true
        packageDelete.checked = editingPackage.delete === true
        password.clear()
        packageDialog.open()
    }

    function cancel() {
        if (packages.length)
            update({operation: "clear"}, true)
        else
            close()
    }

    background: GlassSurface { material: root.material; role: "modal" }
    header: Label { text: root.title; color: root.colors.ink; font.pixelSize: 20; font.bold: true; padding: 16; bottomPadding: 4 }
    contentItem: ColumnLayout {
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                TextArea {
                    id: pasted
                    objectName: "importText"
                    placeholderText: qsTr("Paste links or a compatible download list")
                    Accessible.name: placeholderText
                    wrapMode: TextEdit.Wrap
                    selectByMouse: true
                    color: root.colors.ink
                    placeholderTextColor: root.colors.muted
                    background: GlassSurface { role: "field" }
                }
            }
            GlassButton {
                text: qsTr("Import")
                accent: root.colors.accent
                enabled: !root.busy && pasted.text.trim().length > 0
                onClicked: root.update({operation: "import", text: pasted.text}, false)
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Label { text: qsTr("%1 links").arg(root.links.length); color: root.colors.muted; Layout.fillWidth: true }
            CheckBox {
                text: qsTr("Hide HTML pages")
                enabled: !root.busy && root.packages.length > 0
                checked: root.hidePages
                onClicked: root.update({hide_pages: checked}, false)
            }
        }
        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(190, Math.max(54, root.links.length * 32))
            clip: true
            contentWidth: availableWidth
            ListView {
                model: root.links
                reuseItems: true
                delegate: CheckDelegate {
                    required property var modelData
                    width: ListView.view.width
                    text: (modelData.name || modelData.url) + "  ·  " + Transfer.bytes(modelData.size) + "  ·  " + modelData.state
                    checked: modelData.selected
                    enabled: !root.busy
                    onClicked: root.update({link: modelData.id, selected: checked}, false)
                }
            }
        }
        RowLayout {
            visible: root.packages.length > 0
            Layout.fillWidth: true
            ComboBox {
                id: packageMenu
                Layout.fillWidth: true
                model: root.packages
                textRole: "name"
                Accessible.name: qsTr("Package")
            }
            GlassButton {
                text: qsTr("Package options…")
                enabled: !root.busy && root.editingPackage !== null
                onClicked: root.showPackage()
            }
        }
        Label {
            visible: root.failure !== ""
            Layout.fillWidth: true
            text: root.failure
            wrapMode: Text.WordWrap
            color: root.colors.destructive
        }
        RowLayout {
            Layout.fillWidth: true
            GlassButton { material: root.material; text: qsTr("Cancel"); enabled: !root.busy; onClicked: root.cancel() }
            Item { Layout.fillWidth: true }
            GlassButton { material: root.material; text: qsTr("Add to queue"); enabled: !root.busy && root.hasSelection; onClicked: root.update({operation: "commit", start: false}, true) }
            GlassButton { material: root.material; accent: root.colors.positive; text: qsTr("Start downloads"); enabled: !root.busy && root.hasSelection; onClicked: root.update({operation: "commit", start: true}, true) }
        }
    }

    Dialog {
        id: packageDialog
        title: qsTr("Package options")
        parent: root.contentItem
        anchors.centerIn: parent
        width: Math.min(440, root.width - 28)
        modal: true
        standardButtons: Dialog.Save | Dialog.Cancel
        onAccepted: {
            if (root.editingPackage)
                root.update({package: root.editingPackage.id, name: packageName.text.trim(),
                    folder: packageFolder.text.trim(), password: password.text, extract: packageExtract.checked,
                    delete: packageExtract.checked && packageDelete.checked}, false)
            password.clear()
        }
        onRejected: password.clear()
        ColumnLayout {
            anchors.fill: parent
            TextField { id: packageName; Layout.fillWidth: true; placeholderText: qsTr("Package name"); Accessible.name: placeholderText }
            TextField { id: packageFolder; Layout.fillWidth: true; placeholderText: qsTr("Destination folder"); Accessible.name: placeholderText }
            TextField { id: password; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: qsTr("Archive password"); Accessible.name: placeholderText }
            CheckBox { id: packageExtract; text: qsTr("Extract archives when downloads finish") }
            CheckBox { id: packageDelete; text: qsTr("Delete archives after successful extraction"); enabled: packageExtract.checked }
        }
    }

    Timer {
        interval: 1700
        repeat: true
        running: root.visible && root.links.some(link => link.state === "Checking") && !packageDialog.visible
        onTriggered: root.load()
    }
    Shortcut { sequence: "Escape"; enabled: root.visible && !root.busy && !packageDialog.visible; onActivated: root.cancel() }
}
