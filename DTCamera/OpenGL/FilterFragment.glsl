precision mediump float;

uniform sampler2D u_texture;
uniform sampler2D u_text_texture;
uniform float u_text_progress;

varying mediump vec2 v_texcoord;

void main(void) {
    vec4 color = texture2D(u_texture, v_texcoord);
    vec4 textColor = texture2D(u_text_texture, v_texcoord);
    float r = textColor.r * textColor.a * u_text_progress + (1.0 - textColor.a * u_text_progress) * color.r;
    float g = textColor.g * textColor.a * u_text_progress + (1.0 - textColor.a * u_text_progress) * (color.g * 0.0);
    float b = textColor.b * textColor.a * u_text_progress + (1.0 - textColor.a * u_text_progress) * color.b;
    gl_FragColor.bgra = vec4(b, g, r, color.a);
}
