import {useEffect, useRef} from "react";
import {auroraDarkOpticsGLSL} from "./auroraDarkOptics";
import {auroraLightOpticsGLSL} from "./auroraLightOptics";
import "./aurora-optics.css";

const vertexSource = `
  attribute vec2 position;
  varying vec2 uv;
  void main() {
    uv = position * .5 + .5;
    gl_Position = vec4(position, 0., 1.);
  }
`;

function compile(gl: WebGLRenderingContext, shader: WebGLShader, source: string) {
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    throw new Error(gl.getShaderInfoLog(shader) || "Aurora shader could not compile");
  }
}

/** Renders the glass geometry and reflected light over the native backdrop. */
export function AuroraOptics({variant}: {variant: "dark" | "light"}) {
  const ref = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = ref.current;
    if (!canvas) return;
    const gl = canvas.getContext("webgl", {
      alpha: true,
      depth: false,
      antialias: false,
      premultipliedAlpha: false,
    });
    if (!gl) return;

    let disposeScene: (() => void) | undefined;
    const setup = () => {
      const vertex = gl.createShader(gl.VERTEX_SHADER);
      const fragment = gl.createShader(gl.FRAGMENT_SHADER);
      const program = gl.createProgram();
      const vertices = gl.createBuffer();
      const release = () => {
        if (vertices) gl.deleteBuffer(vertices);
        if (program) gl.deleteProgram(program);
        if (fragment) gl.deleteShader(fragment);
        if (vertex) gl.deleteShader(vertex);
        delete canvas.dataset.rendered;
      };

      if (!vertex || !fragment || !program || !vertices) {
        release();
        return;
      }

      const optics = variant === "dark" ? auroraDarkOpticsGLSL : auroraLightOpticsGLSL;
      try {
        compile(gl, vertex, vertexSource);
        compile(gl, fragment, `
          precision highp float;
          uniform float aspect;
          varying vec2 uv;
          ${optics}
          void main() {
            gl_FragColor = clamp(${variant}Optics(uv, aspect), 0., 1.);
          }
        `);
        gl.attachShader(program, vertex);
        gl.attachShader(program, fragment);
        gl.linkProgram(program);
        if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
          throw new Error(gl.getProgramInfoLog(program) || "Aurora shader could not link");
        }
      } catch (error) {
        console.warn("Aurora optics could not initialize", error);
        release();
        return;
      }

      gl.useProgram(program);
      gl.bindBuffer(gl.ARRAY_BUFFER, vertices);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
      const position = gl.getAttribLocation(program, "position");
      const aspect = gl.getUniformLocation(program, "aspect");
      gl.enableVertexAttribArray(position);
      gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);

      let frame = 0;
      const draw = () => {
        frame = 0;
        const width = canvas.clientWidth;
        const height = canvas.clientHeight;
        if (!width || !height || document.hidden || gl.isContextLost()) return;

        // The optics contain broad surfaces. Cap resolution to keep large
        // windows cheap, and render only as needed for a resize or restore.
        const scale = Math.min(window.devicePixelRatio || 1, 1.5, 1600 / Math.max(width, height));
        canvas.width = Math.max(1, Math.round(width * scale));
        canvas.height = Math.max(1, Math.round(height * scale));
        gl.viewport(0, 0, canvas.width, canvas.height);
        gl.uniform1f(aspect, width / height);
        gl.drawArrays(gl.TRIANGLES, 0, 3);
        canvas.dataset.rendered = variant;
      };

      const requestDraw = () => { if (!frame) frame = requestAnimationFrame(draw); };
      const observer = new ResizeObserver(requestDraw);
      observer.observe(canvas);
      document.addEventListener("visibilitychange", requestDraw);
      requestDraw();

      return () => {
        observer.disconnect();
        document.removeEventListener("visibilitychange", requestDraw);
        cancelAnimationFrame(frame);
        release();
      };
    };

    const onContextLost = (event: Event) => {
      event.preventDefault();
      disposeScene?.();
      disposeScene = undefined;
    };
    const onContextRestored = () => { disposeScene = setup(); };

    canvas.addEventListener("webglcontextlost", onContextLost);
    canvas.addEventListener("webglcontextrestored", onContextRestored);
    disposeScene = setup();
    return () => {
      canvas.removeEventListener("webglcontextlost", onContextLost);
      canvas.removeEventListener("webglcontextrestored", onContextRestored);
      disposeScene?.();
    };
  }, [variant]);

  return <canvas className="cg-aurora-optics" ref={ref} aria-hidden="true"/>;
}
