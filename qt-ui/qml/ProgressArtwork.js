.pragma library
.import "ProgressStyles.js" as Styles
.import "MaterialGeometry.js" as Geometry

const tau=Math.PI*2
function fract(n) { return n-Math.floor(n) }
function color(value,alpha) {
    const hex=String(value).replace("#","").slice(-6)
    return "rgba("+parseInt(hex.slice(0,2),16)+","+parseInt(hex.slice(2,4),16)+","+parseInt(hex.slice(4,6),16)+","+Math.max(0,Math.min(1,alpha))+")"
}
function rounded(ctx,x,y,w,h,r) { ctx.path=Geometry.frame(x,y,w,h,r,"round") }
function oval(ctx,cx,cy,rx,ry,rotation,start,end) {
    ctx.beginPath()
    for(let i=0;i<=20;i++) {
        const a=start+(end-start)*i/20,px=Math.cos(a)*rx,py=Math.sin(a)*ry
        const x=cx+px*Math.cos(rotation)-py*Math.sin(rotation),y=cy+px*Math.sin(rotation)+py*Math.cos(rotation)
        if(i===0)ctx.moveTo(x,y);else ctx.lineTo(x,y)
    }
    ctx.closePath()
}
function curve(ctx,w,h,t,lane,amp,speed) {
    ctx.beginPath()
    for(let i=0;i<=64;i++) { const x=w*i/64,y=h*(lane+amp*Math.sin(i*.22-t*speed));if(!i)ctx.moveTo(x,y);else ctx.lineTo(x,y) }
}
function draw(ctx,options) {
    const w=options.width,h=options.height,front=w*options.amount
    if(w<=0||h<=0||front<=0)return
    const layout=Styles.layout(options.layout)
    const kind={"liquid-silk":"silk","elastic-gel":"gel","photon-streams":"photons","crystal-shimmer":"crystal","capillary-current":"capillary","vortex-glass":"vortex"}[layout]
    if(!kind)return
    const mode=Styles.modeIndex(layout,options.animation),t=options.animation==="none"?0:options.phase
    const first=options.startColor,last=options.endColor,finish=options.finish||{},energy=finish.reflection===undefined?.7:finish.reflection
    const grad=ctx.createLinearGradient(0,0,w,0);grad.addColorStop(0,first);grad.addColorStop(1,last)
    ctx.save();ctx.path=Geometry.frame(0,0,w,h,h*.48,options.shape);ctx.clip()
    ctx.beginPath();ctx.rect(0,0,front,h);ctx.clip()
    ctx.fillStyle=grad;ctx.strokeStyle=grad;ctx.lineCap="round";ctx.lineJoin="round"
  if(kind==='silk'){
   const amp=mode===1?.17:mode===2?.09:.055,rate=mode===2?.65:1.5;
   ctx.beginPath();for(let i=0;i<=70;i++){const x=w*i/70,y=h*(.14+amp*Math.sin(x/Math.max(20,h*4)-t*rate));if(i===0)ctx.moveTo(x,y);else ctx.lineTo(x,y)}
   for(let i=70;i>=0;i--){const x=w*i/70,y=h*(.86+amp*.5*Math.sin(x/Math.max(20,h*4)-t*rate+1.4));ctx.lineTo(x,y)}ctx.closePath();ctx.globalAlpha=.86;ctx.fill();ctx.globalAlpha=1;
   for(let lane=0;lane<3;lane++){curve(ctx,w,h,t+lane*2,.30+lane*.19,.055,rate);ctx.strokeStyle=color(lane===1?first:'#ffffff',(.19+energy*.22)*(lane===1?.6:1));ctx.lineWidth=Math.max(.65,h*.045);ctx.stroke()}
   for(let i=0;i<9;i++){const x=fract(t*.12+i/9)*w,y=h*(.5+.15*Math.sin(x/55-t));ctx.beginPath();oval(ctx,x,y,h*.09,h*.035,0,0,tau);ctx.fillStyle=color('#ffffff',energy*.4);ctx.fill()}
  }else if(kind==='gel'){
   const step=Math.max(22,h*1.75);
   for(let i=0;i<Math.ceil(w/step);i++){const pulse=Math.sin(t*(mode===1?1.4:3.4)-i*(mode===2?.9:.55)),hh=h*(.68+.15*pulse),yy=(h-hh)/2,ww=step*(.84-.055*pulse),x=i*step;
    ctx.beginPath();rounded(ctx,x,yy,ww,hh,Math.min(hh/2,ww/2));ctx.fillStyle=grad;ctx.globalAlpha=.9;ctx.fill();ctx.globalAlpha=1;
    ctx.save();ctx.clip();const gloss=ctx.createLinearGradient(0,yy,0,yy+hh);gloss.addColorStop(0,color('#ffffff',.28+energy*.25));gloss.addColorStop(.42,color('#ffffff',0));gloss.addColorStop(1,color('#130b29',.3));ctx.fillStyle=gloss;ctx.fillRect(x,yy,ww,hh);ctx.restore();
    ctx.beginPath();oval(ctx,x+ww*.34,yy+hh*.23,ww*.15,Math.max(.5,hh*.055),-.1,0,tau);ctx.fillStyle=color('#ffffff',.35+energy*.25);ctx.fill();
   }
  }else if(kind==='photons'){
   for(let lane=0;lane<4;lane++){const yy=h*(.17+lane*.22);ctx.lineWidth=Math.max(.6,h*.055);ctx.strokeStyle=color(lane%2?last:first,.35);ctx.beginPath();ctx.moveTo(0,yy);ctx.lineTo(front,yy);ctx.stroke();
    for(let i=0;i<7;i++){const direction=mode===1&&lane%2?-1:1,burst=mode===2?(Math.sin(t*3+i)>-.2?1:.08):1,x=fract(t*(.23+lane*.025)*direction+i/7+lane*.13)*w,len=Math.max(10,h*(1.3+energy));const streak=ctx.createLinearGradient(x-len,0,x,0);streak.addColorStop(0,color(first,0));streak.addColorStop(.7,color(lane%2?last:first,.8*burst));streak.addColorStop(1,color('#ffffff',(.5+energy*.5)*burst));ctx.strokeStyle=streak;ctx.lineWidth=Math.max(1,h*.075);ctx.beginPath();ctx.moveTo(x-len,yy);ctx.lineTo(x,yy);ctx.stroke()}
   }
  }else if(kind==='crystal'){
   const step=Math.max(18,h*1.15);
   for(let i=0;i<Math.ceil(w/step);i++){const x=i*step,p=mode===1?Math.sin(t*2.7+i*1.8):Math.cos(t*(mode===2?2.2:1.5)-i*.4),lift=h*.05*p;
    ctx.fillStyle=grad;ctx.globalAlpha=.72+.15*p;ctx.beginPath();ctx.moveTo(x+2,h*.18+lift);ctx.lineTo(x+step*.56,h*.04);ctx.lineTo(x+step-2,h*.35-lift);ctx.lineTo(x+step*.86,h*.83);ctx.lineTo(x+step*.31,h*.96);ctx.lineTo(x+1,h*.63);ctx.closePath();ctx.fill();ctx.globalAlpha=1;
    ctx.fillStyle=color('#ffffff',(.12+.25*Math.max(0,p))*energy);ctx.beginPath();ctx.moveTo(x+2,h*.18+lift);ctx.lineTo(x+step*.56,h*.04);ctx.lineTo(x+step*.53,h*.51);ctx.closePath();ctx.fill();
    ctx.strokeStyle=color('#ffffff',(.15+.5*Math.max(0,p))*energy);ctx.lineWidth=.7;ctx.beginPath();ctx.moveTo(x+step*.31,h*.96);ctx.lineTo(x+step*.53,h*.51);ctx.lineTo(x+step-2,h*.35-lift);ctx.stroke();
   }
  }else if(kind==='capillary'){
   const step=Math.max(48,h*3.2);
   for(let lane=0;lane<3;lane++){const yy=h*(.22+lane*.28);ctx.strokeStyle=color(lane%2?last:first,.65);ctx.lineWidth=Math.max(1,h*.07);ctx.beginPath();ctx.moveTo(0,yy);ctx.lineTo(front,yy);ctx.stroke();
    for(let i=0;i<Math.ceil(w/step);i++){const x=i*step,phase=t*(mode===2?3:2)-i*.8-lane,flare=mode===2?Math.pow(Math.max(0,Math.sin(t*2)),3):Math.max(0,Math.sin(phase));ctx.beginPath();ctx.moveTo(x,yy);ctx.bezierCurveTo(x+step*.25,yy,x+step*.25,h*(lane===1?.2:.75),x+step*.54,h*(lane===1?.2:.75));ctx.strokeStyle=color(lane%2?last:first,.4+flare*.5);ctx.stroke();
     const xx=x+fract(t*(mode===1?.22:.4)+lane*.24+i*.13)*step;ctx.beginPath();ctx.arc(xx,yy,Math.max(.8,h*(.035+flare*.035)),0,tau);ctx.fillStyle=color('#ffffff',.3+energy*.65);ctx.fill();
    }
   }
  }else if(kind==='vortex'){
   const step=Math.max(40,h*2.6);
   for(let i=0;i<Math.ceil(w/step)+1;i++){const cx=i*step+step*.3,cy=h/2,rotation=t*(i%2?-.9:1.1),arms=mode===1?2:3;
    for(let arm=0;arm<arms;arm++){ctx.beginPath();for(let j=0;j<=42;j++){const a=j/42*Math.PI*1.7+rotation+arm*tau/arms,r=.1+j/42*.38,x=cx+Math.cos(a)*step*r,y=cy+Math.sin(a)*h*r;if(j===0)ctx.moveTo(x,y);else ctx.lineTo(x,y)}ctx.strokeStyle=arm%2?color(last,.85):color(first,.9);ctx.lineWidth=Math.max(1,h*(mode===2?.055:.09));ctx.stroke()}
    for(let j=0;j<(mode===2?7:2);j++){const a=rotation+j*tau/7,r=.29+(j%3)*.05;ctx.beginPath();oval(ctx,cx+Math.cos(a)*step*r,cy+Math.sin(a)*h*r,Math.max(.7,h*.04),Math.max(.5,h*.025),a,0,tau);ctx.fillStyle=color('#ffffff',(.2+energy*.6));ctx.fill()}
   }
  }
    // Apply lighting only to painted artwork; empty areas keep alpha zero.
    ctx.globalCompositeOperation="source-atop"
    const light=ctx.createLinearGradient(0,0,0,h),optic=finish.optic||0
    light.addColorStop(0,color("#ffffff",Math.min(.85,energy*(optic===2?.85:.5))))
    light.addColorStop(optic===2?.42:.45,color("#ffffff",0))
    light.addColorStop(1,color(optic===3||optic===12?last:"#170d2b",Math.min(.8,(finish.depth||.3)*.4)))
    ctx.fillStyle=light;ctx.fillRect(0,0,front,h)
    if([6,7,9,10].includes(optic)) {
        ctx.strokeStyle=color(optic===10?last:"#ffffff",.2+energy*.2);ctx.lineWidth=Math.max(.6,h*.025)
        const step=optic===9?Math.max(3,h*.2):Math.max(6,h)
        for(let x=-h;x<front;x+=step){ctx.beginPath();ctx.moveTo(x,h);ctx.lineTo(x+h,0);ctx.stroke()}
    }
    ctx.restore()
}

