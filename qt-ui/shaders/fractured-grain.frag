#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform GrainUniforms {
    mat4 qt_Matrix;
    float qt_Opacity;
    float grainStrength;
    vec2 surfaceSize;
} state;
layout(binding = 1) uniform sampler2D silhouetteMask;

void main()
{
    vec2 pixel = floor(qt_TexCoord0 * state.surfaceSize);
    vec3 seed = fract(pixel.xyx * 0.1031);
    seed += dot(seed, seed.yzx + 33.33);
    float grain = fract((seed.x + seed.y) * seed.z);
    float shade = step(0.5, grain);
    float alpha = texture(silhouetteMask, qt_TexCoord0).a
        * fract(grain * 2.0) * 0.39 * state.grainStrength * state.qt_Opacity;
    fragColor = vec4(vec3(shade * alpha), alpha);
}
