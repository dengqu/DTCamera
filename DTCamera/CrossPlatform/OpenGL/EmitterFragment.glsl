varying highp vec3 v_pColorOffset;
varying highp float v_Growth;
varying highp float v_Decay;

uniform highp float u_Time;
uniform highp vec3 u_eColorStart;
uniform highp vec3 u_eColorEnd;
uniform sampler2D u_Texture;

void main(void)
{
    highp vec4 texture = texture2D(u_Texture, gl_PointCoord);
    highp vec4 color = vec4(1.0);
    
    if(u_Time < v_Growth)
    {
        color.rgb = u_eColorStart;
    }
    else
    {
        highp float time = (u_Time - v_Growth) / v_Decay;

        color.rgb = mix(u_eColorStart, u_eColorEnd, time);
    }

    color.rgb += v_pColorOffset;
    color.rgb = clamp(color.rgb, vec3(0.0), vec3(1.0));
    
    gl_FragColor = texture * color;
}
