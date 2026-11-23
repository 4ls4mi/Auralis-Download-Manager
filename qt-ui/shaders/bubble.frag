#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform ProgressUniforms {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 surfaceSize;
    float padding;
    vec4 liquidStart;
    vec4 liquidEnd;
    vec4 glassTint;
    float amount;
    float phase;
    float polish;
    float flow;
    float contour;
    float motionKind;
} state;

const float tau = 6.28318530718;

vec4 layer(vec4 below, vec3 light, float alpha)
{
    alpha = clamp(alpha, 0.0, 1.0);
    return vec4(light * alpha, alpha) + below * (1.0 - alpha);
}

float band(float distance)
{
    return exp(-distance * distance);
}

void main()
{
    vec2 size = max(state.surfaceSize, vec2(1.0));
    vec2 pixel = qt_TexCoord0 * (size + 2.0 * state.padding) - state.padding;
    float width = max(1.0, size.x - 4.0);
    float height = max(1.0, size.y - 3.0);
    float x = clamp((pixel.x - 2.0) / width, 0.0, 1.0);
    float cap = min(width * 0.18, height * 0.61);
    float contourPosition = state.contour;
    float endDistance = max(0.0, max(cap - x * width, x * width - (width - cap)));
    float endRatio = endDistance / max(1.0, cap);
    float wave = cos(tau * (3.3 * x - 0.13));
    float slope = 0.0;
    float offset = (pixel.y - size.y * 0.5) / height;
    float halfHeight = 0.46;

    if (contourPosition < 1.5) {
        // An elliptical cap keeps the rounded and lobed vessels smooth.
        float capProfile = sqrt(max(0.0, 1.0 - endRatio * endRatio));
        halfHeight *= capProfile;
        if (contourPosition > 0.5) {
            halfHeight = (0.39 + 0.082 * wave) * capProfile;
            offset -= 0.025 * sin(tau * 2.0 * x);
            slope = 0.14 * sin(tau * (3.3 * x - 0.13));
        }
    } else if (contourPosition < 2.5) {
        // Prism-like caps have a straight chamfer. The square vessel keeps its full height.
        halfHeight *= 1.0 - endRatio * 0.74;
        slope = 0.20 * endRatio * (x < 0.5 ? -1.0 : 1.0);
    }
    float rimDistance = (abs(offset) - halfHeight) * height;
    float coverage = 1.0 - smoothstep(-0.65, 0.65, rimDistance);
    coverage *= smoothstep(0.5, 2.0, pixel.x)
              * (1.0 - smoothstep(size.x - 2.0, size.x - 0.5, pixel.x));

    // A circular thickness profile provides optical normals across the glass.
    float curvedY = clamp(offset / max(halfHeight, 0.001), -1.0, 1.0);
    float depth = sqrt(max(0.0, 1.0 - curvedY * curvedY));
    vec3 normal = normalize(vec3(slope, -curvedY, depth));
    float rim = pow(1.0 - depth, 2.25);
    float specular = pow(max(0.0, dot(normal, normalize(vec3(-0.25, 0.65, 0.83)))), 34.0);
    float bounce = pow(max(0.0, dot(normal, normalize(vec3(0.36, -0.81, 0.62)))), 23.0);
    float glint = contourPosition > 0.5 && contourPosition < 1.5
        ? 0.35 + 0.65 * pow(max(0.0, cos(tau * (3.3 * x - 0.17))), 4.0)
        : 0.51 + 0.49 * (1.0 - x);

    vec3 spectral = mix(vec3(0.34, 0.91, 1.0), vec3(0.95, 0.39, 0.86),
                        0.5 + 0.5 * sin(tau * (1.2 * x + 0.23 * curvedY)));
    vec4 glass = layer(vec4(0.0), state.glassTint.rgb, 0.075 + 0.24 * rim);
    glass = layer(glass, spectral, 0.27 * rim + 0.19 * bounce);
    glass = layer(glass, vec3(0.84, 0.93, 1.0), specular * glint * 0.62);

    float fillEdge = clamp(state.amount, 0.0, 1.0);
    bool water = state.motionKind > 0.5 && state.motionKind < 1.5;
    bool jelly = state.motionKind > 1.5;
    float phase = state.flow * state.phase;
    float frontSpan = min(height * 0.36, width * min(fillEdge, 1.0 - fillEdge));
    float curvature = frontSpan * (0.54 * (depth - 0.62)
                      + state.flow * 0.55 * sin(state.phase + curvedY * 2.6));
    if (water)
        curvature = frontSpan * (0.46 * (depth - 0.60) + state.flow * 0.31 * sin(phase * 2.0 + curvedY * 4.5));
    if (jelly)
        curvature = frontSpan * (0.98 * depth - 0.51 + state.flow * 0.34 * sin(phase - curvedY * 2.4));
    float frontDistance = (x - fillEdge) * width - curvature;
    float filled = 1.0 - smoothstep(-0.8, 0.8, frontDistance);
    filled *= step(0.001, fillEdge);
    filled = max(filled, step(0.999, fillEdge));

    vec3 emitter = mix(state.liquidStart.rgb, state.liquidEnd.rgb,
                       clamp(x / max(fillEdge, 0.28), 0.0, 1.0));
    float shoulder = pow(abs(curvedY), 1.7);
    vec3 body = mix(vec3(0.011, 0.020, 0.050), emitter,
                    mix(0.35, 0.21, state.polish) + 0.35 * shoulder);
    vec3 luminous = clamp(emitter * 1.10, 0.0, 1.0);
    vec3 reflection = mix(emitter, vec3(0.92, 0.98, 1.0), 0.28);
    float upperDistance = (curvedY + 0.73) * 5.7;
    float lowerDistance = (curvedY - 0.80) * 6.2;
    float upperRidge = exp(-(upperDistance * upperDistance));
    float lowerRidge = exp(-(lowerDistance * lowerDistance));
    vec4 liquid = layer(glass, body, 0.96);
    liquid = layer(liquid, luminous, 0.19 + 0.42 * shoulder + 0.33 * bounce);
    liquid = layer(liquid, spectral, 0.16 * rim);
    liquid = layer(liquid, luminous, 0.64 * upperRidge + 0.69 * lowerRidge);
    liquid = layer(liquid, reflection, 0.86 * specular * glint + 0.22 * bounce);
    float ripple = x * 3.0 - state.phase / tau;
    float lightWave = pow(0.5 + 0.5 * sin(tau * ripple + curvedY * 2.2), 12.0);
    float current = state.flow * lightWave * (0.25 + 0.75 * depth);
    if (water) {
        // Narrow streams travel at different speeds inside the cylindrical profile.
        float surge = 0.5 + 0.5 * cos(tau * 3.0 * x - phase);
        float turbulence = sin(tau * 9.0 * x - phase * 2.0);
        float upperStream = band((curvedY + 0.24 + 0.16 * turbulence) * 5.6);
        float lowerStream = band((curvedY - 0.40 - 0.14 * cos(tau * 7.0 * x - phase * 3.0)) * 7.1);
        float foam = pow(max(0.0, sin(tau * 19.0 * x - phase * 4.0 + curvedY * 6.0)), 10.0);
        float inlet = band((pixel.x - 2.0) / max(3.0, height * 0.55));
        liquid = layer(liquid, body * 0.64, 0.35 * depth * (1.0 - upperStream));
        liquid = layer(liquid, reflection, (0.21 + 0.51 * surge) * upperStream + 0.41 * lowerStream);
        liquid = layer(liquid, mix(reflection, vec3(0.94, 0.99, 1.0), 0.52),
                       foam * (0.37 * upperStream + 0.22 * lowerStream) + 0.37 * inlet * depth);
    } else if (jelly) {
        // A rounded fold compresses and stretches as it moves through the thicker fill.
        float fold = sin(tau * 1.9 * x - phase + 0.38 * sin(phase));
        float slowRidge = band((curvedY + 0.45 + 0.28 * fold) * 4.3);
        float lowerFold = band((curvedY - 0.51 + 0.20 * fold) * 3.0);
        vec3 jellyBody = mix(body, emitter, 0.36 + 0.14 * fold);
        liquid = layer(liquid, jellyBody, 0.54 * depth);
        liquid = layer(liquid, reflection, 0.61 * slowRidge + 0.29 * lowerFold);
        liquid = layer(liquid, body * 0.63, 0.28 * depth * band((curvedY - 0.14 + 0.18 * fold) * 3.4));
    } else {
        liquid = layer(liquid, luminous, current * (0.22 + 0.35 * shoulder));
        liquid = layer(liquid, reflection, current * (0.12 + 0.24 * bounce));
    }
    float meniscus = exp(-abs(frontDistance) / max(1.2, height * 0.13));
    liquid = layer(liquid, reflection, meniscus * 0.71 * depth);

    float sideDistance = max(2.0 - pixel.x, pixel.x - size.x + 2.0);
    vec4 color = mix(glass, liquid, filled) * coverage;
    float lightDistance = max(0.0, max(max(rimDistance, sideDistance), frontDistance));
    float glowReach = state.padding + 1.0;
    float nearGlow = exp(-pow(lightDistance / (glowReach * 0.37), 2.0));
    float wideGlow = 1.0 - smoothstep(0.0, glowReach, lightDistance);
    float halo = (0.34 * nearGlow + 0.17 * wideGlow) * step(0.001, fillEdge) * (1.0 - filled * coverage);
    fragColor = (color + vec4(luminous * halo, halo) * (1.0 - color.a)) * state.qt_Opacity;
}
