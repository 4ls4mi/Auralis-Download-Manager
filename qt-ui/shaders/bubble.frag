#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform BubbleUniforms {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 surfaceSize;
    vec4 liquidStart;
    vec4 liquidEnd;
    vec4 glassTint;
    float amount;
    float phase;
    float polish;
    float flow;
} state;

const float tau = 6.28318530718;

vec4 layer(vec4 below, vec3 light, float alpha)
{
    alpha = clamp(alpha, 0.0, 1.0);
    return vec4(light * alpha, alpha) + below * (1.0 - alpha);
}

void main()
{
    vec2 size = max(state.surfaceSize, vec2(1.0));
    vec2 pixel = qt_TexCoord0 * size;
    float width = max(1.0, size.x - 4.0);
    float height = max(1.0, size.y - 3.0);
    float x = clamp((pixel.x - 2.0) / width, 0.0, 1.0);
    float cap = min(width * 0.18, height * 0.61);

    // End caps are elliptical. The broad body has four gently connected lobes.
    float endDistance = max(0.0, max(cap - x * width, x * width - (width - cap)));
    float capProfile = sqrt(max(0.0, 1.0 - pow(endDistance / max(1.0, cap), 2.0)));
    float wave = cos(tau * (3.3 * x - 0.13));
    float centre = 0.025 * sin(tau * 2.0 * x);
    float halfHeight = (0.39 + 0.082 * wave) * capProfile;
    float offset = (pixel.y - size.y * 0.5) / height - centre;
    float coverage = 1.0 - smoothstep(-0.65, 0.65, (abs(offset) - halfHeight) * height);
    coverage *= smoothstep(0.5, 2.0, pixel.x)
              * (1.0 - smoothstep(size.x - 2.0, size.x - 0.5, pixel.x));

    // A circular thickness profile provides optical normals across the glass.
    float curvedY = clamp(offset / max(halfHeight, 0.001), -1.0, 1.0);
    float depth = sqrt(max(0.0, 1.0 - curvedY * curvedY));
    float slope = 0.14 * sin(tau * (3.3 * x - 0.13));
    vec3 normal = normalize(vec3(slope, -curvedY, depth));
    float rim = pow(1.0 - depth, 2.25);
    float specular = pow(max(0.0, dot(normal, normalize(vec3(-0.25, 0.65, 0.83)))), 34.0);
    float bounce = pow(max(0.0, dot(normal, normalize(vec3(0.36, -0.81, 0.62)))), 23.0);
    float glint = 0.35 + 0.65 * pow(max(0.0, cos(tau * (3.3 * x - 0.17))), 4.0);

    vec3 spectral = mix(vec3(0.34, 0.91, 1.0), vec3(0.95, 0.39, 0.86),
                        0.5 + 0.5 * sin(tau * (1.2 * x + 0.23 * curvedY)));
    vec4 glass = layer(vec4(0.0), state.glassTint.rgb, 0.035 + 0.22 * rim);
    glass = layer(glass, spectral, 0.32 * rim + 0.25 * bounce);
    glass = layer(glass, vec3(0.92, 0.98, 1.0), specular * glint * 0.74);

    float fillEdge = clamp(state.amount, 0.0, 1.0);
    float curvature = cap * (0.30 * (depth - 0.62)
                      + state.flow * 0.12 * sin(state.phase + curvedY * 2.6));
    float filled = 1.0 - smoothstep(-0.8, 0.8, (x - fillEdge) * width - curvature);
    filled *= step(0.001, fillEdge);
    filled = max(filled, step(0.999, fillEdge));

    vec3 pigment = mix(state.liquidStart.rgb, state.liquidEnd.rgb,
                       clamp(x / max(fillEdge, 0.28), 0.0, 1.0));
    float shadow = mix(0.75, 0.36, state.polish) + 0.45 * pow(abs(curvedY), 1.5);
    vec3 body = pigment * shadow + vec3(0.014, 0.03, 0.094);
    vec4 liquid = layer(glass, body, 0.89);
    liquid = layer(liquid, pigment * 1.17, 0.55 * bounce + 0.40 * rim);
    liquid = layer(liquid, spectral, 0.33 * rim + 0.22 * bounce);
    liquid = layer(liquid, vec3(0.96, 0.98, 1.0), 0.88 * specular * glint);
    float ripple = x * 3.0 - state.phase / tau;
    float lightWave = pow(0.5 + 0.5 * sin(tau * ripple + curvedY * 2.2), 12.0);
    float movingLight = state.flow * lightWave * depth * (0.14 + 0.25 * bounce);
    liquid = layer(liquid, mix(pigment, vec3(0.9, 0.97, 1.0), 0.48), movingLight);
    float meniscus = exp(-abs((x - fillEdge) * width - curvature) / max(1.2, height * 0.17));
    liquid = layer(liquid, mix(pigment, spectral, 0.30), meniscus * 0.52 * depth);

    fragColor = mix(glass, liquid, filled) * coverage * state.qt_Opacity;
}
