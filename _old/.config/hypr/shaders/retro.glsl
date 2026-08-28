#version 300 es
precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

const float CURVATURE = 0.01;

void main() {
    vec2 uv = v_texcoord;
    vec2 centered = uv * 2.0 - 1.0;
    centered *= 1.0 + CURVATURE * dot(centered, centered);
    uv = centered * 0.5 + 0.5;

    fragColor = texture(tex, uv);
}

