pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "TransferData.js" as Transfer

Dialog {
    id: root
    readonly property var colors: MaterialTheme.palette
    property bool busy: false
    property string failure: ""
    property var preview: null

    title: qsTr("Batch download")
    modal: true
    closePolicy: busy ? Popup.NoAutoClose : Popup.CloseOnEscape
    anchors.centerIn: parent
    width: Math.min(555, parent ? parent.width - 28 : 555)
    padding: 17

    function present() {
        address.clear()
        ranges.currentIndex = 0
        first.text = "1"
        last.text = "10"
        digits.value = 1
        username.clear()
        password.clear()
        failure = ""
        preview = null
        open()
        address.forceActiveFocus()
    }

    function run(commit) {
        busy = true
        failure = ""
        const payload = {address: address.text.trim(), letters: ranges.currentIndex === 1,
            from: first.text.trim(), to: last.text.trim(), width: String(digits.value),
            login: commit ? username.text : "", password: commit ? password.text : "", commit: commit}
        engine.request({action: "glass-batch", queue: JSON.stringify(payload)}, (reply, error) => {
            busy = false
            failure = Transfer.problem(reply, error)
            if (failure) return
            if (commit) {
                engine.refresh()
                close()
            } else {
                preview = reply
            }
        })
    }

    onClosed: password.clear()
    background: GlassSurface { role: "modal" }
    header: Label { text: root.title; color: root.colors.ink; font.pixelSize: TypographyScale.pixels(20); font.bold: true; padding: 16; bottomPadding: 4 }
    contentItem: ColumnLayout {
        spacing: 8
        TextField {
            id: address
            objectName: "batchAddress"
            Layout.fillWidth: true
            placeholderText: "https://example.com/file*.zip"
            Accessible.name: qsTr("Address pattern")
            enabled: !root.busy
            onTextChanged: root.preview = null
        }
        Label {
            text: qsTr("Use one asterisk for the number or letter to substitute.")
            color: root.colors.muted
        }
        GridLayout {
            columns: 4
            Layout.fillWidth: true
            enabled: !root.busy
            Label { text: qsTr("Range"); color: root.colors.ink }
            Label { text: qsTr("From"); color: root.colors.ink }
            Label { text: qsTr("To"); color: root.colors.ink }
            Label { text: qsTr("Number width"); color: root.colors.ink }
            GlassComboBox {
                id: ranges
                model: [qsTr("Numbers"), qsTr("Letters")]
                Accessible.name: qsTr("Range")
                onActivated: {
                    first.text = currentIndex ? "a" : "1"
                    last.text = currentIndex ? "z" : "10"
                    root.preview = null
                }
            }
            TextField { id: first; text: "1"; Layout.preferredWidth: 72; Accessible.name: qsTr("From"); onTextChanged: root.preview = null }
            TextField { id: last; text: "10"; Layout.preferredWidth: 72; Accessible.name: qsTr("To"); onTextChanged: root.preview = null }
            SpinBox { id: digits; from: 1; to: 10; value: 1; enabled: ranges.currentIndex === 0; Accessible.name: qsTr("Number width"); onValueModified: root.preview = null }
        }
        RowLayout {
            Layout.fillWidth: true
            TextField { id: username; Layout.fillWidth: true; placeholderText: qsTr("Username (optional)"); Accessible.name: placeholderText }
            TextField { id: password; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: qsTr("Password"); Accessible.name: placeholderText }
        }
        Label {
            Layout.fillWidth: true
            visible: root.preview !== null
            text: root.preview ? qsTr("%1 URLs").arg(root.preview.count) + "\n" + (root.preview.preview || []).join("\n") : ""
            textFormat: Text.PlainText
            color: root.colors.muted
            elide: Text.ElideRight
        }
        Label {
            Layout.fillWidth: true
            visible: root.failure !== ""
            text: root.failure
            textFormat: Text.PlainText
            color: root.colors.destructive
            wrapMode: Text.WordWrap
        }
        RowLayout {
            Layout.fillWidth: true
            GlassButton { text: qsTr("Cancel"); enabled: !root.busy; onClicked: root.close() }
            Item { Layout.fillWidth: true }
            GlassButton { text: qsTr("Preview URLs"); enabled: !root.busy && address.text.trim().includes("*"); onClicked: root.run(false) }
            GlassButton { text: qsTr("Add to queue"); accent: root.colors.positive; enabled: !root.busy && root.preview !== null; onClicked: root.run(true) }
        }
    }
}
