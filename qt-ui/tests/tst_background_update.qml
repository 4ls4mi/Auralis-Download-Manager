pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import "../qml" as App

TestCase {
    id: test
    name: "BackgroundUpdate"
    readonly property var available: ({state: "available", version: "9.8.7", size: 1024})
    property var installRequest
    property var completeDownload

    QtObject {
        id: testBackend
        readonly property bool trayAvailable: true
        readonly property bool storeEdition: false
        readonly property string version: "0.1.0"

        function request(command, callback) {
            switch (command.shellAction) {
            case "update-check":
                callback(test.available, null)
                break
            case "update-download":
                test.compare(command.expectedVersion, test.available.version)
                test.completeDownload = callback
                break
            case "update-install":
                test.installRequest = command
                callback({ok: true}, null)
                break
            case "update-progress":
                callback(null, null)
                break
            default:
                test.fail("Unexpected update request: " + command.shellAction)
            }
        }
    }

    Component {
        id: fixture
        App.UpdateWindow { backend: testBackend }
    }

    function init() {
        installRequest = null
        completeDownload = null
    }

    function test_requiresOptInAndWaitsUntilIdle() {
        const window = createTemporaryObject(fixture, test)
        verify(window)
        window.startBackgroundUpdate(available)
        compare(completeDownload, null)
        window.backgroundInstallEnabled = true
        window.startBackgroundUpdate(available)
        compare(window.stage, "downloading")
        compare(window.visible, false)
        completeDownload({ok: true, size: available.size}, null)
        compare(window.stage, "waiting")
        compare(installRequest, null)
        window.backgroundInstallReady = true
        tryCompare(window, "stage", "closing", 4000)
        compare(installRequest.expectedVersion, available.version)
        compare(installRequest.background, true)
        compare(window.visible, false)
    }

    function test_optOutCancelsUnattendedInstall_data() {
        return [{tag: "during download", downloaded: false}, {tag: "while waiting", downloaded: true}]
    }

    function test_optOutCancelsUnattendedInstall(data) {
        const window = createTemporaryObject(fixture, test, {backgroundInstallEnabled: true})
        verify(window)
        window.startBackgroundUpdate(available)
        if (data.downloaded)
            completeDownload({ok: true, size: available.size}, null)
        window.backgroundInstallEnabled = false
        if (!data.downloaded)
            completeDownload({ok: true, size: available.size}, null)
        window.backgroundInstallReady = true
        compare(window.stage, "available")
        compare(window.backgroundRun, false)
        compare(installRequest, null)
        compare(window.visible, false)
    }

    function test_manualInstallRemainsExplicit() {
        const window = createTemporaryObject(fixture, test, {backgroundInstallEnabled: true, release: available})
        verify(window)
        window.downloadAndInstall()
        compare(window.stage, "downloading")
        completeDownload({ok: true, size: available.size}, null)
        compare(window.stage, "closing")
        compare(installRequest.expectedVersion, available.version)
        compare(installRequest.background, false)
    }
}
