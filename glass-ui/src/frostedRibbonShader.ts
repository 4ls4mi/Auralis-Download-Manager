/* Ribbon and clear capsule from Water Bubble 3.5.1. */
export const ribbonFragment = `
    precision highp float;
    uniform vec2 viewport;
    uniform float seconds;
    uniform float progress;
    uniform float shapeGeometry;
    uniform float unknown;
    uniform float trackFinish;
    uniform vec3 trackTint;
    uniform vec3 trackTintA;
    uniform vec3 trackTintB;
    uniform vec3 trackTintC;
    uniform float trackTintStrength;
    uniform vec3 fillColorA;
    uniform vec3 fillColorB;
    uniform vec3 fillColorC;

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
      result = merge(result,pane(p,vec2(342.,270.),vec2(326.,163.),-.082,68.,.73,vec3(.37,.50,.59),blur));
      result = merge(result,pane(p,vec2(393.,247.),vec2(310.,201.), .092,65.,.64,vec3(.31,.44,.52),blur));
      result = merge(result,pane(p,vec2(415.,255.),vec2(307.,204.),-.061,56.,.62,vec3(.28,.43,.52),blur));
      result = merge(result,pane(p,vec2(374.,292.),vec2(332.,168.), .060,64.,.68,vec3(.36,.50,.59),blur));
      result = merge(result,pane(p,vec2(395.,280.),vec2(315.,200.),-.041,54.,.59,vec3(.30,.43,.53),blur));
      result = merge(result,frontPane(p));
      float depth = max(-front,0.);
      result.a = min(result.a,.900+.058*band(depth,1.4,3.6));
      return result;
    }
    // The four knots describe the projected edge of a fold in the reference.
    float edgeCurve(float x,vec4 knots,vec4 heights) {
      return heights.x + (heights.y-heights.x)*smoothstep(knots.x,knots.y,x)
        + (heights.z-heights.y)*smoothstep(knots.y,knots.z,x)
        + (heights.w-heights.z)*smoothstep(knots.z,knots.w,x);
    }

    vec3 sheet(vec3 back,vec2 p,vec2 profile,vec3 glass,vec3 glow,float mask,float light) {
      float width = max(1.,profile.y-profile.x);
      float t = (p.y-profile.x)/width;
      float top = p.y-profile.x;
      float bottom = profile.y-p.y;
      float inside = smoothstep(-.52,.78,min(top,bottom))*mask;
      float dy = clamp(2.*t-1.,-1.,1.);
      float z = sqrt(max(.008,1.-dy*dy));

      // Light passing through the curved glass picks up blue along the thick fold.
      // A softbox above the ribbon reflects along its shoulder, below the thin rim.
      vec3 n = normalize(vec3(0.,dy,z));
      vec3 ray = refract(vec3(0.,0.,-1.),n,1./1.42);
      vec3 transmitted = back*exp(-vec3(.37,.15,.055)*z*.66);
      float shoulder = band(t,.19,.19);
      float key = band(t,.105,.082)*light;
      float pocket = band(t,.49,.27);
      float bounce = band(t+ray.y*.085,.83,.195);
      vec3 color = mix(transmitted,glass,.52)
        + vec3(.23,.29,.31)*(.49*shoulder+.42*key)
        - vec3(.039,.059,.071)*pocket
        + glow*.30*bounce;
      vec3 result = mix(back,color,inside*.79);
      float rim = band(top,.1,.83)*mask;
      float spill = band(top,1.3,2.5)*mask;
      result += mix(glow,vec3(.88,.97,1.),.67)*rim*(.45+.18*light);
      result += glow*spill*.11;
      result += glow*band(bottom,.8,1.7)*mask*.15;
      return result;
    }

    vec3 referenceFolds(vec2 p) {
      float x = p.x;
      float y = p.y;
      vec3 blue = vec3(.269,.497,.614)
        + vec3(.13,.19,.21)*band(y,235.,9.)
        + vec3(.03,.14,.18)*band(x,519.,104.)*band(y,268.,17.);
      float t = seconds*.93;

      // Far side of the wave: the line dips under the following fold, then rises.
      float rearY = edgeCurve(x-2.6*sin(t+.7),vec4(191.,237.,280.,315.),vec4(232.,240.,230.,232.));
      float rearMask = smoothstep(172.,205.,x)*(1.-smoothstep(313.,346.,x));
      blue = sheet(blue,p,vec2(rearY,278.),vec3(.39,.66,.75),vec3(.49,.83,.88),rearMask*.62,.63);

      // Right wing, seen through the central cyan face.
      float wingY = edgeCurve(x-3.6*sin(t-1.2),vec4(483.,528.,570.,602.),vec4(229.,240.,272.,267.));
      float wingMask = smoothstep(469.,498.,x);
      blue = sheet(blue,p,vec2(wingY,280.),vec3(.32,.70,.81),vec3(.42,.85,.92),wingMask*.85,.74);

      float xC = x-5.5*sin(t-2.1);
      float crestC = edgeCurve(xC,vec4(415.,480.,506.,573.),vec4(239.,229.,235.,277.));
      float spanC = smoothstep(398.,434.,xC)*(1.-smoothstep(569.,587.,xC));
      blue = sheet(blue,p,vec2(crestC,278.),vec3(.24,.67,.78),vec3(.31,.87,.96),spanC,.96);

      // This pocket sits behind the crossing crests; its broad shadow is visible
      // through the lit surface of the central fold.
      float xB = x-4.8*sin(t+.5);
      float hollow = edgeCurve(xB,vec4(326.,378.,425.,472.),vec4(232.,261.,246.,231.));
      float spanB = smoothstep(316.,343.,xB)*(1.-smoothstep(449.,484.,xB));
      blue = sheet(blue,p,vec2(hollow,278.),vec3(.42,.71,.80),vec3(.48,.83,.90),spanB*.74,.56);

      // A short near face catches light where the middle sheets cross.
      float crossingX = x-3.8*sin(t+.28);
      float crossing = edgeCurve(crossingX,vec4(386.,409.,436.,454.),vec4(230.,231.,244.,262.));
      float crossingFoot = edgeCurve(crossingX,vec4(395.,424.,442.,458.),vec4(277.,275.,268.,260.));
      float crossMask = smoothstep(364.,393.,crossingX)*(1.-smoothstep(448.,458.,crossingX));
      blue = sheet(blue,p,vec2(crossing,crossingFoot),vec3(.48,.74,.83),vec3(.57,.88,.94),crossMask*.64,.92);

      float xA = x-4.2*sin(t-1.0);
      float crestA = edgeCurve(xA,vec4(248.,289.,319.,392.),vec4(236.,229.,236.,277.));
      float spanA = smoothstep(222.,263.,xA)*(1.-smoothstep(394.,415.,xA));
      blue = sheet(blue,p,vec2(crestA,278.),vec3(.46,.68,.78),vec3(.57,.87,.95),spanA,.80);

      // The nearest fold starts white at its upper left and rolls into the trough.
      float xLeft = x-3.4*sin(t-2.8);
      float first = edgeCurve(xLeft,vec4(159.,189.,226.,276.),vec4(228.,230.,244.,276.));
      float firstMask = 1.-smoothstep(270.,290.,xLeft);
      blue = sheet(blue,p,vec2(first,279.),vec3(.62,.77,.84),vec3(.76,.91,.97),firstMask,1.);
      float milky = .63*spot(p,vec2(155.,232.),vec2(76.,19.))
                   + .26*spot(p,vec2(172.,247.),vec2(65.,19.));
      blue = mix(blue,vec3(.83,.93,.965),milky);

      // Light concentrated at the floor is transmitted through the overlapping glass.
      float pool = band(x,500.,103.);
      blue += vec3(.14,.35,.42)*pool*band(y,274.,6.3);
      blue += vec3(.24,.37,.40)*pool*band(y,275.8,1.8);
      return blue;
    }

    vec4 ribbonBar(vec2 p,vec4 background) {
      vec2 q = p-vec2(408.,253.5);
      float d = rounded(q,vec2(280.,24.),mix(24.,2.,shapeGeometry));
      float end = 128.+560.*progress;
      float active = (1.-smoothstep(end-5.,end+12.,p.x))*smoothstep(.035,.35,progress);
      float pool = band(p.x,472.,103.);
      if (d>1.) {
        float shadow = band(d,3.,7.)*smoothstep(0.,17.,q.y)*.21;
        float bloom = .43*pool*active*band(p.y,277.,5.6)*band(d,1.5,10.2);
        return over(over(background,vec3(.10,.25,.34),shadow),vec3(.33,.87,.98),bloom);
      }

      float depth = max(-d,0.);
      float y = q.y/24.;
      float rim = band(depth,1.07,1.18);
      float inner = band(depth,3.38,2.1);

      vec2 crossSection = vec2(q.x-clamp(q.x,-256.,256.),q.y)/24.;
      float dome = sqrt(max(.008,1.-dot(crossSection,crossSection)));
      vec3 normal = normalize(vec3(crossSection,dome));
      vec3 ray = reflect(vec3(0.,0.,-1.),normal);
      float endSpec = band(ray.x,.68,.32)*band(ray.y,-.29,.51)*smoothstep(659.,677.,p.x);

      vec3 track = mix(background.rgb,vec3(.58,.75,.83),.115);
      track += vec3(.10,.15,.19)*band(ray.y,-.62,.21)*.29;
      track += vec3(.12,.19,.23)*band(ray.y,.66,.23)*.24;
      track = mix(track,vec3(.78,.898,.952),endSpec*.35);
      track += vec3(.14,.22,.28)*inner*.125;

      if (trackFinish > .5 && trackFinish < 1.5) track = mix(track, vec3(.72,.84,.91), .48);
      if (trackFinish > 1.5 && trackFinish < 2.5) track = mix(track, vec3(.045,.09,.15), .54);
      if (trackFinish > 2.5) track = mix(track, vec3(.56,.78,.86), .40) + vec3(.055,.09,.10)*inner;
      vec3 gradientTint = mix(mix(trackTintA, trackTintB, smoothstep(0.0, 0.5, clamp((p.x-128.)/560.,0.,1.))), mix(trackTintB, trackTintC, smoothstep(0.5, 1.0, clamp((p.x-128.)/560.,0.,1.))), step(0.5, clamp((p.x-128.)/560.,0.,1.)));
      track = mix(track, gradientTint, trackTintStrength);

      // Keep the actual fill position tied to transferred bytes. These
      // coordinates map the visible folds to the width shown in the reference.
      float artworkX = 128.+(p.x-128.)*(492./459.2);
      vec3 liquid = referenceFolds(vec2(artworkX,p.y));
      // Preserve the reference folds and lighting while applying the chosen palette.
      float along=clamp((p.x-128.)/560.,0.,1.);
      vec3 chosen=mix(mix(fillColorA,fillColorB,smoothstep(0.,.5,along)),fillColorC,smoothstep(.5,1.,along));
      float brightness=dot(liquid,vec3(.2126,.7152,.0722));
      vec3 colored=chosen*(.42+brightness*.85)+vec3(max(0.,brightness-.65)*.60);
      liquid=chosen;
      float nose = sqrt(max(0.,1.-sq(clamp(y*.98,-1.,1.))));
      float cap = end-19.*(1.-nose);
      float full = smoothstep(.982,1.,progress);
      float fill = mix((1.-smoothstep(-.6,.85,p.x-cap))*smoothstep(0.,.031,progress),1.,full);
      float endDepth = cap-p.x;



      vec3 face = mix(track,liquid,fill);
      if (unknown>.5) {
        float pulse = pow(.5+.5*cos(q.x*.024-seconds*3.),6.);
        face = mix(track,liquid,.11+.45*pulse);
      }
      face = mix(face,vec3(.865,.943,.974),rim*(.44+.20*max(0.,-y))*(1.-fill));
      return over(background,face,aa(d)*(.79+.115*fill));
    }
    void main() {
      vec2 p=vec2(gl_FragCoord.x/viewport.x,1.-gl_FragCoord.y/viewport.y)*vec2(560.,48.)+vec2(128.,229.5);
      gl_FragColor=ribbonBar(p,vec4(.245,.410,.521,0.));
    }
`;
