import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const qml = new URL("../../qt-ui/qml/", import.meta.url);
const progress = readFileSync(new URL("ProgressMotion.qml", qml), "utf8");
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

test("motion clears the previous frame and never paints without an explicit fill mask", () => {
  const code = method(progress, "motion") + method(progress, "drawProgress") + ";drawProgress(ctx);";
  for (const animationStyle of ["none", "sheen", "heartbeat", "tide", "elastic", "glints", "current"]) {
    for (const width of [0, 2, 300]) for (const fraction of [0, .01, .42, 1]) for (const fillMask of ["", "M 0 0 H 126 V 24 H 0 Z"]) {
      const ctx = canvas();
      vm.runInNewContext(code, {ctx, width, height:24, fraction, animationStyle, fillMask, phase:1.2});
      assert.equal(ctx.calls[0][0], "reset");
      assert.equal(ctx.calls[1][0], "clearRect");
      if (!width || !fraction || !fillMask || animationStyle === "none") {
        assert.ok(!ctx.calls.some(([name]) => ["fill", "fillRect", "stroke"].includes(name)));
      } else {
        assert.deepEqual(ctx.calls.find(([name]) => name === "rect"), ["rect",0,0,width*fraction,24]);
        assert.equal(ctx.path, fillMask);
      }
    }
  }
});

test("retired layouts safely fall back to Classic while older layouts remain available", () => {
  const source = readFileSync(new URL("ProgressLayoutGeometry.js", qml), "utf8");
  const context = {};
  vm.runInNewContext(source.replace(/^\.(?:pragma|import).*$/gm, ""), context);
  for (const name of ["liquid-capsule", "jelly-beads", "braided-ribbon", "prism-segments", "molten-glass", "orbit-marker", "glass-tiles", "checkpoints", "tidal-ribbon", "frosted-cells", "filament-core", "twin-rails"])
    assert.equal(context.style(name), "classic");
  for (const name of ["classic", "status-track", "pill-segments", "thin-line", "striped-fill"])
    assert.equal(context.style(name), name);
});
