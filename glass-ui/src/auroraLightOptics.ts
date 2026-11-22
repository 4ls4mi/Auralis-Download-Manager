// A small set of overlapping glass slabs, expressed in window coordinates.
// Surface colors are composited in straight alpha so the live acrylic remains visible.
export const auroraLightOpticsGLSL = `
float iceEdgeDistance(vec2 point, vec2 start, vec2 end) {
    vec2 edge = end - start;
    vec2 relative = point - start;
    return (edge.x * relative.y - edge.y * relative.x) / length(edge);
}

vec4 iceOver(vec4 under, vec4 over) {
    float alpha = over.a + under.a * (1.0 - over.a);
    vec3 color = over.rgb * over.a + under.rgb * under.a * (1.0 - over.a);
    return vec4(color / max(0.0001, alpha), alpha);
}

vec4 iceSlab(
    vec2 point, vec2 a, vec2 b, vec2 c, vec2 d,
    vec3 tint, float opacity, float thickness, float glintAt
) {
    float front = iceEdgeDistance(point, a, b);
    float farEnd = iceEdgeDistance(point, b, c);
    float back = iceEdgeDistance(point, c, d);
    float nearEnd = iceEdgeDistance(point, d, a);
    float edge = min(min(front, back), min(farEnd, nearEnd));
    float coverage = smoothstep(-0.0014, 0.0014, edge);
    if (coverage <= 0.0) return vec4(0.0);

    vec2 axis = b - a;
    float along = dot(point - a, axis) / dot(axis, axis);
    float face = smoothstep(0.0, 1.0, front / max(0.001, front + back));
    float reflection = 1.0 - smoothstep(0.08, 0.49, abs(along - glintAt));
    float cut = 1.0 - smoothstep(thickness * 0.65, thickness * 1.24, edge);
    float rim = 1.0 - smoothstep(0.0010, 0.0033, edge);

    // Light catches the near lip. The opposite cut shifts toward cooler blue.
    float litSide = 1.0 - smoothstep(edge + 0.001, edge + thickness, min(front, nearEnd));
    vec3 faceColor = mix(tint, mix(tint, vec3(0.98, 1.0, 1.0), 0.55), face);
    vec3 cutColor = mix(vec3(0.36, 0.67, 0.83), vec3(0.94, 0.99, 1.0), litSide);
    vec3 color = mix(faceColor, cutColor, cut * 0.73);
    color = mix(color, vec3(0.95, 1.0, 1.0), rim * reflection * 0.87);
    float alpha = opacity * (0.47 + 0.53 * face)
        + cut * (0.12 + 0.12 * litSide)
        + rim * (0.09 + 0.30 * reflection);
    return vec4(color, coverage * min(alpha, 0.68));
}

vec4 lightOptics(vec2 uv, float aspect) {
    vec2 scale = vec2(aspect, 1.0);
    vec2 point = uv * scale;
    vec4 result = vec4(0.0);

    // The oblique rear face cuts across the tops of the rising panes.
    result = iceOver(result, iceSlab(
        point, vec2(-0.16, 0.76) * scale, vec2(0.43, 0.63) * scale,
        vec2(0.79, 1.12) * scale, vec2(-0.19, 1.21) * scale,
        vec3(0.59, 0.83, 0.97), 0.14, 0.009, 0.60));
    result = iceOver(result, iceSlab(
        point, vec2(-0.30, 0.14) * scale, vec2(0.52, 1.23) * scale,
        vec2(0.24, 1.31) * scale, vec2(-0.48, 0.46) * scale,
        vec3(0.65, 0.88, 0.99), 0.17, 0.009, 0.52));
    result = iceOver(result, iceSlab(
        point, vec2(-0.10, -0.20) * scale, vec2(1.19, 0.96) * scale,
        vec2(0.99, 1.25) * scale, vec2(-0.31, 0.00) * scale,
        vec3(0.71, 0.90, 1.0), 0.24, 0.013, 0.46));
    result = iceOver(result, iceSlab(
        point, vec2(0.38, -0.22) * scale, vec2(1.20, 0.72) * scale,
        vec2(1.10, 0.97) * scale, vec2(0.14, -0.08) * scale,
        vec3(0.48, 0.75, 0.92), 0.23, 0.017, 0.76));
    result = iceOver(result, iceSlab(
        point, vec2(0.74, -0.16) * scale, vec2(1.22, 0.26) * scale,
        vec2(1.13, 0.50) * scale, vec2(0.56, -0.03) * scale,
        vec3(0.80, 0.95, 1.0), 0.24, 0.016, 0.39));
    return result;
}
`;
