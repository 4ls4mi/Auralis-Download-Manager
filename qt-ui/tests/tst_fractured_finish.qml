import QtQuick
import QtTest
import "../qml" as App

TestCase {
    id: test
    name: "FracturedPanelFinish"
    width: 850
    height: 650
    visible: true
    when: windowShown

    property var startingAppearance

    Component {
        id: appearancePage
        App.SettingsAppearance {
            width: 750
            backdrop: ({backdropAvailable: false})
        }
    }

    function init() {
        startingAppearance = App.WindowAppearance.snapshot()
    }

    function cleanup() {
        App.WindowAppearance.applyBackup(startingAppearance, true)
    }

    function test_picker_appears_only_for_fractured_acrylic() {
        App.MaterialTheme.current = "black-ceramic"
        const page = createTemporaryObject(appearancePage, test)
        const picker = findChild(page, "fracturedPanelFinish")
        verify(picker)
        verify(!picker.visible)
        App.MaterialTheme.current = "fractured-pearl"
        tryVerify(() => picker.visible)
        compare(picker.model.map(choice => choice.value).join(","),
                "acrylic,mica,tinted,blurred,translucent,frosted")
        picker.chosen("mica")
        compare(App.MaterialTheme.current, "fractured-pearl")
        compare(App.MaterialTheme.fracturedFinish, "mica")
    }

    function test_old_settings_default_without_changing_other_preferences() {
        App.WindowAppearance.applyBackup({
            "mh-glass-material": "fractured-pearl",
            "mh-glass-glass-translucency": "56",
            "mh-glass-qt-appearance": JSON.stringify({cornerRadius: 22})
        }, true)
        compare(App.MaterialTheme.current, "fractured-pearl")
        compare(App.MaterialTheme.fracturedFinish, "frosted")
        compare(App.MaterialTheme.translucency, .56)
        compare(App.WindowAppearance.cornerRadius, 22)
    }

    function test_saved_preferences_and_appearance_backup() {
        App.MaterialTheme.current = "fractured-pearl"
        App.MaterialTheme.tintColor = "#864288"
        App.MaterialTheme.translucency = .53
        App.MaterialTheme.fracturedFinish = "tinted"
        App.MaterialTheme.current = "black-ceramic"
        compare(App.MaterialTheme.fracturedFinish, "tinted")
        const snapshot = App.WindowAppearance.snapshot()
        compare(JSON.parse(snapshot["mh-glass-qt-appearance"]).fracturedFinish, "tinted")
        const stored = JSON.parse(App.WindowAppearance.persistence.saved)
        compare(JSON.parse(stored["mh-glass-qt-appearance"]).fracturedFinish, "tinted")
        App.MaterialTheme.fracturedFinish = "blurred"
        App.WindowAppearance.applyBackup(snapshot, true)
        compare(App.MaterialTheme.current, "black-ceramic")
        compare(App.MaterialTheme.fracturedFinish, "tinted")
        compare(App.MaterialTheme.translucency, .53)
        compare(App.MaterialTheme.tintColor.toString(), "#864288")
    }

    function test_theme_import_and_legacy_theme() {
        App.MaterialTheme.current = "fractured-pearl"
        App.MaterialTheme.fracturedFinish = "translucent"
        const theme = App.WindowAppearance.exportTheme()
        compare(theme.qt.fracturedFinish, "translucent")
        App.MaterialTheme.fracturedFinish = "blurred"
        verify(App.WindowAppearance.importTheme(theme))
        compare(App.MaterialTheme.current, "fractured-pearl")
        compare(App.MaterialTheme.fracturedFinish, "translucent")

        delete theme.qt.fracturedFinish
        App.MaterialTheme.fracturedFinish = "mica"
        verify(App.WindowAppearance.importTheme(theme))
        compare(App.MaterialTheme.fracturedFinish, "mica")
        theme.qt.fracturedFinish = "invalid"
        verify(App.WindowAppearance.importTheme(theme))
        compare(App.MaterialTheme.fracturedFinish, "mica")

        App.MaterialTheme.current = "black-ceramic"
        const other = App.WindowAppearance.exportTheme()
        compare(other.qt.fracturedFinish, undefined)
        other.qt.fracturedFinish = "acrylic"
        verify(App.WindowAppearance.importTheme(other))
        compare(App.MaterialTheme.fracturedFinish, "mica")
    }
}
