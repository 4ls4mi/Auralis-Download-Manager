import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const qml = new URL("../../qt-ui/qml/", import.meta.url);
const progress = readFileSync(new URL("CreativeProgress.qml", qml), "utf8");
const graph = readFileSync(new URL("TransferGraph.qml", qml), "utf8");
function method(source, name) {
  const match = source.match(new RegExp("    function " + name + "\\(([^)]*)\\) \\{([\\s\\S]*?)\\n    \\}"));
  assert.ok(match, name);
  return `function ${name}(${match[1]}) {${match[2]}}`;
}
function canvas() {
  const calls = [], strokes = [];
  let path = [];
  const ctx = { calls, strokes };
  for (const name of ["reset", "clearRect", "lineTo", "moveTo", "quadraticCurveTo", "closePath",
    "fill", "stroke", "save", "restore", "clip", "fillRect", "rect", "arc", "translate"]) {
    ctx[name] = (...args) => {
      for (const value of args) assert.ok(Number.isFinite(value), `${name}: ${value}`);
      calls.push([name, ...args]);
      if (name === "moveTo" || name === "lineTo") path.push(args);
      if (name === "stroke") strokes.push(path.map(point => [...point]));
    };
  }
  ctx.beginPath = () => { path = []; };
  ctx.createLinearGradient = (...args) => {
    assert.ok(args.every(Number.isFinite));
    return { addColorStop(offset) { assert.ok(offset >= 0 && offset <= 1); } };
  };
  return ctx;
}

const layouts = ["liquid-capsule", "jelly-beads", "braided-ribbon", "prism-segments", "molten-glass", "orbit-marker", "glass-tiles", "checkpoints", "tidal-ribbon", "frosted-cells", "filament-core", "twin-rails"];
test("all creative progress renderers clip to the real progress boundary at narrow and normal sizes", () => {
  const code = method(progress, "capsule") + method(progress, "motion") + method(progress, "drawProgress") + ";drawProgress(ctx);";
  for (const layoutStyle of layouts) for (const width of [2, 20, 300]) for (const height of [2, 16, 32]) {
    for (const amount of [0, .01, .68, 1, -1, 2, NaN]) {
      const fraction = Number.isFinite(amount) ? Math.max(0, Math.min(1, amount)) : 0;
      const ctx = canvas();
      vm.runInNewContext(code, { ctx, width, height, fraction, layoutStyle,
        startColor: "#38d8ce", endColor: "#a97afa", trackColor: "#202530", phase: .5, light: false, shape:"round", overlayOnly:false, animationStyle:"none", finish:{reflection:1,depth:1}, Qt:{rgba:()=>"white"} });
      const clips = ctx.calls.filter(([name]) => name === "rect");
      if (width < 3 || height < 3 || fraction === 0) assert.equal(clips.length, 0);
      else {
        assert.equal(clips.length, 1);
        assert.equal(clips[0][1], 2);
        assert.equal(clips[0][3], (width - 4) * fraction);
      }
    }
  }
});

test("each graph material preserves sample values and its top-edge coordinates", () => {
  const helpers = ["trace", "gradient", "paintJelly", "paintSatin"].map(name => method(graph, name)).join("\n");
  for (const graphMaterial of ["jelly", "frosted", "crystal", "satin", "pearl", "aurora-mesh", "carbon", "mercury"]) for (const compact of [false, true]) for (const graphShape of ["area", "line"]) {
    const samples = [0, 2, 7, 3, 9, 1], original = [...samples], ctx = canvas();
    const draw = graphMaterial === "satin" && graphShape === "line" ? "paintSatin(ctx,10,99,90)" : "paintJelly(ctx,10,99,90,null)";
    vm.runInNewContext(helpers + ";" + draw, { ctx, samples, width: 201, height: 100,
      compact, graphMaterial, graphShape, flowEnabled:false, lighting:{reflection:1}, opticalShade:()=>"shade", lineColor: "purple", endpointColor: "teal",
      lineTone: { edge: "white" }, endpointTone: { edge: "cyan" }, MaterialTheme: { rgba: color => color, mix:color=>color } });
    const expected = samples.map((value, index) => [index * 40, 99 - value / 10 * 90]);
    assert.deepEqual(ctx.strokes.at(-1), expected);
    assert.deepEqual(samples, original);
  }
});

test("bar materials preserve the measured height of every sample", () => {
  const code=method(graph,"gradient")+method(graph,"drawBars")+";drawBars(ctx,10,99,90,'glow','core','edge',null);";
  for (const graphMaterial of ["jelly","frosted","crystal","satin","pearl","aurora-mesh","carbon","mercury"]) {
    const samples=[0,2,7,3,9,1], ctx=canvas(), tone={edge:"white",core:"teal",body:"purple"};
    vm.runInNewContext(code,{ctx,samples,width:201,height:100,compact:false,light:false,graphMaterial,optic:0,
      lineColor:"teal",endpointColor:"purple",lineTone:tone,endpointTone:tone,
      lighting:{halo:1,haloWidth:1,reflection:1,depth:1,caustic:0},MaterialTheme:{rgba:color=>color,mix:color=>color}});
    for(let i=1;i<samples.length;i++) {
      const x=i*33.5+1.5,h=samples[i]/10*90;
      assert.ok(ctx.calls.some(([name,px,py,pw,ph])=>name === "fillRect" && px === x && py === 99-h && pw === 30.5 && ph === h));
    }
    assert.deepEqual(samples,[0,2,7,3,9,1]);
  }
});

test("progress motion stays inside the measured fill for every layout and frame shape", () => {
  const code = ["capsule", "motion", "drawProgress"].map(name => method(progress,name)).join("\n")+";drawProgress(ctx);";
  for (const layoutStyle of layouts) for (const animationStyle of ["none", "classic", "water", "jelly", "sheen", "heartbeat", "tide", "elastic", "glints", "current"]) {
    for (const shape of ["round", "square", "prism"]) for (const overlayOnly of [false,true]) {
      const ctx=canvas();
      vm.runInNewContext(code,{ctx,width:300,height:24,fraction:.42,layoutStyle,animationStyle,shape,overlayOnly,fillMask:"",
        startColor:"teal",endColor:"purple",trackColor:"black",phase:1.2,light:false,finish:{reflection:.8,depth:.6},Qt:{rgba:()=>"white"}});
      const clip=ctx.calls.find(([name])=>name === "rect");
      assert.equal(clip[3],296*.42);
    }
  }
});

test("every creative layout is recognized by both selection and renderer", () => {
  const choices = readFileSync(new URL("WindowAppearance.qml", qml), "utf8");
  const geometry = readFileSync(new URL("ProgressLayoutGeometry.js", qml), "utf8");
  const host = readFileSync(new URL("GlassProgress.qml", qml), "utf8");
  for (const layout of layouts) {
    assert.ok(choices.includes(`value: "${layout}"`));
    assert.ok(geometry.includes(`case "${layout}":`));
    assert.ok(host.includes(`"${layout}"`));
  }
});
