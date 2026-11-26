import QtQuick
import QtTest
import "../qml" as App

TestCase {
    id: test
    name: "CreativeProgressRendering"
    width: 400
    height: 50
    visible: true
    when: windowShown
    Component { id: renderer; App.CreativeProgress { width: 360; height: 32; amount: .42 } }
    function test_layouts_data() {
        const rows=[]
        for (const layout of ["liquid-capsule","jelly-beads","braided-ribbon","prism-segments","molten-glass","orbit-marker","glass-tiles","checkpoints","tidal-ribbon","frosted-cells","filament-core","twin-rails"])
            for (const shape of ["round","square","prism"])
                rows.push({tag:layout+"-"+shape,layout:layout,shape:shape})
        return rows
    }
    function test_layouts(data) {
        const item=createTemporaryObject(renderer,test,{layoutStyle:data.layout,shape:data.shape,animationStyle:"glints",lightingStyle:"chrome",phase:1.2})
        verify(item !== null)
        tryCompare(item,"available",true)
        item.requestPaint()
        wait(40)
        waitForRendering(item,250)
        const frame=grabImage(item)
        compare(frame.width,360)
        verify(frame.pixel(10,16) !== frame.pixel(359,0))
    }
}

