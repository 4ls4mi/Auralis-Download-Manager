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
    vec4 lighting;
    vec4 trackStart;
    vec4 trackEnd;
    vec4 trackUpper;
    vec4 trackLower;
    vec4 trackEdge;
    float amount;
    float phase;
    float flow;
    float contour;
    float motionKind;
    float optic;
} state;

const float tau = 6.28318530718;

vec4 layer(vec4 below, vec3 light, float alpha)
{
    alpha = clamp(alpha, 0.0, 1.0);
    return vec4(light * alpha, alpha) + below * (1.0 - alpha);
}

// Qt supplies ShaderEffect colors with premultiplied alpha.
vec4 over(vec4 below, vec4 paint)
{
    return paint + below * (1.0 - paint.a);
}

float band(float distance)
{
    return exp(-distance * distance);
}

vec4 glassFinish(vec4 liquid, vec4 glass, float u, float y, float ribs, vec3 pigment, vec3 light)
{
    vec3 dark = mix(vec3(0.009, 0.017, 0.030), pigment, 0.12);
    if (state.optic == 5.0) {
        float sweep = band((u - 0.49 + 0.27 * y) * 3.7);
        vec3 satin = mix(pigment, vec3(0.94, 0.98, 1.0), 0.53);
        return layer(liquid, satin, 0.67 * sweep * (0.86 - 0.25 * y));
    }
    if (state.optic == 6.0) {
        float cell = u * 6.0;
        float angle = mod(floor(cell), 2.0) == 0.0 ? y : -y;
        float plane = fract(cell) - (0.50 + 0.41 * angle);
        liquid = layer(liquid, plane > 0.0 ? light : dark, plane > 0.0 ? 0.46 : 0.57);
        return layer(liquid, light, 0.47 * band(plane * 36.0));
    }
    if (state.optic == 7.0) {
        float leading = band((u - 0.22 - 0.28 * y) * 5.2) * (1.0 - u);
        float trailing = band((u - 0.78 + 0.29 * y) * 5.2) * u;
        liquid = layer(liquid, dark, 0.53 * band((u - 0.52) * 2.2));
        liquid = layer(liquid, mix(state.liquidStart.rgb, light, 0.36), 0.88 * leading);
        return layer(liquid, mix(state.liquidEnd.rgb, light, 0.34), 0.88 * trailing);
    }
    if (state.optic == 8.0) {
        float leftGlint = band((u - 0.08) * 29.0) * band((y + 0.68) * 7.5);
        float rightGlint = band((u - 0.93) * 31.0) * band((y - 0.71) * 8.0);
        liquid = layer(liquid, dark, 0.58 * band(y * 1.25));
        return layer(liquid, mix(light, vec3(0.96, 0.99, 1.0), 0.72), 0.97 * max(leftGlint, rightGlint));
    }
    if (state.optic == 9.0) {
        float lens = fract(u * ribs + 0.18 * y * y);
        liquid = layer(liquid, dark, 0.66 * band((lens - 0.72) * 4.5));
        return layer(liquid, light, 0.82 * band((lens - 0.34) * 9.0) * (0.85 - 0.22 * y));
    }
    if (state.optic == 10.0) {
        vec3 film = 0.5 + 0.5 * cos(tau * (u * 1.17 + vec3(0.07, 0.40, 0.74)));
        float edge = band((abs(y) - 0.88) * 12.3);
        return layer(liquid, mix(pigment, film, 0.59), 0.88 * edge);
    }
    if (state.optic == 11.0) {
        float center = band(y * 2.35) * (0.55 + 0.45 * band((u - 0.53) * 2.45));
        liquid = layer(liquid, dark, 0.70 * smoothstep(0.18, 0.98, abs(y)));
        return layer(liquid, mix(pigment, light, 0.62), 0.92 * center);
    }
    // Edge-lit glass concentrates light at the profile and leaves the center clear.
    liquid = layer(glass, dark, 0.39 + 0.19 * abs(y));
    return layer(liquid, light, 0.92 * band((abs(y) - 0.84) * 14.8));
}

float sprayAdvance(float life)
{
    return life * (1.18 - 0.18 * life);
}

