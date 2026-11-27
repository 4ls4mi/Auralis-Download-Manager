import QtQuick
import QtTest
import "../qml" as App
import "../qml/ProgressStyles.js" as Styles

TestCase {
    id: test
    name: "ArtisticProgressRendering"
    width: 400
    height: 70
    visible: true
    when: windowShown
    Rectangle { id: backdrop; anchors.fill: parent; color: "#203a51" }
    Component { id: renderer; App.ArtisticProgress { width: 360; amount: .42; phase: 1.25 } }
    Component { id: host; App.GlassProgress { width: 360; height: 32; value: .42 } }
    function test_artwork_data() {
        const rows=[]
        for (const layout of Styles.layouts().filter(option=>Styles.artistic(option.value)))
            for (const motion of Styles.choices(layout.value))
                for (const height of [14,32])
                    for (const shape of ["round","square","prism"])
                        rows.push({tag:motion.value+"-"+layout.value+"-"+height+"-"+shape,
                            layout:layout.value,motion:motion.value,height:height,shape:shape})
        return rows
    }
    function test_artwork(data) {
        const item=createTemporaryObject(renderer,test,{height:data.height,layoutStyle:data.layout,
            animationStyle:data.motion,shape:data.shape})
        verify(item!==null)
        tryCompare(item,"available",true)
        item.requestPaint()
        wait(35)
        waitForRendering(item,250)
        let frame=grabImage(test)
        compare(frame.pixel(300,Math.floor(data.height/2)),backdrop.color)
        let painted=0
        for(let x=4;x<148;x+=8)for(let y=1;y<data.height;y+=3)
            if(frame.pixel(x,y)!==backdrop.color)painted++
        verify(painted>0,"The layout must paint visible artwork")
        item.amount=0
        item.requestPaint()
        wait(35)
        waitForRendering(item,250)
        frame=grabImage(test)
        for(let x=4;x<360;x+=28)
            compare(frame.pixel(x,Math.floor(data.height/2)),backdrop.color)
    }
    function test_host_and_animation_memory() {
        const saved=App.WindowAppearance.preferences
        try {
            App.WindowAppearance.set("customProgressFill",true)
            for(const layout of Styles.layouts()) {
                App.WindowAppearance.set("progressLayout",layout.value)
                const motion=Styles.choices(layout.value)[2].value
                App.WindowAppearance.set("progressAnimation",motion)
                const item=createTemporaryObject(host,test,{layoutStyle:layout.value,animationStyle:motion})
                verify(item!==null)
                compare(item.selectedAnimation,motion)
                compare(item.artisticLayout,Styles.artistic(layout.value))
                wait(35)
                item.destroy()
            }
            for(const layout of Styles.layouts()) {
                App.WindowAppearance.set("progressLayout",layout.value)
                compare(App.WindowAppearance.progressAnimation,Styles.choices(layout.value)[2].value)
                compare(App.WindowAppearance.progressAnimationChoices.length,4)
            }
            const snapshot=App.WindowAppearance.snapshot()
            compare(JSON.parse(snapshot["mh-glass-qt-appearance"]).progressAnimations["elastic-gel"],"gel-spring")
            App.WindowAppearance.applyBackup(snapshot,true)
            App.WindowAppearance.set("progressLayout","elastic-gel")
            compare(App.WindowAppearance.progressAnimation,"gel-spring")
            App.WindowAppearance.set("progressLayout","liquid-silk")
            App.WindowAppearance.set("progressAnimation","gel-spring")
            verify(Styles.choices("liquid-silk").some(choice=>choice.value===App.WindowAppearance.progressAnimation))
        } finally { App.WindowAppearance.preferences=saved }
    }
    function test_animation_frames_data() {
        const rows=[]
        for(const layout of Styles.layouts().filter(option=>Styles.artistic(option.value)))
            for(const motion of Styles.choices(layout.value).filter(option=>option.value!=="none"))
                rows.push({tag:motion.value,layout:layout.value,motion:motion.value})
        return rows
    }
    function test_animation_frames(data) {
        const item=createTemporaryObject(renderer,test,{height:32,amount:.72,layoutStyle:data.layout,
            animationStyle:data.motion,moving:true})
        verify(item!==null)
        tryCompare(item,"available",true)
        wait(70)
        waitForRendering(item,250)
        const first=grabImage(test)
        wait(230)
        waitForRendering(item,250)
        const second=grabImage(test)
        let changed=false
        for(let x=3;x<255&&!changed;x+=4)
            for(let y=2;y<31;y+=3)if(first.pixel(x,y)!==second.pixel(x,y)){changed=true;break}
        verify(changed,"The selected effect must move, rather than just change its name")
        compare(second.pixel(300,16),backdrop.color)
        item.moving=false
    }
}
