#version 440

layout(location = 0) in vec2 distanceFromCorner;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform Outline {
    mat4 matrix;
    vec2 reach;
} outline;

void main()
{
    vec2 corner = max(vec2(0.0), 1.0 - distanceFromCorner / outline.reach);
    float boundary = pow(corner.x, 3.05) + pow(corner.y, 3.05) - 1.0;
    float pixel = length(vec2(dFdx(boundary), dFdy(boundary)));
    float feather = 0.72 * max(pixel, 0.00001);
    float coverage = 1.0 - smoothstep(-feather, feather, boundary);
    fragColor = vec4(0.0, 0.0, 0.0, coverage);
}
