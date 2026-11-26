import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

ColumnLayout {
    id: root
    property var categories: []
    property bool busy: false
    property string problem: ""
    property string mode: "save"
    readonly property var selected: categories[category.currentIndex] || null
    readonly property var colors: MaterialTheme.palette
    signal saved()
    spacing: 12
    function select(index) {
        mode = "save"
        const item = categories[index]
        if (!item) return
        name.text = item.name
        types.text = item.types || ""
        folder.text = item.folder
        remember.checked = item.remember
    }
    function load() {
        if (!engine.ready || busy) return
        busy = true
        engine.request({query:"glass-category-settings"}, function(result,error) {
            busy = false
            if (error || !result) { problem = error || qsTr("Could not load categories."); return }
            categories = result.categories || []
            category.currentIndex = Math.max(0, Math.min(category.currentIndex, categories.length - 1))
            select(category.currentIndex)
        })
    }
    function commit(operation) {
        if (busy) return
        busy = true
        problem = ""
        const payload = {operation:operation, key:selected?.key || "", name:name.text,
            types:types.text, folder:folder.text, remember:remember.checked}
        engine.request({action:"glass-category-setting",queue:JSON.stringify(payload)},function(result,error) {
            busy = false
            if (error || result?.error) { problem = error || result.error; return }
            categories = result.categories || []
            if (operation === "new") category.currentIndex = categories.length - 1
            select(Math.max(0, category.currentIndex))
            saved()
        })
    }
    onVisibleChanged: if (visible) load()
    Component.onCompleted: if (visible) load()
    Connections { target: engine; function onReadyChanged() { if (root.visible) root.load() } }
    Label { text: qsTr("Categories, file types, and folders"); color: root.colors.text; font.bold: true; wrapMode: Text.WordWrap; Layout.fillWidth: true }
    RowLayout {
        Layout.fillWidth: true
        GlassComboBox {
            id: category
            Layout.fillWidth: true
            model: root.categories
            textRole: "name"
            enabled: !root.busy && root.mode === "save"
            Accessible.name: qsTr("Category")
            onActivated: root.select(currentIndex)
        }
        GlassButton {
            text: qsTr("New")
            enabled: !root.busy
            onClicked: { root.mode = "new"; name.clear(); types.clear(); name.forceActiveFocus() }
        }
        GlassButton { text: qsTr("Edit"); enabled: !root.busy && root.selected?.editable === true; onClicked: root.mode = "edit" }
    }
    TextField {
        id: name
        visible: root.mode !== "save"
        Layout.fillWidth: true
        placeholderText: qsTr("Category name")
        Accessible.name: placeholderText
    }
    Label {
        Layout.fillWidth: true
        color: root.colors.text
        text: String(root.selected?.key || "").toLowerCase() === "general" && root.mode !== "new"
            ? qsTr("General receives file types that do not match another category.")
            : qsTr("File types assigned to this category (separate extensions with spaces)")
        wrapMode: Text.WordWrap
    }
    TextArea {
        id: types
        Layout.fillWidth: true
        Layout.preferredHeight: 80
        readOnly: root.mode === "save" || (root.mode !== "new" && root.selected?.editable !== true)
        wrapMode: TextEdit.Wrap
        placeholderText: qsTr("For example: ZIP 7Z RAR")
        Accessible.name: qsTr("Category file types")
        selectByMouse: true
    }
    Label { text: qsTr("Default download directory"); color: root.colors.text }
    RowLayout {
        Layout.fillWidth: true
        TextField { id: folder; Layout.fillWidth: true; selectByMouse: true; Accessible.name: qsTr("Default download directory") }
        GlassButton { text: qsTr("Browse…"); enabled: !root.busy; onClicked: chooser.open() }
    }
    FolderDialog { id: chooser; title: qsTr("Choose a category folder"); onAccepted: folder.text = engine.localPath(selectedFolder) }
    CheckBox { id: remember; text: qsTr("Use the last selected folder for this category"); palette.windowText: root.colors.text }
    RowLayout {
        GlassButton { text: qsTr("Save category"); enabled: !root.busy && folder.text.trim().length > 0; onClicked: root.commit(root.mode) }
        GlassButton { text: qsTr("Cancel edit"); visible: root.mode !== "save"; onClicked: root.select(category.currentIndex) }
    }
    Label {
        Layout.fillWidth: true
        text: qsTr("Temporary directory: not needed. Downloaded parts are written beside the destination file, so no separate assembling folder is used.")
        color: root.colors.muted
        wrapMode: Text.WordWrap
    }
    GlassButton { text: qsTr("Restore built-in categories"); enabled: !root.busy; onClicked: root.commit("restore") }
    Label { Layout.fillWidth: true; visible: root.problem.length > 0; text: root.problem; color: root.colors.destructive; wrapMode: Text.WordWrap }
}
