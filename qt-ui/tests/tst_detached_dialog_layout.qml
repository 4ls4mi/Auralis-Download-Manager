import QtQuick
import QtTest
import "../qml" as App

TestCase {
    name: "DetachedDialogLayout"

    Component {
        id: dialogFactory
        App.DetachedDialogWindow {
            id: dialog
            acrylicMode: true
            background: null
            sizePreferenceKey: ""
            property int bodyHeight: 100

            bodyContent: [Item { implicitHeight: dialog.bodyHeight }]
        }
    }

    function test_openDialogKeepsItsHeightWhenBodyChanges() {
        const dialog = createTemporaryObject(dialogFactory, null)
        verify(dialog)
        dialog.open()
        const initialHeight = dialog.height
        dialog.bodyHeight = 320
        tryVerify(() => dialog.preferredHeight > initialHeight)
        wait(50)
        compare(dialog.height, initialHeight)
        dialog.hide()
        dialog.open()
        verify(dialog.height > initialHeight)
        dialog.hide()
    }
}