function drawLegacy(ctx,o) {
    const w=o.width,h=o.height,front=o.front,t=o.phase,tick=fract(t/tau),motion=o.animation
    ctx.save();ctx.lineCap="round"
    if(o.layout==="pill-segments") {
        const gap=Math.min(8,h*.48,w/16),span=(w-4*gap)/5
        for(let i=0;i<5;i++) {
            const pulse=.5+.5*Math.sin(t-i*(motion==="pill-wave"?1.2:.7))
            const x=i*(span+gap)
            if(motion==="pill-squeeze") {
                ctx.strokeStyle=color("#ffffff",.12+.42*pulse);ctx.lineWidth=Math.max(.8,h*.05)
                ctx.beginPath();ctx.moveTo(x+span*.16,h*(.22+.14*pulse));ctx.quadraticCurveTo(x+span*.5,h*.08,x+span*.84,h*(.22+.14*pulse));ctx.stroke()
            } else {
                const light=ctx.createLinearGradient(x,0,x+span,0)
                light.addColorStop(0,color("#ffffff",0));light.addColorStop(.5,color("#ffffff",motion==="pill-cascade"?.5*Math.pow(pulse,4):.32*pulse));light.addColorStop(1,color("#ffffff",0))
                ctx.fillStyle=light;ctx.fillRect(x,0,span,h)
            }
        }
    } else if(o.layout==="thin-line") {
        ctx.lineWidth=Math.max(.8,h*.65)
        if(motion==="line-breathe") {
            ctx.strokeStyle=color("#ffffff",.12+.36*(.5+.5*Math.sin(t)));ctx.beginPath();ctx.moveTo(0,h/2);ctx.lineTo(front,h/2);ctx.stroke()
        } else for(let i=0;i<(motion==="line-packets"?6:1);i++) {
            const x=fract(tick+i/6)*w,length=motion==="line-packets"?Math.max(4,h*2):Math.max(12,w*.18)
            const light=ctx.createLinearGradient(x-length,0,x,0);light.addColorStop(0,color(o.startColor,0));light.addColorStop(1,color("#ffffff",.9))
            ctx.strokeStyle=light;ctx.beginPath();ctx.moveTo(x-length,h/2);ctx.lineTo(x,h/2);ctx.stroke()
        }
    } else if(o.layout==="status-track") {
        if(motion==="status-breathe") {ctx.fillStyle=color("#ffffff",.04+.14*Math.pow(.5+.5*Math.sin(t),2));ctx.fillRect(0,0,front,h)}
        else if(motion==="status-signal") {const radius=Math.max(1,h*.12)+(.5+.5*Math.sin(t))*h*.33;ctx.strokeStyle=color("#ffffff",.5);ctx.lineWidth=Math.max(.7,h*.05);ctx.beginPath();ctx.arc(Math.max(0,front-h*.32),h/2,radius,0,tau);ctx.stroke()}
        else {const x=tick*w;ctx.fillStyle=color("#ffffff",.24);ctx.fillRect(x,0,Math.max(1,h*.15),h)}
    }
    ctx.restore()
}
