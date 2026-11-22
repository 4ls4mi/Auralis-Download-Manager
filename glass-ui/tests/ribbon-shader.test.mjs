import test from 'node:test';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {browserFixture} from './browser-fixture.mjs';

const browserPath = process.env.AURALIS_TEST_BROWSER || (process.platform === 'linux' ? '/usr/bin/chromium' : '');
const skip = !browserPath || !existsSync(browserPath);
const fixture = browserFixture(browserPath, ['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader']);

test('ribbon shader compiles with independent backdrop gradient colors', {skip}, async t => {
  const {page, baseUrl} = await fixture.openPage(t);
  await page.goto(baseUrl);
  const result = await page.evaluate(async () => {
    const {ribbonFragment} = await import('/src/frostedRibbonShader.ts');
    const gl = document.createElement('canvas').getContext('webgl');
    if (!gl) return 'WebGL unavailable';
    const shader = gl.createShader(gl.FRAGMENT_SHADER);
    gl.shaderSource(shader, ribbonFragment);
    gl.compileShader(shader);
    return gl.getShaderParameter(shader, gl.COMPILE_STATUS) ? 'ok' : gl.getShaderInfoLog(shader);
  });
  assert.equal(result, 'ok');
});

test('clear, frosted and recessed ribbon backdrops render differently', {skip}, async t => {
  const {page, baseUrl} = await fixture.openPage(t);
  await page.goto(baseUrl);
  const backdrops = await page.evaluate(async () => {
    const {ribbonFragment} = await import('/src/frostedRibbonShader.ts');
    const {frostVertex} = await import('/src/frostedLayersShader.ts');
    const canvas = document.createElement('canvas');
    canvas.width = 200;
    canvas.height = 60;
    const gl = canvas.getContext('webgl', {preserveDrawingBuffer: true});
    const compile = (type, source) => {
      const shader = gl.createShader(type);
      gl.shaderSource(shader, source);
      gl.compileShader(shader);
      if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw Error(gl.getShaderInfoLog(shader));
      return shader;
    };
    const program = gl.createProgram();
    gl.attachShader(program, compile(gl.VERTEX_SHADER, frostVertex));
    gl.attachShader(program, compile(gl.FRAGMENT_SHADER, ribbonFragment));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw Error(gl.getProgramInfoLog(program));
    gl.useProgram(program);
    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const position = gl.getAttribLocation(program, 'position');
    gl.enableVertexAttribArray(position);
    gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);
    const {width, height} = canvas;
    gl.viewport(0, 0, width, height);
    gl.uniform2f(gl.getUniformLocation(program, 'viewport'), width, height);
    gl.uniform1f(gl.getUniformLocation(program, 'progress'), 0);
    const trackFinish = gl.getUniformLocation(program, 'trackFinish');
    const draw = (finish, pixels) => {
      gl.uniform1f(trackFinish, finish);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      gl.readPixels(0, 0, width, height, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
    };
    const baseline = new Uint8Array(width * height * 4);
    const pixels = new Uint8Array(baseline.length);
    draw(0, baseline);
    return [1, 2, 3].map(finish => {
      draw(finish, pixels);
      return {finish, differs: pixels.some((value, index) => value !== baseline[index])};
    });
  });
  for (const {finish, differs} of backdrops) assert.ok(differs, `finish ${finish} must change the rendered backdrop`);
});

test('ribbon preserves a visible backdrop and fill when WebGL is unavailable', {skip}, async t => {
  const {page, baseUrl} = await fixture.openPage(t);
  await page.addInitScript(() => {
    const original = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function (type, ...args) {
      return type === 'webgl' ? null : original.call(this, type, ...args);
    };
  });
  await page.goto(baseUrl);
  await page.evaluate(async () => {
    const {default: React} = await import('/node_modules/.vite/deps/react.js');
    const {default: {createRoot}} = await import('/node_modules/.vite/deps/react-dom_client.js');
    const {default: Ribbon} = await import('/src/FrostedRibbon.tsx');
    const host = document.createElement('div');
    host.className = 'cg-window';
    host.innerHTML = '<div id="ribbon-test" class="cg-percent-track cg-track-frosted" style="width:300px;height:36px"></div>';
    document.body.append(host);
    createRoot(document.getElementById('ribbon-test')).render(React.createElement(Ribbon, {
      shape: 'rounded', percent: 40, colors: ['#ff0000', '#00ff00', '#0000ff'],
      fallback: 'linear-gradient(red,blue)', finish: 'frosted', tint: 'ice'
    }));
  });
  await page.waitForSelector('.cg-ribbon-fallback-track');
  const state = await page.evaluate(() => ({
    background: getComputedStyle(document.querySelector('.cg-ribbon-fallback-track')).backgroundImage,
    fill: document.querySelector('.cg-ribbon-fallback').style.width
  }));
  assert.notEqual(state.background, 'none');
  assert.equal(state.fill, '40%');
});

test('sculpted liquid remains selected for every supported progress shape and old shapes migrate', {skip}, async t => {
  const {page, baseUrl} = await fixture.openPage(t);
  await page.goto(baseUrl);
  const result = await page.evaluate(async () => {
    const {default: React} = await import('/node_modules/.vite/deps/react.js');
    const {default: {createRoot}} = await import('/node_modules/.vite/deps/react-dom_client.js');
    const shared = await import('/src/CrystalShared.tsx');
    localStorage.setItem('mh-glass-progress-shape', 'spiral');
    localStorage.setItem('mh-glass-connection-shape', 'openring');
    const old = shared.loadAppearance();
    const shapes = [];
    for (const shape of ['rounded', 'square', 'faceted', 'bubble']) {
      localStorage.setItem('mh-glass-progress-shape', shape);
      localStorage.setItem('mh-glass-progress-material', 'liquid-glass');
      const host = document.createElement('div');
      document.body.append(host);
      const root = createRoot(host);
      root.render(React.createElement(shared.CrystalProvider, null, React.createElement(shared.GradientBar, {percent: 50})));
      await new Promise(resolve => setTimeout(resolve, 100));
      const selector = shape === 'bubble' ? 'svg.cg-bubble-vessel' : 'canvas.cg-liquid-progress';
      shapes.push({shape, canvas: Boolean(host.querySelector(selector))});
      root.unmount();
      host.remove();
    }
    return {oldProgress: old.progressShape, oldConnection: old.connectionShape, shapes};
  });
  assert.equal(result.oldProgress, 'rounded');
  assert.equal(result.oldConnection, 'rounded');
  for (const {shape, canvas} of result.shapes) assert.equal(canvas, true, `${shape} must use sculpted liquid`);
});
