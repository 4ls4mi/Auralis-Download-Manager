/** Dark Aurora models reflections on broad intersecting glass volumes. */
export const auroraDarkOpticsGLSL = /* glsl */ `
float darkGlassHighlight(float distanceToCenter, float width) {
  float spread = distanceToCenter / width;
  return exp(-spread * spread);
}

vec4 darkGlassVolume(vec2 uv, float aspect, vec2 center, vec2 radii, float tilt,
                     float curvature, float lightTurn, float intensity) {
  vec2 position = (uv - center) * vec2(aspect, 1.0);
  float c = cos(tilt);
  float s = sin(tilt);
  vec2 point = mat2(c, -s, s, c) * position / (radii * vec2(aspect, 1.0));
  // The slanted lobes broaden and narrow softly along the contour.
  float angle = atan(point.y, point.x + 0.00001);
  float outline = 1.0 + curvature * (0.43 * cos(2.0 * angle + 0.8)
                    + 0.62 * sin(3.0 * angle - 0.8) + 0.25 * cos(5.0 * angle));
  float radius = length(point) / outline;
  float inside = 1.0 - smoothstep(0.989, 1.005, radius);
  float depth = sqrt(max(0.0, 1.0 - radius * radius));
  vec3 normal = normalize(vec3(point * 0.82 / outline, depth + 0.001));
  float fresnel = pow(1.0 - max(normal.z, 0.0), 2.0);
  // Wide reflected pools and tight glints sit on different parts of the rim.
  float azimuth = angle + tilt + lightTurn;
  float cyanLight = pow(max(0.0, cos(azimuth - 2.36)), 6.0);
  float violetLight = pow(max(0.0, cos(azimuth + 0.57)), 5.0);
  float blueLight = pow(max(0.0, cos(azimuth - 0.48)), 7.0);
  float borderFocus = darkGlassHighlight(radius - 0.948, 0.092);
  float spill = darkGlassHighlight(radius - 1.012, 0.064);
  float cornerGlint = pow(max(0.0, cos(azimuth - 2.15)), 21.0)
                    * darkGlassHighlight(radius - 0.978, 0.025);
  float fineRim = darkGlassHighlight(radius - 0.997, 0.013);
  float shadow = inside * 0.085 * (0.45 + depth * 0.55);
  float cyan = cyanLight * (0.23 * borderFocus + 0.11 * spill + 0.14 * fineRim);
  float violet = violetLight * (0.24 * borderFocus + 0.14 * spill + 0.16 * fineRim);
  float blue = blueLight * (0.19 * borderFocus + 0.1 * spill);
  float glint = 0.32 * cornerGlint + 0.055 * inside * fresnel;
  float alpha = (shadow + cyan + violet + blue + glint) * intensity;
  vec3 sum = shadow * vec3(0.075, 0.12, 0.27)
          + cyan * vec3(0.16, 0.7, 0.99)
          + violet * vec3(0.70, 0.37, 1.0)
          + blue * vec3(0.20, 0.43, 0.99)
          + glint * vec3(0.64, 0.86, 1.0);
  return vec4(sum / max(0.0001, shadow + cyan + violet + blue + glint), min(alpha, 0.72));
}

vec4 darkGlassOver(vec4 top, vec4 bottom) {
  float alpha = top.a + bottom.a * (1.0 - top.a);
  return vec4((top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a)) / max(alpha, 0.0001), alpha);
}

vec4 darkOptics(vec2 uv, float aspect) {
  // The two upper lenses continue past the frame, and a shallow diagonal lens
  // crosses the lower workspace. The small lens adds a contact reflection.
  vec4 crown = darkGlassVolume(uv, aspect, vec2(0.29, 0.99), vec2(0.27, 0.25), 0.27, 0.085, 3.60, 0.89);
  vec4 shoulder = darkGlassVolume(uv, aspect, vec2(0.74, 0.91), vec2(0.29, 0.24), -0.32, 0.105, 0.53, 0.83);
  vec4 workspace = darkGlassVolume(uv, aspect, vec2(0.63, 0.29), vec2(0.43, 0.235), 0.33, 0.12, 0.03, 1.0);
  vec4 corner = darkGlassVolume(uv, aspect, vec2(0.28, 0.15), vec2(0.24, 0.15), -0.24, 0.08, -0.4, 0.57);
  return darkGlassOver(corner, darkGlassOver(workspace, darkGlassOver(shoulder, crown)));
}
`;
