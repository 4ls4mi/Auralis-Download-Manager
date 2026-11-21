/** Shaded liquid cross-section. Progress and track clipping are handled by the caller. */
export const liquidMaterialFragment = `
precision mediump float;
uniform vec2 viewport;
uniform float seconds;
uniform float material;
uniform vec3 colorA;
uniform vec3 colorB;
uniform vec3 colorC;
float band(float x,float c,float w){float d=(x-c)/w;return exp(-d*d);}
void main(){
 vec2 uv=gl_FragCoord.xy/viewport;float x=uv.x,y=1.0-uv.y;
 vec3 chosen=mix(mix(colorA,colorB,smoothstep(0.0,.5,x)),colorC,smoothstep(.5,1.0,x));
 float cross=clamp(1.0-pow(2.0*y-1.0,2.0),0.0,1.0),depth=sqrt(cross);
 float flowing=sin(x*32.0-seconds*2.1+sin(y*7.0+seconds*.7))*.5+.5;
 float crest=.18+.075*sin(x*19.0-seconds*1.5)+.025*sin(x*37.0+seconds*1.1);
 float broad=band(y,crest,material>1.5?.14:.085);
 float rim=band(y,.028,.028)+band(y,.965,.028)*.55;
 float inner=band(y,.39+.035*sin(x*12.0-seconds*1.6),.09)*(.35+.65*flowing);
 float light=material<.5?.72:material<1.5?.95:.58;
 vec3 body=chosen*(.31+.58*depth)+chosen*inner*.21;
 body=mix(body,vec3(1.0),clamp(broad*light*.55+rim*(material<1.5?.48:.36),0.0,.86));
 float refracted=band(y,.67+.08*sin(x*15.0-seconds*1.25),.055)*(.25+.75*flowing);
 body+=mix(chosen,vec3(1.0),.45)*refracted*.14;
 if(material>.5&&material<1.5){body+=vec3(.18)*band(y,.085,.012)+vec3(.13)*band(y,.90,.015);}
 if(material>1.5){body+=vec3(.24)*band(y,.21+.05*sin(x*4.0-seconds*.4),.12);}
 gl_FragColor=vec4(clamp(body,0.0,1.0),1.0);
}`;
