pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property var fontSettings
    readonly property var colors: MaterialTheme.palette
    readonly property var englishCurated: ["Talina", "Milkyway", "Mochi Boom", "Qilka", "Qurova"]
    readonly property var arabicCurated: ["Kidzhood Arabic", "Tinta Arabic", "Madani Arabic",
        "Mahameru Arabic", "Gumela Arabic", "Tufuli Arabic", "Lutfey Arabic"]

    spacing: 13

    function familyKey(name) {
        return name.toLowerCase().replace(/[^a-z0-9]/g, "")
    }

    function familyChoices(curated, installed) {
        const detected = new Map()
        for (const family of installed) {
            const key = familyKey(family)
            if (key && !detected.has(key))
                detected.set(key, family)
        }

        const options = [{label: qsTr("System default"), value: ""}]
        const missing = []
        const included = new Set()
        for (const name of curated) {
            const key = familyKey(name)
            const family = detected.get(key)
            if (family) {
                options.push({label: name, value: family})
                included.add(key)
            } else {
                missing.push(name)
            }
        }
        for (const family of installed) {
            if (family && !included.has(familyKey(family)))
                options.push({label: family, value: family})
        }
        return {options: options, missing: missing}
    }

    function previewFont(text, size, weight) {
        const fallback = fontSettings.interfaceFont
        const selected = fontSettings.fontForText(text)
        return Qt.font({family: selected.family || fallback.family, pixelSize: size, weight: weight})
    }

    component ScriptFonts: ColumnLayout {
        id: script

        required property string caption
        required property string family
        required property var installed
        required property var curated
        required property string sampleTitle
        required property string sampleDetail
        property bool rightToLeft: false
        readonly property var choices: root.familyChoices(curated, installed)
        readonly property int selectedIndex: Math.max(0, choices.options.findIndex(option => option.value === family))
        property bool selectionFailed: false
        signal familyRequested(string value)

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.alignment: Qt.AlignTop
        spacing: 6

        Label {
            Layout.fillWidth: true
            text: script.caption
            color: root.colors.text
            font.weight: Font.DemiBold
            wrapMode: Text.WordWrap
        }

        GlassComboBox {
            Layout.fillWidth: true
            model: script.choices.options
            textRole: "label"
            valueRole: "value"
            currentIndex: script.selectedIndex
            Accessible.name: script.caption
            onActivated: {
                script.familyRequested(currentValue)
                if (script.selectionFailed)
                    currentIndex = Qt.binding(() => script.selectedIndex)
            }
        }

        Frame {
            Layout.fillWidth: true
            padding: 10
            background: GlassSurface { role: "field" }

            contentItem: ColumnLayout {
                spacing: 3
                Label {
                    Layout.fillWidth: true
                    text: script.sampleTitle
                    textFormat: Text.PlainText
                    font: root.previewFont(text, 17, Font.DemiBold)
                    color: root.colors.text
                    horizontalAlignment: script.rightToLeft ? Text.AlignRight : Text.AlignLeft
                    wrapMode: Text.WordWrap
                }
                Label {
                    Layout.fillWidth: true
                    text: script.sampleDetail
                    textFormat: Text.PlainText
                    font: root.previewFont(text, 13, Font.Normal)
                    color: root.colors.muted
                    horizontalAlignment: script.rightToLeft ? Text.AlignRight : Text.AlignLeft
                    wrapMode: Text.Wrap
                }
            }
        }

        Label {
            Layout.fillWidth: true
            visible: script.choices.missing.length > 0
            text: qsTr("Available after installation (%1).").arg(script.choices.missing.join(", "))
            textFormat: Text.PlainText
            color: root.colors.muted
            wrapMode: Text.Wrap
        }

        Label {
            Layout.fillWidth: true
            visible: script.selectionFailed
            text: qsTr("This font is no longer available.")
            color: root.colors.destructive
            wrapMode: Text.WordWrap
        }
    }

    Label {
        Layout.fillWidth: true
        text: qsTr("Install licensed font copies on this device, then reopen Auralis to use them here.")
        color: root.colors.muted
        wrapMode: Text.WordWrap
    }

    GridLayout {
        Layout.fillWidth: true
        columns: width >= 540 ? 2 : 1
        columnSpacing: 14
        rowSpacing: 13

        ScriptFonts {
            id: english
            caption: qsTr("English interface font")
            family: root.fontSettings.englishFamily
            installed: root.fontSettings.englishFonts
            curated: root.englishCurated
            sampleTitle: "Download queue"
            sampleDetail: "Archive.zip · 42 MB of 108 MB"
            onFamilyRequested: value => english.selectionFailed = !root.fontSettings.setEnglishFamily(value)
        }

        ScriptFonts {
            id: arabic
            caption: qsTr("Arabic interface font")
            family: root.fontSettings.arabicFamily
            installed: root.fontSettings.arabicFonts
            curated: root.arabicCurated
            rightToLeft: true
            sampleTitle: "قائمة التنزيلات"
            sampleDetail: "جارٍ التنزيل · ٤٢ من ١٠٨ ميغابايت"
            onFamilyRequested: value => arabic.selectionFailed = !root.fontSettings.setArabicFamily(value)
        }
    }
}
