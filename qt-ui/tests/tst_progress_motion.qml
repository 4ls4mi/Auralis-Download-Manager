import QtQuick
import QtTest
import "../qml" as App
import "../qml/ProgressStyles.js" as Styles

TestCase {
    id: test
    name: "ProgressMotionTransparency"
    width: 400
    height: 50
    visible: true
    when: windowShown
    Rectangle { id: backdrop; anchors.fill: parent; color: "#1f4a61" }
    Component { id: renderer; App.ProgressMotion { width: 360; height: 32 } }
    function test_transparency_data() {
        const rows=[]
        for (const layout of ["status-track","pill-segments","thin-line"])
            for (const motion of Styles.choices(layout).filter(option=>option.value!=="none"))
                rows.push({tag:motion.value,style:motion.value,layout:layout})
        return rows
    }
    function test_transparency(data) {
        backdrop.color = "#1f4a61"
        const item = createTemporaryObject(renderer, test, {amount:.42, animationStyle:data.style, layoutStyle:data.layout, phase:1.2,
            fillMask:"M 0 0 H 151 V 32 H 0 Z"})
        verify(item !== null)
        tryCompare(item, "available", true)
        item.requestPaint()
        wait(50)
        waitForRendering(item, 250)
        let frame = grabImage(test)
        // Neither the unused track nor the completed fill gets an opaque backdrop.
        compare(frame.pixel(300,16), backdrop.color)
        const firstFill = frame.pixel(30,16)
        backdrop.color = "#e2b86d"
        waitForRendering(backdrop, 250)
        frame = grabImage(test)
        compare(frame.pixel(300,16), backdrop.color)
        verify(frame.pixel(30,16) !== firstFill)
        item.amount = 0
        item.requestPaint()
        wait(50)
        waitForRendering(item, 250)
        frame = grabImage(test)
        compare(frame.pixel(30,16), backdrop.color)
    }
}
