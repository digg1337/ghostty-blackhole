# Cinematic Black Hole implementation guide

Work from the target repository root:

~~~sh
cd /home/slouka/personal/ghostty-blackhole
~~~

This guide is for a fresh session with no codebase context. Implement one stage
at a time and stop on a failed gate. The features are: a smooth Gargantua disk
with single-pass glow and anamorphic streak; a deep-space backdrop with a
Milky-Way ridge, procedural galaxies, and star glints; relativistic polar
jets; and a film look with optional ACES, grain, vignette, and photon-ring
chromatic aberration.

## 1. Mission and invariants

Add this beside the existing QUALITY_LEVEL definitions:

~~~glsl
#define CINEMATIC 0
~~~

The six required variants are all three quality tiers with CINEMATIC equal to
0 and 1. The current look remains the default.

Hard invariants:

- Do not touch tokenFromBytes, tokenDecode, tokenLevel, or their cursor-color
  encoding and glide behavior.
- Do not touch the unfocused feeding block, claude-token.py, or B_CRIT.
  B_CRIT is deliberately a define, not a tunable.
- Preserve the Ghostty one-fragment, stateless model. There is no framebuffer,
  custom uniform, compute pass, or second post pass. Bloom is analytic.
- Never process terminal text with grain, CA, vignette, or disk tonemapping.
- Every new slider is a top-level declaration exactly shaped like
  const float NAME = x.xxxx; and has a matching ParamSpec entry.

Ghostty facts: fragCoord.y is top-down; use the existing yUp conversion.
Reload with SIGUSR2, locating the Ghostty process with ps because Ghostty is
the shell's ancestor; do not rely on pgrep.

Use search-string anchors, never line numbers:

~~~sh
rg -n -F 'vec3 stars(vec3 d)' blackhole.glsl
~~~

If an anchor is not unique, use a longer string. Never guess an insertion
point.

## 2. Verification harness

Create tools before editing shader code. The Python driver wraps the project
shader with Ghostty-like uniforms and calls mainImage. The C program compiles
that wrapper in a headless desktop GL 4.3 EGL pbuffer. The explicit pbuffer
surface attribute is required on hosts where eglChooseConfig otherwise
returns zero configurations.

### tools/glcheck.c

~~~c
#define _GNU_SOURCE
#include <EGL/egl.h>
#include <GL/gl.h>
#include <stdio.h>
#include <stdlib.h>
static char *readall(const char *p){FILE*f=fopen(p,"rb");long n;char*s;
 if(!f){perror(p);return 0;}fseek(f,0,SEEK_END);n=ftell(f);fseek(f,0,SEEK_SET);
 s=calloc((size_t)n+1,1);if(!s||fread(s,1,(size_t)n,f)!=(size_t)n){free(s);s=0;}
 fclose(f);return s;}
