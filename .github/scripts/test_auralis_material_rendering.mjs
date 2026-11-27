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

function library(name, imports = {}) {
  const context = {...imports};
  vm.runInNewContext(readFileSync(new URL(name, qml), "utf8").replace(/^\.(?:pragma|import).*$/gm, ""), context);
  return context;
}
const styles = library("ProgressStyles.js");
const geometry = library("MaterialGeometry.js");
const artwork = library("ProgressArtwork.js", {Styles:styles, Geometry:geometry});

test("each layout has three own motions and a static option; old settings migrate safely", () => {
  const seen = new Set();
  for (const {value:layout} of styles.layouts()) {
    const choices=styles.choices(layout);
    assert.equal(choices.length,4);
    assert.equal(choices.at(-1).value,"none");
    for (const choice of choices.slice(0,-1)) { assert.ok(!seen.has(choice.value)); seen.add(choice.value); }
    for (const legacy of [undefined,"bogus","classic","water","jelly","sheen","heartbeat","tide","elastic","glints","current"])
      assert.ok(choices.some(option=>option.value===styles.normalize(layout,legacy)));
    assert.equal(styles.normalize(layout,"none"),"none");
  }
  assert.equal(styles.layouts().length,11);
  assert.equal(seen.size,33);
  assert.equal(styles.layout("liquid-capsule"),"classic");
  assert.deepEqual(JSON.parse(JSON.stringify(styles.remembered({"elastic-gel":"gel-spring",invalid:"bad"}))),{"elastic-gel":"gel-spring"});
});

test("new artwork stays clipped to progress at normal, compact, tiny and empty sizes", () => {
  for(const {value:layout} of styles.layouts().filter(option=>styles.artistic(option.value))) {
    for(const {value:animation} of styles.choices(layout)) for(const width of [0,2,320]) for(const height of [3,14,32]) for(const amount of [0,.01,.42,1]) {
      const ctx=canvas();
      ctx.bezierCurveTo=(...args)=>assert.ok(args.every(Number.isFinite));
      artwork.draw(ctx,{width,height,amount,layout,animation,phase:1.25,shape:"round",startColor:"#9069f8",endColor:"#ba98ff",finish:{reflection:.7,depth:.4,optic:6}});
      if(!width||!amount) assert.equal(ctx.calls.length,0);
      else {
        assert.ok(ctx.calls.filter(([name])=>name==="clip").length>=2);
        assert.ok(ctx.calls.some(([name,x,y,w,h])=>name==="rect"&&x===0&&y===0&&w===width*amount&&h===height));
        assert.equal(ctx.globalCompositeOperation,"source-atop");
      }
    }
  }
});

test("legacy overlay uses the exact masked front rather than painting an unfilled track", () => {
  const code=method(progress,"drawProgress")+";drawProgress(ctx);";
  for(const layoutStyle of ["status-track","pill-segments","thin-line"]) for(const {value:animationStyle} of styles.choices(layoutStyle)) {
    for(const fraction of [0,.42,1]) for(const fillMask of ["","M 0 0 H 125 V 24 H 0 Z"]) {
      const ctx=canvas();
      vm.runInNewContext(code,{ctx,width:300,height:24,fraction,clipFront:125,layoutStyle,animationStyle,fillMask,phase:1.25,startColor:"#9069f8",endColor:"#ba98ff",Styles:styles,Artwork:artwork});
      assert.equal(ctx.calls[0][0],"reset");assert.equal(ctx.calls[1][0],"clearRect");
      if(!fraction||!fillMask||animationStyle==="none") assert.equal(ctx.calls.length,2);
      else assert.ok(ctx.calls.some(([name,x,y,w])=>name==="rect"&&w===125));
    }
  }
});
