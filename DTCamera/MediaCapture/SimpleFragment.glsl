precision mediump float;

uniform sampler2D u_texture;
uniform vec4 u_color;

varying highp vec2 v_texcoord;

void main(void) {
    gl_FragColor = u_color * texture2D(u_texture, v_texcoord);
}