int main(int ac,char**av){if(ac!=2)return 2;EGLint ma,mi,n;
 EGLDisplay d=eglGetDisplay(EGL_DEFAULT_DISPLAY);
 if(d==EGL_NO_DISPLAY||!eglInitialize(d,&ma,&mi)||!eglBindAPI(EGL_OPENGL_API))
  {fputs("EGL init failed\n",stderr);return 1;}
 const EGLint ca[]={EGL_SURFACE_TYPE,EGL_PBUFFER_BIT,EGL_RENDERABLE_TYPE,
  EGL_OPENGL_BIT,EGL_RED_SIZE,8,EGL_GREEN_SIZE,8,EGL_BLUE_SIZE,8,EGL_ALPHA_SIZE,8,EGL_NONE};
 EGLConfig cfg;if(!eglChooseConfig(d,ca,&cfg,1,&n)||n==0)
  {fprintf(stderr,"eglChooseConfig returned %d configs\n",n);return 1;}
 const EGLint pa[]={EGL_WIDTH,16,EGL_HEIGHT,16,EGL_NONE};
 const EGLint xa[]={EGL_CONTEXT_MAJOR_VERSION,4,EGL_CONTEXT_MINOR_VERSION,3,
  EGL_CONTEXT_OPENGL_PROFILE_MASK,EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT,EGL_NONE};
 EGLSurface s=eglCreatePbufferSurface(d,cfg,pa);EGLContext c=eglCreateContext(d,cfg,0,xa);
 if(s==EGL_NO_SURFACE||c==EGL_NO_CONTEXT||!eglMakeCurrent(d,s,s,c))return 1;
 char*src=readall(av[1]);if(!src)return 1;GLuint sh=glCreateShader(GL_FRAGMENT_SHADER);
 glShaderSource(sh,1,(const GLchar**)&src,0);glCompileShader(sh);GLint ok=0;
 glGetShaderiv(sh,GL_COMPILE_STATUS,&ok);if(!ok){GLint z;glGetShaderiv(sh,GL_INFO_LOG_LENGTH,&z);
  char*e=calloc(z+1,1);glGetShaderInfoLog(sh,z,0,e);fputs(e,stderr);free(e);return 1;}
 GLuint pr=glCreateProgram();glAttachShader(pr,sh);glLinkProgram(pr);glGetProgramiv(pr,GL_LINK_STATUS,&ok);
 if(!ok){GLint z;glGetProgramiv(pr,GL_INFO_LOG_LENGTH,&z);char*e=calloc(z+1,1);
  glGetProgramInfoLog(pr,z,0,e);fputs(e,stderr);free(e);return 1;}puts("OK");return 0;}
~~~

### tools/verify.py

~~~python
#!/usr/bin/env python3
import argparse,pathlib,re,subprocess,tempfile
HEADER="""#version 430 core
uniform vec3 iResolution; uniform float iTime,iTimeFocus,iTimeCursorChange;
uniform vec4 iDate,iCurrentCursorColor,iPreviousCursorColor;
uniform sampler2D iChannel0;
"""
FOOTER="""out vec4 _outColor;
void main(){mainImage(_outColor,gl_FragCoord.xy);}
"""
def main():
 ap=argparse.ArgumentParser();ap.add_argument("--shader",default="blackhole.glsl")
 ap.add_argument("--glcheck",default="tools/glcheck");a=ap.parse_args()
 src=pathlib.Path(a.shader).read_text();bad=False
 for name,q in [("LIGHTWEIGHT",0),("BALANCED",1),("MAXIMUM",2)]:
  for cine in (0,1):
   s=re.sub(r"^#define QUALITY_LEVEL .*$",f"#define QUALITY_LEVEL {q}",src,flags=re.M)
   s=re.sub(r"^#define CINEMATIC .*$",f"#define CINEMATIC {cine}",s,flags=re.M)
   with tempfile.NamedTemporaryFile("w",suffix=".frag") as f:
    f.write(HEADER+s+FOOTER);f.flush();r=subprocess.run([a.glcheck,f.name],text=True,capture_output=True)
    tag=f"QUALITY_{name} CINEMATIC={cine}"
    if r.returncode:bad=True;print("FAIL",tag,r.stderr)
    else:print("PASS",tag,r.stdout.strip())
 return int(bad)
if __name__=="__main__":raise SystemExit(main())
~~~

Build and run the baseline gate:

~~~sh
mkdir -p tools
cc -O2 -Wall -Wextra tools/glcheck.c -o tools/glcheck $(pkg-config --cflags --libs egl gl)
chmod +x tools/verify.py
python3 tools/verify.py
~~~

Expected observable: six PASS lines and status 0. Fix the harness or baseline
shader before feature work.

## 3. Stage 0 — scaffolding

Use the unique anchor #define QUALITY_LEVEL QUALITY_MAXIMUM. Add this tunable
block beside the current top-level constants:

~~~glsl
const float CINE_SKY_GAIN    = 1.0000;
const float CINE_GLOW_GAIN   = 0.5500;
const float CINE_GLOW_RADIUS = 0.0500;
const float CINE_STREAK_GAIN = 0.2400;
const float CINE_JET_GAIN    = 0.7000;
const float CINE_JET_ANGLE   = 0.1800;
const float CINE_JET_BETA    = 0.9000;
const float CINE_FILM_GRAIN  = 0.0200;
const float CINE_VIGNETTE    = 0.1800;
const float CINE_RING_CA     = 0.3000;
const float CINE_ACES        = 1.0000;
~~~