float sprayDot(vec2 point, vec2 radius)
{
    vec2 scaled = point / radius;
    return 1.0 - smoothstep(0.38, 1.0, dot(scaled, scaled));
}

vec4 waterSpray(vec4 glass, vec2 point, float halfHeight, float height, float reach,
                float phase, vec3 glow, vec3 highlight)
{
    int particles = reach >= 46.0 ? 7 : 3;
    for (int index = 0; index < 7; ++index) {
        if (index >= particles)
            break;
        float seed = float(index);
        float life = fract(2.0 * phase / tau + seed * 0.381966);
        float side = mod(seed, 2.0) == 0.0 ? -1.0 : 1.0;
        float distance = reach * (index == 0 ? 1.0 : 0.39 + 0.60 * fract(seed * 0.754878));
        float firstImpact = 0.235 + 0.112 * fract((seed + 1.0) * 0.618034);
        float reflectedTime = life / firstImpact;
        float wall = side * 0.87;
        float travelX = 2.0 + distance * sprayAdvance(life);
        float travelY = wall * (1.0 - abs(mod(reflectedTime + 1.0, 4.0) - 2.0));
        float fade = smoothstep(0.0, 0.07, life) * (1.0 - smoothstep(0.67, 1.0, life));
        float size = (1.14 - life * 0.38) * (0.75 + 0.39 * fract((seed + 1.0) * 0.56984));
        vec2 radius = size * vec2(max(1.3, height * 0.085), max(1.0, height * 0.049));
        if (abs(point.x - travelX) < radius.x * 1.62) {
            vec2 delta = vec2(point.x - travelX, (point.y - travelY) * halfHeight);
            glass = layer(glass, glow, sprayDot(delta, radius * vec2(1.62, 1.4)) * fade * 0.58);
            glass = layer(glass, highlight, sprayDot(delta, radius) * fade * 0.91);
        }

        // Reflect at both walls and leave a short ripple and two smaller droplets.
        float hit = floor((reflectedTime + 1.0) * 0.5);
        float contact = (hit * 2.0 - 1.0) * firstImpact;
        float age = (life - contact) / 0.21;
        if (hit < 1.0 || age < 0.0 || age >= 1.0)
            continue;
        float hitX = 2.0 + distance * sprayAdvance(contact);
        if (abs(point.x - hitX) > height * 0.48 + 2.5)
            continue;
        float hitWall = hit < 2.0 ? wall : -wall;
        float impact = (1.0 - age) * (1.0 - 0.62 * contact);
        vec2 offset = vec2(point.x - hitX, (point.y - hitWall) * halfHeight * 2.3);
        float ringRadius = 1.1 + age * height * 0.37;
        float ripple = (1.0 - smoothstep(0.1, 1.3, abs(length(offset) - ringRadius))) * impact;
        glass = layer(glass, glow, ripple * 0.66);
        float lift = 0.86 * 4.0 * age * (1.0 - age);
        float fragmentY = hitWall * (1.0 - lift);
        vec2 first = vec2(point.x - hitX - age * height * 0.38, (point.y - fragmentY) * halfHeight);
        vec2 second = vec2(point.x - hitX + age * height * 0.23,
                           (point.y - hitWall * (1.0 - lift * 0.62)) * halfHeight);
        vec2 fragmentRadius = vec2(max(1.15, height * 0.054), max(0.85, height * 0.037));
        glass = layer(glass, highlight, impact * (0.83 * sprayDot(first, fragmentRadius)
                                               + 0.58 * sprayDot(second, fragmentRadius * 0.8)));
    }
    return glass;
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
    } else if (contourPosition > 3.5) {
        // Ice leaves more of the left cap intact and has an asymmetric bevel.
        halfHeight *= 1.0 - endRatio * (x < 0.5 ? 0.38 : 0.63);
        offset += 0.12 * endRatio * (x < 0.5 ? -1.0 : 1.0);
        slope = 0.17 * endRatio * (x < 0.5 ? -1.0 : 1.0);
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

    float haloStrength = state.lighting.x;
    float reflectivity = state.lighting.y;
    float shading = state.lighting.z;
    vec3 spectral = mix(state.liquidStart.rgb, state.liquidEnd.rgb,
                        0.5 + 0.5 * sin(tau * (1.2 * x + 0.23 * curvedY)));
    vec3 glassLight = mix(spectral, vec3(0.90, 0.96, 1.0), 0.40);
    vec4 glass = layer(vec4(0.0), state.glassTint.rgb, 0.065 + 0.09 * shading + 0.24 * rim);
    glass = layer(glass, spectral, reflectivity * (0.25 * rim + 0.16 * bounce));
    glass = layer(glass, glassLight, specular * glint * 0.68 * reflectivity);
    vec3 silver = mix(spectral, vec3(0.90, 0.96, 1.0), 0.80);
    if (state.optic == 1.0) {
        glass = layer(glass, glassLight, 0.22 * depth + 0.12 * band((curvedY + 0.35) * 1.95));
    } else if (state.optic == 2.0) {
        float chromeLines = band((curvedY + 0.71) * 18.0) + 0.60 * band((curvedY - 0.72) * 15.0);
        glass = layer(glass, silver, 0.58 * chromeLines);
    } else if (state.optic == 3.0) {
        glass = layer(glass, spectral, 0.43 * band((curvedY - 0.78) * 6.0));
    } else if (state.optic == 4.0) {
        glass = layer(glass, vec3(0.014, 0.018, 0.034), 0.31 * depth);
    }

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
                    0.38 - 0.24 * shading + (0.19 + 0.22 * shading) * shoulder);
    vec3 luminous = clamp(emitter * 1.10, 0.0, 1.0);
    vec3 reflection = mix(emitter, vec3(0.92, 0.98, 1.0), 0.28);
    float upperDistance = (curvedY + 0.73) * 5.7;
    float lowerDistance = (curvedY - 0.80) * 6.2;
    float upperRidge = exp(-(upperDistance * upperDistance));
    float lowerRidge = exp(-(lowerDistance * lowerDistance));
    vec4 liquid = layer(glass, body, 0.96);
    liquid = layer(liquid, luminous, 0.14 * haloStrength + 0.37 * shoulder + 0.30 * bounce);
    liquid = layer(liquid, spectral, 0.13 * rim);
    liquid = layer(liquid, luminous, (0.46 + 0.19 * shading) * upperRidge + (0.38 + 0.28 * shading) * lowerRidge);
    liquid = layer(liquid, reflection, reflectivity * (0.91 * specular * glint + 0.20 * bounce));
    liquid = layer(liquid, body * 0.44, 0.48 * shading * band((curvedY - 0.23) * 2.75));
    if (state.optic == 1.0) {
        // A wide, soft highlight scatters through the body.
        vec3 frost = mix(emitter, vec3(0.91, 0.97, 1.0), 0.64);
        liquid = layer(liquid, frost, 0.21 + 0.63 * band((curvedY + 0.19) * 1.53));
    } else if (state.optic == 2.0) {
        vec3 chrome = mix(reflection, vec3(0.96, 0.99, 1.0), 0.71);
        liquid = layer(liquid, body * 0.30, 0.62 * band((curvedY - 0.07) * 2.4));
        float shoulderLine = band((curvedY + 0.55) * 18.0);
        float rimLine = band((curvedY + 0.76) * 23.0);
        liquid = layer(liquid, chrome, 0.88 * shoulderLine + 0.91 * rimLine);
        liquid = layer(liquid, reflection, 0.54 * band((curvedY - 0.72) * 17.0));
    } else if (state.optic == 3.0) {
        liquid = layer(liquid, body * 0.26, 0.94 * (1.0 - smoothstep(-0.15, 0.76, curvedY)));
        liquid = layer(liquid, luminous, 0.86 * band((curvedY - 0.73) * 3.8));
        liquid = layer(liquid, reflection, 0.69 * band((curvedY - 0.88) * 13.0));
    } else if (state.optic == 4.0) {
        vec3 smoke = mix(vec3(0.014, 0.018, 0.033), emitter, 0.13);
        liquid = layer(glass, smoke, 0.71 + 0.16 * shoulder);
        liquid = layer(liquid, emitter, 0.62 * band((abs(curvedY) - 0.86) * 10.0));
        liquid = layer(liquid, reflection, 0.32 * specular * glint);
    }
    if (state.optic >= 5.0 && filled > 0.0) {
        float u = clamp(x / max(fillEdge, 0.025), 0.0, 1.0);
        float ribs = clamp(fillEdge * width / 9.0, 3.0, 22.0);
        liquid = glassFinish(liquid, glass, u, curvedY, ribs, emitter, reflection);
    }
    float movingHighlight = state.optic == 4.0 ? 0.66 : state.optic == 1.0 ? 0.79 : 1.0;
    float ripple = x * 3.0 - state.phase / tau;
    float lightWave = pow(0.5 + 0.5 * sin(tau * ripple + curvedY * 2.2), 12.0);
    float current = state.flow * lightWave * (0.25 + 0.75 * depth);
    if (water) {
        // Narrow streams travel at different speeds inside the cylindrical profile.
        float surge = 0.5 + 0.5 * cos(tau * 3.0 * x - 2.0 * phase);
        float turbulence = sin(tau * 9.0 * x - phase * 2.0);
        float upperStream = band((curvedY + 0.24 + 0.16 * turbulence) * 5.6);
        float lowerStream = band((curvedY - 0.40 - 0.14 * cos(tau * 7.0 * x - phase * 3.0)) * 7.1);
        float foam = pow(max(0.0, sin(tau * 19.0 * x - phase * 4.0 + curvedY * 6.0)), 10.0);
        float inlet = band((pixel.x - 2.0) / max(3.0, height * 0.77));
        liquid = layer(liquid, body * 0.64, 0.35 * depth * (1.0 - upperStream));
        liquid = layer(liquid, reflection, movingHighlight * ((0.21 + 0.51 * surge) * upperStream + 0.41 * lowerStream));
        liquid = layer(liquid, mix(reflection, vec3(0.94, 0.99, 1.0), 0.52),
                       foam * (0.37 * upperStream + 0.22 * lowerStream) + (0.28 + 0.48 * surge) * inlet * depth);
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
    if (state.lighting.w > 0.5) {
        // Intersecting highlights refract through the liquid volume.
        float longitudinal = pixel.x / max(6.0, 0.74 * height);
        float drift = (water ? 2.0 : 1.0) * phase;
        float first = band((curvedY + 0.09 + 0.50 * sin(longitudinal - drift)) * 13.0);
        float second = band((curvedY - 0.17 + 0.44 * cos(longitudinal * 0.79 + drift)) * 10.5);
        liquid = layer(liquid, reflection, depth * (0.66 * first + 0.42 * second));
    }
    float meniscus = exp(-abs(frontDistance) / max(1.2, height * 0.13));
    liquid = layer(liquid, reflection, meniscus * 0.71 * depth);

    if (state.trackStart.a > 0.0 && filled < 1.0) {
        glass = over(glass, mix(state.trackStart, state.trackEnd, x));
        glass = over(glass, state.trackUpper * max(-curvedY, 0.0));
        glass = over(glass, state.trackLower * max(curvedY, 0.0));
        glass = over(glass, state.trackEdge * rim);
    }

    // Keep spray inside both the glass silhouette and the unfilled region.
    float remainder = (1.0 - fillEdge) * width;
    if (water && state.flow > 0.0 && fillEdge > 0.001 && remainder >= 8.0 && height >= 8.0
        && coverage > 0.0 && filled < 1.0 && pixel.x <= size.x - 2.0) {
        glass = waterSpray(glass, vec2((pixel.x - 2.0) - fillEdge * width, curvedY),
                          max(1.0, halfHeight * height), height, remainder - 3.0,
                          phase, luminous, reflection);
    }
    float sideDistance = max(2.0 - pixel.x, pixel.x - size.x + 2.0);
    vec4 color = mix(glass, liquid, filled) * coverage;
    float lightDistance = max(0.0, max(max(rimDistance, sideDistance), frontDistance));
    float glowReach = state.padding + 1.0;
    float nearGlow = exp(-pow(lightDistance / (glowReach * 0.37), 2.0));
    float wideGlow = 1.0 - smoothstep(0.0, glowReach, lightDistance);
    float halo = haloStrength * (0.33 * nearGlow + 0.15 * wideGlow)
               * step(0.001, fillEdge) * (1.0 - filled * coverage);
    fragColor = (color + vec4(luminous * halo, halo) * (1.0 - color.a)) * state.qt_Opacity;
}
