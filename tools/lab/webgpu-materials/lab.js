// Experimental WebGPU pipeline. Synthetic background only; never captures desktop pixels.
const canvas = document.querySelector('canvas');
const status = document.querySelector('#status');
const shader = `
struct Config { size: vec2f, mode: f32, light: f32, accent: vec4f };
@group(0) @binding(0) var<uniform> c: Config;
struct VOut { @builtin(position) pos: vec4f, @location(0) uv: vec2f };
@vertex fn vert(@builtin(vertex_index) i:u32)->VOut {
 let p=array<vec2f,3>(vec2f(-1.,-1.),vec2f(3.,-1.),vec2f(-1.,3.));
 var o:VOut; o.pos=vec4f(p[i],0.,1.); o.uv=p[i]*.5+.5; return o;
}
fn rounded(p:vec2f,b:vec2f,r:f32)->f32 { let q=abs(p)-b+vec2f(r);return length(max(q,vec2f(0.)))+min(max(q.x,q.y),0.)-r; }
@fragment fn frag(i:VOut)->@location(0) vec4f {
 let uv=vec2f(i.uv.x,1.-i.uv.y);let p=(uv-vec2f(.5))*vec2f(c.size.x/c.size.y,1.);
 let halfSize=vec2f(c.size.x/c.size.y*.44,.39);
 var d=rounded(p,halfSize,.065);
 if(c.mode<.5){ let wave=.025*sin(p.x*15.)+.012*sin(p.x*26.); d=rounded(vec2f(p.x,p.y+wave),halfSize,.13); }
 if(c.mode>=.5 && c.mode<1.5 || c.mode>=4.5){ let q=abs(p)-halfSize; d=max(max(q.x,q.y),(q.x+q.y+.055)*.707); }
 if(c.mode>=1.5 && c.mode<2.5){let q=abs(p)-halfSize;d=max(max(q.x,q.y),(q.x+q.y+.035)*.707);}
 let inside=1.-smoothstep(-.003,.003,d);let edge=exp(-abs(d)*100.);
 let bg=mix(vec3f(.012,.035,.12),vec3f(.07,.27,.48),uv.y)+vec3f(.045,.03,.11)*sin(uv.x*5.+uv.y*3.);
 let base=mix(vec3f(.015,.045,.11),vec3f(.74,.84,.94),c.light*.85);
 var surface=mix(base,c.accent.rgb,.27);let top=pow(max(0.,1.-abs(uv.y-.16)*5.),2.);
 surface+=vec3f(.18,.23,.28)*top;
 if(c.mode<.5){surface+=vec3f(.13,.27,.32)*pow(max(0.,sin(p.x*12.+p.y*5.)),12.);}
 if(c.mode>=.5 && c.mode<1.5 || c.mode>=4.5){let facet=abs(sin(p.x*23.+floor(p.y*15.)*1.7));surface+=vec3f(.10,.16,.24)*pow(facet,8.);}
 if(c.mode>=1.5 && c.mode<2.5){surface*=.65;surface+=vec3f(.08)*step(.5,fract((p.x+p.y)*4.));}
 if(c.mode>=2.5 && c.mode<3.5){surface=mix(surface,vec3f(.66,.78,.91),.43);surface+=vec3f(.08)*smoothstep(.04,.0,abs(p.y+.08*sin(p.x*5.)));}
 if(c.mode>=3.5 && c.mode<4.5){surface+=vec3f(.22,.28,.35)*pow(max(0.,1.-abs(p.y+.18-.08*cos(p.x*3.))*8.),4.);}
 if(c.mode>=4.5){surface+=.15*(.5+.5*cos(vec3f(0.,2.,4.)+p.x*8.+p.y*9.));}
 let edgeColor=mix(vec3f(.38,.75,.93),c.accent.rgb,.25);let color=mix(bg,surface,inside)+edge*edgeColor*.7;
 return vec4f(color,1.);
}`;
try {
 if (!navigator.gpu) throw Error('WebGPU is unavailable in this WebView/browser.');
 const adapter=await navigator.gpu.requestAdapter(); if(!adapter)throw Error('No WebGPU adapter available.');
 const device=await adapter.requestDevice(); const context=canvas.getContext('webgpu'); const format=navigator.gpu.getPreferredCanvasFormat();
 context.configure({device,format,alphaMode:'opaque'});
 const module=device.createShaderModule({code:shader});const info=await module.getCompilationInfo();
 const errors=info.messages.filter(m=>m.type==='error');if(errors.length)throw Error(errors.map(e=>e.message).join('; '));
 const pipeline=device.createRenderPipeline({layout:'auto',vertex:{module,entryPoint:'vert'},fragment:{module,entryPoint:'frag',targets:[{format}]},primitive:{topology:'triangle-list'}});
 const buffer=device.createBuffer({size:32,usage:GPUBufferUsage.UNIFORM|GPUBufferUsage.COPY_DST});
 const bind=device.createBindGroup({layout:pipeline.getBindGroupLayout(0),entries:[{binding:0,resource:{buffer}}]});
 function draw(){let w=Math.max(1,Math.round(canvas.clientWidth*devicePixelRatio)),h=Math.max(1,Math.round(canvas.clientHeight*devicePixelRatio));canvas.width=w;canvas.height=h;
 const hex=document.querySelector('#accent').value; const rgb=[1,3,5].map(n=>parseInt(hex.slice(n,n+2),16)/255);
 device.queue.writeBuffer(buffer,0,new Float32Array([w,h,document.querySelector('#style').selectedIndex,document.querySelector('#light').checked?1:0,...rgb,1]));
 const cmd=device.createCommandEncoder(),pass=cmd.beginRenderPass({colorAttachments:[{view:context.getCurrentTexture().createView(),loadOp:'clear',storeOp:'store',clearValue:{r:0,g:0,b:0,a:1}}]});pass.setPipeline(pipeline);pass.setBindGroup(0,bind);pass.draw(3);pass.end();device.queue.submit([cmd.finish()]);}
 document.querySelectorAll('select,input').forEach(el=>el.addEventListener('input',draw));new ResizeObserver(draw).observe(canvas);device.lost.then(info=>{status.textContent='GPU device lost: '+info.message});draw();status.textContent='WebGPU prototype running; native backdrop integration and Windows visual validation remain unfinished.';
} catch(e) {status.textContent=String(e);}
