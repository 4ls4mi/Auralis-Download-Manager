// Pane renderer ported from the user-supplied Water Bubble 3.5.1 source.
// The progress ribbon is rendered separately at each indicator location.
export const frostVertex = `attribute vec2 position; void main(){ gl_Position=vec4(position,0.,1.); }`;
export const frostFragment = `
    precision highp float;
    uniform vec2 viewport;
    uniform vec3 themeTint;
    uniform float themeStrength;
    uniform float glassOpacity;
    uniform float seconds;
    uniform float progress;
    uniform float unknown;

    float sq(float x) { return x*x; }
    float band(float x,float center,float width) { return exp(-sq((x-center)/width)); }
    float spot(vec2 p,vec2 center,vec2 size) {
      vec2 q = (p-center)/size;
      return exp(-dot(q,q));
    }
    float rounded(vec2 p,vec2 halfSize,float radius) {
      vec2 q = abs(p)-halfSize+radius;
      return min(max(q.x,q.y),0.)+length(max(q,0.))-radius;
    }
    float aa(float distance) { return 1.-smoothstep(-.65,.76,distance); }
    vec4 over(vec4 back,vec3 rgb,float opacity) {
      opacity = clamp(opacity,0.,1.);
      float a = opacity + back.a*(1.-opacity);
      return vec4(mix(back.rgb*back.a,rgb,opacity)/max(a,.0001),a);
    }
    vec4 merge(vec4 back,vec4 front) { return over(back,front.rgb,front.a); }
    vec2 layerPoint(vec2 p,vec2 center,float angle) {
      float c = cos(angle), s = sin(angle);
      return mat2(c,-s,s,c)*(p-center);
    }
    vec4 pane(vec2 p,vec2 center,vec2 radius,float angle,float corner,float opacity,vec3 tint,float blur) {
      vec2 q = layerPoint(p,center,angle);
      float d = rounded(q,radius,corner);
      float feather = 1.+8.4*blur;
      if (d>feather) return vec4(0.);
      float depth = max(0.,-d);
      vec2 edge = normalize(max(abs(q)-radius+corner,vec2(.001)))*sign(q);
      float sky = .37+.63*max(0.,-edge.y);
      float upper = band(q.y,-radius.y*.81,radius.y*.48);
      float spread = spot(q,vec2(-radius.x*.58,-radius.y*.62),vec2(245.,105.));
      float veil = band(depth,8.,13.5);
      vec3 diffuse = tint + vec3(.046,.062,.073) + vec3(.13,.16,.17)*upper+vec3(.105,.132,.143)*spread;
      diffuse += vec3(.17,.21,.24)*veil*(.20+.44*sky);
      vec4 layer = vec4(diffuse,opacity - .07*spread);
      float rim = band(depth,1.65,1.45+6.2*blur)*(.22+.30*sky)*(1.-.60*blur);
      layer = over(layer,vec3(.81,.897,.94),rim);
      layer.a *= 1.-smoothstep(-.70*feather,.76*feather,d);
      return layer;
    }
    vec2 frontPoint(vec2 p) {
      vec2 q = p-vec2(403.,263.);
      q.x += 4.8*band(p.y,273.,124.) - 4.1*band(p.y,122.,58.);
      q.y -= 6.3*band(p.x,428.,187.) - 3.4*band(p.x,159.,72.);
      q.y += .025*q.x;
      return q;
    }
    float frontDistance(vec2 p) { return rounded(frontPoint(p),vec2(319.,214.),58.); }
    vec4 frontPane(vec2 p) {
      float d = frontDistance(p);
      if (d > 1.) return vec4(0.);
      float depth = max(-d,0.);
      vec2 outward = normalize(vec2(frontDistance(p+vec2(.63,0.))-d,
                                   frontDistance(p+vec2(0.,.63))-d)+vec2(.0001));
      float sky = max(0.,-outward.y);
      float bounce = max(0.,outward.y);
      float top = spot(p,vec2(226.,63.),vec2(285.,141.));
      float left = spot(p,vec2(143.,237.),vec2(174.,202.));
      float foot = spot(p,vec2(601.,447.),vec2(228.,95.));
      float shade = spot(p,vec2(473.,304.),vec2(252.,141.));
      float fog = spot(p,vec2(318.,152.),vec2(345.,95.))
                + .72*spot(p,vec2(606.,437.),vec2(217.,75.));
      vec3 hue = vec3(.245,.410,.521)
        + vec3(.155,.196,.217)*top
        + vec3(.055,.088,.108)*left
        + vec3(.092,.145,.17)*foot
        - vec3(.056,.080,.088)*shade;
      float opacity = .70 + .08*shade;
      vec4 glass = vec4(hue,opacity);
      glass = over(glass,vec3(.72,.84,.915),.31*fog);
      float wide = band(depth,8.8,12.9);
      float rim = band(depth,1.40,1.40);
      glass = over(glass,vec3(.67,.797,.854),wide*(.15+.19*sky+.22*bounce));
      glass = over(glass,vec3(.85,.93,.965),rim*(.30+.22*sky+.17*bounce));
      glass.a *= aa(d);
      return glass;
    }
    vec4 shell(vec2 p) {
      vec4 result = vec4(0.);
      // Rear seams soften wherever the front pane's fog lies over them.
      float front = frontDistance(p);
      float blur = 1.-smoothstep(-23.,-2.,front);
      result = merge(result,pane(p,vec2(382.,270.),vec2(326.,163.),-.082,68.,.73,vec3(.37,.50,.59),blur));
      result = merge(result,pane(p,vec2(393.,247.),vec2(310.,201.), .092,65.,.64,vec3(.31,.44,.52),blur));
      result = merge(result,pane(p,vec2(415.,255.),vec2(307.,204.),-.061,56.,.62,vec3(.28,.43,.52),blur));
      result = merge(result,pane(p,vec2(400.,292.),vec2(332.,168.), .060,64.,.68,vec3(.36,.50,.59),blur));
      result = merge(result,pane(p,vec2(395.,280.),vec2(315.,200.),-.041,54.,.59,vec3(.30,.43,.53),blur));
      result = merge(result,frontPane(p));
      float depth = max(-front,0.);
      result.a = min(result.a,.900+.058*band(depth,1.4,3.6));
      return result;
    }
    void main() {
      vec2 p=vec2(gl_FragCoord.x/viewport.x,1.-gl_FragCoord.y/viewport.y)*vec2(742.,522.);
      vec4 glass=shell(p);
      float luminance=dot(glass.rgb,vec3(.2126,.7152,.0722));
      vec3 colored=luminance*(vec3(.24)+themeTint*.95);
      glass.rgb=mix(glass.rgb,colored,themeStrength*.90);
      glass.a *= glassOpacity;
      gl_FragColor=glass;
    }
`;
