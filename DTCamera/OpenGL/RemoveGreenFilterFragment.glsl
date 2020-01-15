precision mediump float;

uniform sampler2D u_texture;

varying mediump vec2 v_texcoord;

void main(void) {
    vec4 color = texture2D(u_texture, v_texcoord);
    gl_FragColor.bgra = vec4(color.b, 0.0 * color.g, color.r, color.a);
}
