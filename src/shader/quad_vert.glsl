#version 460 core
layout (location = 0) in vec4 aVert;

out vec2 TexCoord;

void main() {
    TexCoord = aVert.zw;
    gl_Position = vec4(aVert.xy, 0., 1.);
}
