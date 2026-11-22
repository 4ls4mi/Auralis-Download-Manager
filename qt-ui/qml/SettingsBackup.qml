pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

ColumnLayout {
    id: root

    required property var backdrop
    property bool busy: false
    property bool restoredArchive: false
    property string status: ""
    property string problem: ""
    property string restoredTo: ""
    property var archiveId: null
    property url sourceArchive
    property var startup: ({enabled: false, mode: "minimized"})
    readonly property var colors: MaterialTheme.palette

    signal settingsRestored()

    function resetReport(message) {
        busy = true
        status = message
        problem = ""
        restoredTo = ""
    }

    function fail(message) {
        archiveId = null
        busy = false
        status = ""
        problem = message
    }

    function fetchStartup(continuation) {
        engine.request({local: "startupSettings"}, function(result, error) {
            if (error || !result) {
                fail(error || qsTr("Could not read Windows startup settings."))
                return
            }
            startup = result
            if (continuation) continuation(result)
        })
    }

    function setStartup(enabled, mode, done) {
        engine.request({local: "setStartupSettings", enabled: enabled, mode: mode}, function(result, error) {
            if (result) startup = result
            done(error || (result ? "" : qsTr("Could not update Windows startup settings.")))
        })
    }

    function saveStartup(enabled, mode) {
        if (busy) return
        resetReport(qsTr("Saving Windows startup settings…"))
        setStartup(enabled, mode, function(error) {
            if (error) { fail(error); return }
            status = qsTr("Windows startup settings saved.")
            busy = false
        })
    }

    function exportPreferences(file) {
        resetReport(qsTr("Exporting preferences…"))
        fetchStartup(function(startupOptions) {
            engine.request({query: "glass-backup-settings"}, function(result, error) {
                if (error || !result || !result.settings) {
                    fail(error || qsTr("Could not export the download preferences."))
                    return
                }
                const data = {format: "auralis-preferences", version: 1, appearance: WindowAppearance.snapshot(),
                    settings: result.settings, startup: startupOptions}
                engine.request({local: "writeShareFile", file: file, data: data}, function(reply, saveError) {
                    if (saveError || !reply) { fail(saveError || qsTr("Could not write preferences.")); return }
                    status = qsTr("Preferences exported to %1").arg(reply.path)
                    busy = false
                })
            })
        })
    }

    function validPreferences(data) {
        const object = value => Boolean(value && typeof value === "object" && !Array.isArray(value))
        return object(data) && data.format === "auralis-preferences" && data.version === 1 &&
            object(data.settings) && object(data.appearance) &&
            Object.values(data.appearance).every(value => typeof value === "string") &&
            object(data.startup) && typeof data.startup.enabled === "boolean" && ["window", "minimized"].includes(data.startup.mode)
    }

    function importPreferences(file) {
        resetReport(qsTr("Restoring preferences…"))
        engine.request({local: "readShareFile", file: file}, function(data, readError) {
            if (readError || !validPreferences(data)) {
                fail(readError || qsTr("Choose a valid Auralis preferences file."))
                return
            }
            engine.request({action: "glass-restore-settings", queue: JSON.stringify(data.settings)}, function(reply, error) {
                if (error || !reply || !reply.ok) { fail(error || qsTr("Could not restore the download preferences.")); return }
                WindowAppearance.applyBackup(data.appearance, true)
                settingsRestored()
                const finish = warning => { status = qsTr("Preferences restored."); problem = warning; busy = false }
                if (Qt.platform.os === "windows") setStartup(data.startup.enabled, data.startup.mode, finish)
                else finish("")
            })
        })
    }

    function exportArchive(file) {
        resetReport(qsTr("Preparing download backup…"))
        restoredArchive = false
        fetchStartup(function(startupOptions) {
            engine.request({local: "prepareFullBackup", appearance: WindowAppearance.snapshot(), startup: startupOptions},
                function(manifest, error) {
                    if (error || !manifest) { fail(error || qsTr("Could not prepare the backup.")); return }
                    engine.request({action: "glass-export-full-backup", dir: engine.localPath(file), queue: manifest.path},
                        function(result, startError) {
                            engine.request({local: "discardBackupManifest", file: manifest.path})
                            beginArchive(result, startError, qsTr("Writing the download backup…"))
                        })
                })
        })
    }

    function importArchive(folder) {
        resetReport(qsTr("Preparing download restore…"))
        restoredArchive = true
        engine.request({local: "chooseRestoreTarget", file: folder}, function(target, error) {
            if (error || !target) { fail(error || qsTr("Could not choose a restore destination.")); return }
            engine.request({action: "glass-import-full-backup", dir: engine.localPath(sourceArchive), queue: target.path},
                function(result, startError) { beginArchive(result, startError, qsTr("Restoring the download archive…")) })
        })
    }

    function beginArchive(result, error, message) {
        if (error || !result || !result.id) { fail(error || qsTr("Could not start the archive operation.")); return }
        status = message
        archiveId = result.id
        archivePoll.restart()
    }

    function pollArchive() {
        if (!archiveId) return
        if (!engine.ready) { archivePoll.restart(); return }
        engine.request({query: "glass-full-backup-status", ids: [archiveId]}, function(result, error) {
            if (error || !result) { fail(error || qsTr("Could not read the archive status.")); return }
            if (result.pending) { archivePoll.restart(); return }
            archiveId = null
            if (!restoredArchive) {
                status = qsTr("Download backup saved to %1").arg(result.path)
                busy = false
                return
            }
            if (result.ui) WindowAppearance.applyBackup(result.ui, Boolean(result.ui_complete))
            restoredTo = result.restored_to || ""
            status = qsTr("Restored %1 downloads to %2").arg(result.downloads || 0).arg(restoredTo)
            settingsRestored()
            engine.refresh()
            const finish = warning => { problem = warning || result.warning || ""; busy = false }
            if (result.startup && Qt.platform.os === "windows")
                setStartup(result.startup.enabled, result.startup.mode, finish)
            else finish("")
        })
    }

    Component.onCompleted: if (Qt.platform.os === "windows") fetchStartup()

    component Card: Frame {
        Layout.fillWidth: true
        padding: 14
        background: GlassSurface { role: "content"; backdropAvailable: root.backdrop.backdropAvailable }
    }

    component Heading: Label {
        Layout.fillWidth: true
        color: root.colors.text
        font.pixelSize: 17
        font.weight: Font.DemiBold
        wrapMode: Text.WordWrap
    }

    component Copy: Label {
        Layout.fillWidth: true
        color: root.colors.muted
        wrapMode: Text.WordWrap
    }

    Card {
        visible: Qt.platform.os === "windows"
        ColumnLayout {
            width: parent.width
            Heading { text: qsTr("Windows startup") }

            Switch {
                text: qsTr("Start Auralis when I sign in")
                enabled: !root.busy
                checked: root.startup.enabled
                onToggled: root.saveStartup(checked, root.startup.mode)
            }

            GlassComboBox {
                Layout.fillWidth: true
                enabled: !root.busy && root.startup.enabled
                textRole: "label"
                valueRole: "value"
                model: [{label: qsTr("Start minimized"), value: "minimized"}, {label: qsTr("Show the main window"), value: "window"}]
                currentIndex: indexOfValue(root.startup.mode)
                onActivated: root.saveStartup(root.startup.enabled, currentValue)
                Accessible.name: qsTr("Startup window behavior")
            }
        }
    }

    Card {
        ColumnLayout {
            width: parent.width
            Heading { text: qsTr("Preferences backup") }
            Copy { text: qsTr("Save appearance, startup, and downloader settings. Saved passwords and service credentials stay on this PC.") }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                GlassButton { text: qsTr("Export preferences…"); enabled: !root.busy && engine.ready; onClicked: prefsSave.open() }
                GlassButton { text: qsTr("Restore preferences…"); enabled: !root.busy && engine.ready; onClicked: prefsOpen.open() }
            }
        }
    }

    Card {
        ColumnLayout {
            width: parent.width
            Heading { text: qsTr("Downloads backup") }
            Copy { text: qsTr("Includes history and supported downloaded and saved partial files. Stop downloads and queues before starting. Restored files go into a new folder.") }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                GlassButton { text: qsTr("Create download backup…"); enabled: !root.busy && engine.ready; onClicked: archiveSave.open() }
                GlassButton { text: qsTr("Restore download backup…"); enabled: !root.busy && engine.ready; onClicked: archiveOpen.open() }
                GlassButton {
                    visible: Boolean(root.restoredTo)
                    text: qsTr("Open restored folder")
                    onClicked: if (!engine.openFolder(root.restoredTo)) root.problem = qsTr("Could not open the restored folder.")
                }
            }
        }
    }

    BusyIndicator { visible: root.busy; running: visible; Layout.preferredHeight: 24; Layout.preferredWidth: 24 }

    Label {
        Layout.fillWidth: true
        visible: Boolean(root.status)
        text: root.status
        color: root.colors.text
        wrapMode: Text.WrapAnywhere
        Accessible.ignored: !visible
    }

    Label {
        Layout.fillWidth: true
        visible: Boolean(root.problem)
        text: root.problem
        color: root.colors.destructive
        wrapMode: Text.WordWrap
        Accessible.ignored: !visible
    }

    Timer { id: archivePoll; interval: 600; onTriggered: root.pollArchive() }

    FileDialog {
        id: prefsSave
        title: qsTr("Export preferences")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "json"
        nameFilters: [qsTr("Auralis preferences (*.json)")]
        onAccepted: root.exportPreferences(selectedFile)
    }
    FileDialog {
        id: prefsOpen
        title: qsTr("Select preferences to restore")
        nameFilters: [qsTr("Auralis preferences (*.json)")]
        onAccepted: root.importPreferences(selectedFile)
    }
    FileDialog {
        id: archiveSave
        title: qsTr("Create a download backup")
        fileMode: FileDialog.SaveFile
        defaultSuffix: "auralis-backup"
        nameFilters: [qsTr("Auralis backup (*.auralis-backup)")]
        onAccepted: root.exportArchive(selectedFile)
    }
    FileDialog {
        id: archiveOpen
        title: qsTr("Select a download backup")
        nameFilters: [qsTr("Auralis backup (*.auralis-backup)")]
        onAccepted: { root.sourceArchive = selectedFile; restoreFolder.open() }
    }
    FolderDialog {
        id: restoreFolder
        title: qsTr("Choose where to put the restored downloads")
        onAccepted: root.importArchive(selectedFolder)
    }
}