Run the six-variant gate. With CINEMATIC 0, fixed-frame blackFrac and avgLum
must match today's baseline within normal floating-point noise.

## 4. Stage A — Gargantua disk and glow

Anchor on DiskLook L = LOOK_DEFAULT;. Immediately after it add:

~~~glsl
#if CINEMATIC
    L.temp=6200.0; L.thick=0.0500; L.turb=0.0800;
    L.contr=0.1800; L.filSharp=1.2000;
#endif
~~~

Do not modify LOOK_DEFAULT or demo presets. Before vec3 traceNearField( add
this single-pass analytic proxy:

~~~glsl
#if CINEMATIC
vec3 cineDiskProxy(vec2 p,float W,DiskLook L,float rin,float rout,vec3 n,vec3 v){
 vec3 ray=normalize(vec3(p*W,-max(4.0,W*.02)));float den=dot(ray,n);
 if(abs(den)<.035)return vec3(0);vec3 hit=ray*(-dot(vec3(0),n)/den);float r=length(hit);
 float ann=smoothstep(rin,rin+.35,r)*(1.-smoothstep(rout-1.2,rout,r));
 float edge=max(1.-sqrt(rin/max(r,rin)),0.);float tp=pow(rin/max(r,rin),.75)*pow(edge,.25)/.488;
 vec3 tan=normalize(cross(n,hit));float beta=clamp(1./sqrt(max(2.*r,1.01)),0.,.85);
 float dop=sqrt(max(1.-beta*beta,.02))/max(1.+beta*dot(tan,v),.08);
 float shift=mix(1.,dop,L.dopp);vec3 c=blackbodyLinear(L.temp*max(tp,.08)*max(shift,.1));
 return c*ann*pow(clamp(tp,0.,1.5),2.5)*pow(max(shift,.05),L.beam)*L.gain;
}
vec3 cineGlow(vec2 p,float W,DiskLook L,float rin,float rout,vec3 n,vec3 v){
 const vec2 o[6]=vec2[6](vec2(-1,0),vec2(1,0),vec2(-.5,0),vec2(.5,0),vec2(0,-.75),vec2(0,.75));
 const float w[6]=float[6](.10,.10,.18,.18,.12,.12);vec3 s=vec3(0);
 for(int i=0;i<6;i++)s+=cineDiskProxy(p+o[i]*CINE_GLOW_RADIUS,W,L,rin,rout,n,v)*w[i];
 float streak=exp(-abs(p.y)/max(CINE_GLOW_RADIUS*.45,1e-4))*exp(-abs(p.x)/max(CINE_GLOW_RADIUS*5.,1e-4));
 return (s+vec3(.72,.86,1.)*streak*CINE_STREAK_GAIN)*CINE_GLOW_GAIN;
}
#endif
~~~

At the end of traceNearField, before its existing return, add
emitc += cineGlow(p,W,L,rin,rout,n,normalize(v)); behind CINEMATIC. If p is not
in scope, thread the existing screen point through the arguments; never add a
uniform. Gate: the disk band avgLum rises and a soft halo appears, while
focused terminal text is unchanged.

## 5. Stage B — deep-space backdrop

Anchor on vec3 stars(vec3 d). Preserve the current sparse-star result as
baseStars, then append:

~~~glsl
#if CINEMATIC
 vec3 q=normalize(d);float band=exp(-pow((q.y+.12*sin(5.*q.x))/.24,2.));
 vec3 sky=vec3(.12,.16,.25)*band*(.35+.65*hash21(floor(q.xz*28.)));
 const vec3 gd[3]=vec3[3](vec3(.32,.18,-.93),vec3(-.72,.22,-.65),vec3(.08,-.64,-.76));
 for(int k=0;k<3;k++){float c=clamp(dot(q,gd[k]),-1.,1.);vec3 t=normalize(q-gd[k]*c);
  float u=atan(t.z,t.x),v=acos(c),e=exp(-pow(v/(.060+.015*float(k)),2.));
  sky+=vec3(.30,.22,.16)*e*(.35+.65*(.5+.5*cos(7.*u+34.*v+float(k))));}
 if(h>.985){float cr=exp(-80.*abs(f.x-off.x))+exp(-80.*abs(f.y-off.y));
  sky+=tint*cr*((h-.985)/.015);}
 return baseStars+sky*CINE_SKY_GAIN;
#else
 return baseStars;
#endif
~~~

Do not move the existing multiplication by L.star at either caller. Gate:
STAR_GAIN 0.6 shows structured sky and glints; STAR_GAIN 0.0 shows none.

## 6. Stage C — relativistic jets

Use the unique anchor // Integrate emission and absorption through a finite
disk volume. Insert inside the existing march loop after the position update:

~~~glsl
#if CINEMATIC
 vec3 jd=normalize(x);float side=dot(jd,n)<0.?-1.:1.;
 float cone=smoothstep(CINE_JET_ANGLE*(.30+.14*r),CINE_JET_ANGLE*(.10+.05*r),
                       length(jd-n*side));
 float window=smoothstep(horizon*1.1,horizon*2.,r)*(1.-smoothstep(rout*2.4,rout*5.,r));
 float noise=.55+.45*vnoiseWrapY(vec2(r*.42,abs(dot(jd,n))*13.+t*.7),13.);
 vec3 vel=n*side*CINE_JET_BETA;
 float dop=sqrt(max(1.-CINE_JET_BETA*CINE_JET_BETA,.01))/max(1.-dot(vel,normalize(v)),.06);
 emitc+=blackbodyLinear(20000.)*CINE_JET_GAIN*cone*window*noise*pow(max(dop,.05),3.)*
         min(length(x-xPrev),1.);
#endif
~~~

Gate: with DISK_INCL around 0.25, two opposed lobes appear and the approaching
lobe is brighter. Restore normal values after the test.

## 7. Stage D — film look

Place this beside filmicTonemap:

~~~glsl
#if CINEMATIC
vec3 cineACES(vec3 x){x=max(x,vec3(0));const mat3 a=mat3(.59719,.35458,.04823,.076,.90834,.01566,.0284,.13383,.83777);
 const mat3 b=mat3(1.60475,-.53108,-.07367,-.10208,1.10813,-.00605,-.00327,-.07276,1.07602);
 x=a*x;x=(x*(x+.0245786)-.000090537)/(x*(.983729*x+.432951)+.238081);return clamp(b*x,vec3(0),vec3(1));}
vec3 cineDiskTone(vec3 x){return CINE_ACES>.5?cineACES(x):filmicTonemap(x);}
#endif
~~~

At the exact anchor return bg * trans + filmicTonemap(emitc * L.expo); replace
only the disk term:

~~~glsl
#if CINEMATIC
 return bg*trans+cineDiskTone(emitc*L.expo);
#else
 return bg*trans+filmicTonemap(emitc*L.expo);
#endif
~~~

Inside the existing photon-ring condition anchored by abs(b - B_CRIT), CA may
offset only disk-trace channels:

~~~glsl
#if CINEMATIC
 vec2 caDir=normalize(p+vec2(1e-6))*CINE_RING_CA/res.y;
 col=vec3(traceNearField(p-caDir,center,W,rh,window,shield,t,dil,L,rin,rout,spin,horizon).r,
          traceNearField(p,center,W,rh,window,shield,t,dil,L,rin,rout,spin,horizon).g,
          traceNearField(p+caDir,center,W,rh,window,shield,t,dil,L,rin,rout,spin,horizon).b);
#endif
~~~

Do not move this outside the ring; maximum quality already supersamples.
Apply grain/vignette before terminal compositing, never to texture iChannel0:

~~~glsl
#if CINEMATIC
 float vg=1.-CINE_VIGNETTE*smoothstep(.20,1.20,plen/max(7.*rh,1e-4));
 float grain=(hash21(fragCoord.xy+vec2(iTime,17.))-.5)*CINE_FILM_GRAIN;
 diskColor=max(diskColor*vg+grain*vg,vec3(0));
#endif
~~~

Use the actual disk-only variable at the current composition point. If col
already contains terminal text, move this operation earlier. Gate: focused
text is pixel-clean, unfocused output is nonblank, and magentaLeftover=0.

## 8. Stage E — tuner and README

In ParamSpec.swift add Cinematic immediately before Other in groupOrder. Add
every CINE name to all:

~~~swift
"CINE_SKY_GAIN": ParamSpec(0.0...3.0, "Cinematic", 1.0, "Cinematic sky gain"),
"CINE_GLOW_GAIN": ParamSpec(0.0...2.0, "Cinematic", 0.55, "Disk halo gain"),
"CINE_GLOW_RADIUS": ParamSpec(0.005...0.20, "Cinematic", 0.05, "Halo radius"),
"CINE_STREAK_GAIN": ParamSpec(0.0...1.0, "Cinematic", 0.24, "Blue streak gain"),
"CINE_JET_GAIN": ParamSpec(0.0...3.0, "Cinematic", 0.70, "Jet gain"),
"CINE_JET_ANGLE": ParamSpec(0.02...0.60, "Cinematic", 0.18, "Jet angle"),
"CINE_JET_BETA": ParamSpec(0.0...0.99, "Cinematic", 0.90, "Jet velocity"),
"CINE_FILM_GRAIN": ParamSpec(0.0...0.10, "Cinematic", 0.02, "Disk-only grain"),
"CINE_VIGNETTE": ParamSpec(0.0...1.0, "Cinematic", 0.18, "Hole vignette"),
"CINE_RING_CA": ParamSpec(0.0...1.0, "Cinematic", 0.30, "Ring channel separation"),
"CINE_ACES": ParamSpec(0.0...1.0, "Cinematic", 1.0, "Use ACES tonemap"),
~~~

Add a Cinematic preset containing these defaults, STAR_GAIN 0.6, DISK_TEMP
6200, DISK_THICKNESS 0.05, DISK_TURBULENCE 0.08, and DISK_CONTRAST 0.18.
The preset must not change CINEMATIC because that is a compile-time define.
Document the mode and every CINE constant in README. Confirm claude-token.py
is unchanged.

## 9. Final acceptance

~~~sh
python3 tools/verify.py
git diff --check
rg -n -F 'tokenFromBytes' blackhole.glsl
rg -n -F 'float tokenDecode' blackhole.glsl
rg -n -F 'float tokenLevel' blackhole.glsl
rg -n -F '#define B_CRIT' blackhole.glsl
git diff --stat
~~~

Require six compile passes; unchanged CINEMATIC 0 blackFrac and avgLum; crisp
focused text; working unfocused feeding; Stage A disk-band luminance increase;
Stage B STAR_GAIN behavior; Stage C opposed Doppler-asymmetric jets; Stage D
disk-only grain/vignette/CA with magentaLeftover=0; and all constants visible
in the Cinematic tuner group and README. Test live reload by finding Ghostty
with ps and sending SIGUSR2. Restore CINEMATIC 0 unless enabled shipping is
intentional.

## 10. Troubleshooting

- Zero EGL configs: retain EGL_SURFACE_TYPE, EGL_PBUFFER_BIT in glcheck.c.
- Grey shadow at extreme zoom: may be correct mirrored/reprojected sampling;
  compare normal-size blackFrac before changing horizon or B_CRIT.
- Tuner drift into Other: exact name missing from ParamSpec.all, or declaration
  does not match the required const float NAME = x.xxxx; format.
- Ring or edge smear: preserve mirrorUV; do not replace it with clamp.
- Sky ignores STAR_GAIN 0: keep cinematic sky inside stars or multiply the
  complete result at both callers.
- Noisy or magenta text: grain/CA was applied after terminal compositing;
  restore the original mirrorUV text sample and move effects to disk emission.
- Focused frame blank: cinematic code changed vis, shield, eat, I, sz, or the
  early visibility return. Restore those state calculations.
