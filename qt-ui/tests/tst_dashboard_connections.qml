import QtQuick
import QtTest
import "../qml" as App
import "../qml/TransferData.js" as Transfer

TestCase {
    id: test
    name: "DashboardConnections"
    width: 640
    height: 120
    visible: true
    when: windowShown

    Component {
        id: slotGrid
        App.ConnectionSlotGrid {
            width: 80
            height: 28
            activeCount: 4
            configuredCount: 32
            shape: "square"
            activeInk: "#408a64"
            idleInk: "#e0e0e0"
        }
    }

    function test_configuredAndLiveCountsAreIndependent() {
        compare(Transfer.connectionCounts({chunk_count: 32, active_connections: 32}), {active: 32, configured: 32})
        compare(Transfer.connectionCounts({chunk_count: 32, active_connections: 4}), {active: 4, configured: 32})
        compare(Transfer.connectionCounts({chunk_count: 32, active_connections: 0}), {active: 0, configured: 32})
        const workers = [{state: "Receiving"}, {state: "Connecting"}, {state: "Finished"}]
        compare(Transfer.connectionCounts({chunk_count: 32, connections: workers}), {active: 2, configured: 32})
    }

    function test_gridRendersFirstAndLastSlots() {
        const grid = createTemporaryObject(slotGrid, test)
        verify(grid !== null)
        compare(grid.slotCount, 32)
        tryCompare(grid, "available", true)
        grid.requestPaint()
        tryVerify(() => {
            const frame = grabImage(grid)
            return frame.pixel(5, 3) === grid.activeInk && frame.pixel(75, 24) === grid.idleInk
        })
        grid.configuredCount = 128
        compare(grid.slotCount, 128)
    }
}
