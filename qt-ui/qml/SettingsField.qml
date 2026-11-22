pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property var field
    property bool busy: false
    property var cells: []
    property var regional: ({})
    property bool expanded: false
    readonly property var colors: MaterialTheme.palette
    readonly property string kind: field.kind || "text"
    readonly property bool complex: kind === "table" || kind === "lines" || kind === "regional"
    readonly property bool unavailable: field.key === "cnl_on" || field.key === "cnl_sites"
    readonly property var choices: (field.options || []).map((choice, index) =>
        typeof choice === "string" ? ({label: choice, value: index}) : choice)
    signal commit(var value, var options)

    enabled: !busy
    spacing: 8

    function loadDraft() {
        if (kind === "table") cells = (field.value || []).map(row => Array.from(row))
        else if (kind === "regional") regional = Object.assign({}, field.value)
    }

    function defaultCell(column) {
        if (column.options && column.options.length) return column.options[0].value
        if (column.kind === "boolean") return false
        if (column.kind === "number") return 1
        return ""
    }

    function saveLine(value) {
        if (kind === "number") {
            if (!String(value).trim()) return
            const number = Number(value)
            if (Number.isInteger(number) && number >= (field.minimum ?? 0) && number <= (field.maximum ?? 2147483647) &&
                number !== field.value) commit(number, {})
        } else if (kind === "password" ? Boolean(value) : value !== String(field.value ?? "")) {
            commit(value, {})
        }
    }

    Component.onCompleted: loadDraft()
    onFieldChanged: loadDraft()

    component FieldBox: TextField {
        color: root.colors.text
        placeholderTextColor: root.colors.muted
        selectByMouse: true
        background: GlassSurface { role: "field" }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Label {
                Layout.fillWidth: true
                text: root.field.label
                color: root.colors.text
                wrapMode: Text.WordWrap
                font.weight: Font.DemiBold
            }

            Label {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.unavailable ? qsTr("Click’n’Load is unavailable. Existing settings are preserved.") : (root.field.description || "")
                color: root.colors.muted
                wrapMode: Text.WordWrap
                font.pixelSize: 12
            }
        }

        Loader {
            Layout.preferredWidth: root.kind === "boolean" ? 56 : Math.min(root.width * 0.48, 300)
            Layout.minimumWidth: root.kind === "boolean" ? 48 : 125
            active: !root.unavailable
            sourceComponent: root.complex ? expandButton : root.kind === "boolean" ? boolControl
                : root.kind === "select" ? selectControl : root.field.key === "video_cookies_file" ? cookieControl : inputControl
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: root.colors.divider
    }

    Component {
        id: boolControl
        Switch {
            checked: Boolean(root.field.value)
            Accessible.name: root.field.label
            onToggled: root.commit(checked, {})
        }
    }

    Component {
        id: selectControl
        ComboBox {
            model: root.choices
            textRole: "label"
            valueRole: "value"
            currentIndex: root.choices.findIndex(choice => choice.value === root.field.value)
            Accessible.name: root.field.label
            palette.text: root.colors.text
            palette.buttonText: root.colors.text
            palette.base: root.colors.background
            onActivated: root.commit(currentValue, {})
        }
    }

    Component {
        id: inputControl
        RowLayout {
            spacing: 6
            FieldBox {
                id: editable
                Layout.fillWidth: true
                text: String(root.field.value ?? "")
                Accessible.name: root.field.label
                echoMode: root.kind === "password" ? TextInput.Password : TextInput.Normal
                placeholderText: root.kind === "password" && root.field.saved ? qsTr("Saved password") : ""
                inputMethodHints: root.kind === "number" ? Qt.ImhDigitsOnly : Qt.ImhNone
                validator: root.kind === "number" ? numericValidator : null
                onEditingFinished: root.saveLine(text)

                IntValidator {
                    id: numericValidator
                    bottom: root.field.minimum ?? 0
                    top: root.field.maximum ?? 2147483647
                }
            }

            GlassButton {
                visible: root.kind === "password" && Boolean(root.field.saved)
                text: qsTr("Clear")
                Accessible.name: qsTr("Clear saved password")
                onClicked: root.commit("", {clear: true})
            }
        }
    }

    Component {
        id: cookieControl
        RowLayout {
            Label {
                Layout.fillWidth: true
                text: root.field.value || qsTr("No file selected")
                color: root.colors.muted
                elide: Text.ElideMiddle
                ToolTip.visible: cookieHover.hovered && Boolean(root.field.value)
                ToolTip.text: root.field.value ? String(root.field.value) : ""
                HoverHandler { id: cookieHover }
            }
            GlassButton { text: qsTr("Choose…"); onClicked: cookies.open() }
            GlassButton {
                visible: Boolean(root.field.value)
                text: qsTr("Clear")
                onClicked: root.commit("", {})
            }
            FileDialog {
                id: cookies
                title: qsTr("Choose a Netscape cookies file")
                nameFilters: [qsTr("Text files (*.txt)")]
                onAccepted: root.commit(engine.localPath(selectedFile), {})
            }
        }
    }

    Component {
        id: expandButton
        GlassButton {
            text: root.expanded ? qsTr("Close editor") : qsTr("Edit…")
            checkable: true
            checked: root.expanded
            onClicked: root.expanded = !root.expanded
        }
    }

    Loader {
        Layout.fillWidth: true
        active: root.expanded && root.complex && !root.unavailable
        sourceComponent: root.kind === "table" ? tableControl : root.kind === "lines" ? linesControl : regionalControl
    }

    Component {
        id: linesControl
        ColumnLayout {
            TextArea {
                id: lines
                Layout.fillWidth: true
                Layout.preferredHeight: 108
                text: (root.field.value || []).join("\n")
                placeholderText: qsTr("One address per line")
                color: root.colors.text
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                Accessible.name: root.field.label
                background: GlassSurface { role: "field" }
            }

            GlassButton {
                Layout.alignment: Qt.AlignRight
                text: qsTr("Save list")
                enabled: lines.text !== (root.field.value || []).join("\n")
                onClicked: root.commit(lines.text.split(/\r?\n/).map(line => line.trim()).filter(Boolean), {})
            }
        }
    }

    Component {
        id: tableControl
        ColumnLayout {
            id: tableEditor
            readonly property var columns: root.field.columns || []

            Repeater {
                model: root.cells
                delegate: RowLayout {
                    id: tableRow
                    required property int index
                    required property var modelData
                    Layout.fillWidth: true

                    Repeater {
                        model: tableEditor.columns
                        delegate: Loader {
                            id: cell
                            required property int index
                            required property var modelData
                            readonly property int row: tableRow.index
                            readonly property var entry: tableRow.modelData[cell.index]
                            Layout.fillWidth: modelData.kind !== "boolean"
                            Layout.preferredWidth: modelData.kind === "boolean" ? 82 : 150

                            function update(value) {
                                root.cells[row][index] = value
                            }

                            sourceComponent: modelData.kind === "boolean" ? rowCheck : modelData.options ? rowChoice
                                : (root.field.key === "category_dirs" || root.field.key === "sounds") && index === 1
                                    ? rowPath : rowValue

                            Component {
                                id: rowCheck
                                CheckBox {
                                    text: cell.modelData.label
                                    checked: Boolean(cell.entry)
                                    palette.windowText: root.colors.text
                                    onToggled: cell.update(checked)
                                }
                            }

                            Component {
                                id: rowChoice
                                ComboBox {
                                    model: cell.modelData.options
                                    textRole: "label"
                                    valueRole: "value"
                                    currentIndex: model.findIndex(option => option.value === cell.entry)
                                    Accessible.name: cell.modelData.label
                                    onActivated: cell.update(currentValue)
                                }
                            }

                            Component {
                                id: rowPath
                                RowLayout {
                                    FieldBox {
                                        id: location
                                        Layout.fillWidth: true
                                        text: String(cell.entry ?? "")
                                        placeholderText: cell.modelData.label
                                        Accessible.name: cell.modelData.label
                                        onTextEdited: cell.update(text)
                                    }
                                    GlassButton {
                                        text: qsTr("Browse…")
                                        onClicked: root.field.key === "category_dirs" ? chooseFolder.open() : chooseSound.open()
                                    }
                                    FolderDialog {
                                        id: chooseFolder
                                        title: qsTr("Choose a category folder")
                                        onAccepted: {
                                            location.text = engine.localPath(selectedFolder)
                                            cell.update(location.text)
                                        }
                                    }
                                    FileDialog {
                                        id: chooseSound
                                        title: qsTr("Choose a notification sound")
                                        nameFilters: [qsTr("Audio files (*.wav *.mp3 *.ogg)")]
                                        onAccepted: {
                                            location.text = engine.localPath(selectedFile)
                                            cell.update(location.text)
                                        }
                                    }
                                }
                            }

                            Component {
                                id: rowValue
                                FieldBox {
                                    text: String(cell.entry ?? "")
                                    placeholderText: cell.modelData.label
                                    Accessible.name: cell.modelData.label
                                    echoMode: cell.modelData.kind === "password" ? TextInput.Password : TextInput.Normal
                                    inputMethodHints: cell.modelData.kind === "number" ? Qt.ImhDigitsOnly : Qt.ImhNone
                                    validator: cell.modelData.kind === "number" ? cellInteger : null
                                    onTextEdited: {
                                        if (acceptableInput) cell.update(cell.modelData.kind === "number" ? Number(text) : text)
                                    }
                                    IntValidator { id: cellInteger; bottom: 0 }
                                }
                            }
                        }
                    }

                    GlassButton {
                        text: qsTr("Remove")
                        visible: !root.field.fixed
                        onClicked: {
                            const rows = root.cells.slice()
                            rows.splice(tableRow.index, 1)
                            root.cells = rows
                        }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                visible: root.field.key === "site_logins"
                text: qsTr("A blank password keeps the saved password for the same site and username.")
                color: root.colors.muted
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                GlassButton {
                    visible: !root.field.fixed
                    text: qsTr("Add row")
                    onClicked: root.cells = root.cells.concat([columns.map(root.defaultCell)])
                }
                Item { Layout.fillWidth: true }
                GlassButton {
                    text: qsTr("Save table")
                    onClicked: root.commit(root.cells, {})
                }
            }
        }
    }

    Component {
        id: regionalControl
        ColumnLayout {
            CheckBox {
                text: qsTr("Use custom date and time format")
                checked: Boolean(root.regional.custom)
                onToggled: root.regional = Object.assign({}, root.regional, {custom: checked})
            }
            ComboBox {
                Layout.fillWidth: true
                enabled: root.regional.custom
                model: [qsTr("Day / Month / Year"), qsTr("Month / Day / Year"), qsTr("Year / Month / Day")]
                currentIndex: ["dmy", "mdy", "ymd"].indexOf(root.regional.order)
                Accessible.name: qsTr("Date order")
                onActivated: root.regional = Object.assign({}, root.regional, {order: ["dmy", "mdy", "ymd"][index]})
            }
            CheckBox {
                text: qsTr("24-hour clock")
                enabled: root.regional.custom
                checked: Boolean(root.regional.clock24)
                onToggled: root.regional = Object.assign({}, root.regional, {clock24: checked})
            }
            ComboBox {
                Layout.fillWidth: true
                enabled: root.regional.custom
                model: [qsTr("Sunday"), qsTr("Monday"), qsTr("Tuesday"), qsTr("Wednesday"), qsTr("Thursday"), qsTr("Friday"), qsTr("Saturday")]
                currentIndex: root.regional.week_start ?? 0
                Accessible.name: qsTr("First day of the week")
                onActivated: root.regional = Object.assign({}, root.regional, {week_start: index})
            }
            GlassButton {
                Layout.alignment: Qt.AlignRight
                text: qsTr("Save format")
                onClicked: root.commit(root.regional, {})
            }
        }
    }
}
