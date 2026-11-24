#version 440

layout(location = 0) in vec2 position;
layout(location = 1) in vec2 cornerDistance;
layout(location = 0) out vec2 distanceFromCorner;

layout(std140, binding = 0) uniform Outline {
    mat4 matrix;
    vec2 reach;
} outline;

void main()
{
    distanceFromCorner = cornerDistance;
    gl_Position = outline.matrix * vec4(position, 0.0, 1.0);
}
