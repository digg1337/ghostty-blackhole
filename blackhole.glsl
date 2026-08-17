// blackhole.glsl — a geodesic-traced black hole for Ghostty
//
// After Eric Bruneton's "Real-time High-Quality Rendering of Non-Rotating
// Black Holes" (https://ebruneton.github.io/black_hole_shader/). Bruneton
// precomputes Schwarzschild geodesics into lookup textures; a Ghostty custom
// shader is a single fragment pass with no custom textures, so each pixel's
// light path is integrated numerically. The exact planar Schwarzschild term
// is augmented with the leading gravitomagnetic field of a spinning mass: a
// stable Kerr-inspired approximation with frame dragging, a spin-dependent
// horizon and ISCO. The silhouette itself uses the exact Kerr radial photon
// potential, preventing strong-field leaks from the approximate live path.
//
//   * the shadow            — exact Kerr capture/escape coverage, including
//                             the spin-shifted critical curve
//   * gravitational lensing — escaped rays are projected back onto the
//                             terminal "sky" plane: text bends, magnifies,
//                             and mirrors inside the Einstein ring
//   * photon ring           — rays winding near the r = 1.5 r_s photon sphere
//   * accretion disk        — a finite turbulent volume the ray may cross
//                             several times; CIE blackbody color from a
//                             Shakura–Sunyaev profile is Kerr-shifted,
//                             g^4 transported, absorbed, and filmically mapped
//   * starfield             — a faint lensed sky so the bending reads even
//                             over empty terminal background
//
// Units: r_s (Schwarzschild radius) = 1. The screen mapping ties the shadow
// radius b_crit to HOLE_RADIUS * sz, so the size modes below keep working.
//
// Ghostty setup (~/.config/ghostty/config):
//   custom-shader = /path/to/blackhole_ghostty/blackhole.glsl
//   custom-shader-animation = always

// ---------------------------------------------------------------- tunables --
// hole & lensing
const float HOLE_RADIUS   = 0.0200; // size dial. Pomodoro: shadow radius at full size (fraction of screen height). Token mode: scales the area calibration, exact at 0.08.
const float LENS_DEPTH    = 13.0000; // distance from hole to the terminal "sky" plane, in r_s — bigger = text bends harder
const float STAR_GAIN     = 0.0550; // restrained lensed sky brightness around the hole (0 = off)
const float BH_SPIN       = 0.8500; // Kerr spin approximation: 0 = Schwarzschild, 0.998 = near-extremal
// accretion disk geometry (radii in Schwarzschild radii)
const float DISK_INNER    = 1.3500; // inner edge; clamped to the rotation-appropriate Kerr ISCO
const float DISK_OUTER    = 10.0000; // outer edge
const float DISK_INCL     = 1.4200; // inclination, rad: 0 = face-on, 1.57 = edge-on
const float DISK_ROLL     = 0.1800; // rotation of the whole system in the screen plane, rad
const float DISK_THICKNESS = 0.0550; // thin-disk scale height H/r; lensing supplies the apparent vertical arcs
// accretion disk matter & light
const float DISK_GAIN     = 3.2000; // disk emission brightness
const float DISK_OPACITY  = 1.2000; // optical depth through the full tapered vertical column
const float DISK_TEMP     = 7200.0000; // temperature of the hottest annulus, Kelvin
const float DOPPLER_MIX   = 1.0000; // 0 = no relativistic color/brightness asymmetry, 1 = full Kerr shift
const float DISK_BEAM     = 4.0000; // bolometric Liouville transport: observed intensity scales as g^4
const float DISK_SPEED    = 3.6000; // turbulent orbital pattern speed; negative reverses the orbit direction
const float DISK_WIND     = 6.0000; // spiral winding tightness of the streaks
const float DISK_CONTRAST = 1.0500; // streak contrast: 0 = smooth haze, higher = sharp filaments
const float DISK_TURBULENCE = 0.7000; // mixture of fine turbulent structure into the base disk density
const float DISK_FILAMENT_SHARPNESS = 2.2000; // ridge exponent for hot filaments: higher = thinner, crisper streak lines
const float DISK_WARP_STRENGTH = 0.5000; // domain-warp the turbulence field for swirling, marbled structure (0 = off)
const float DISK_ARM_COUNT     = 2.0000; // number of dominant spiral density-wave arms overlaid on the turbulence
const float DISK_ARM_TWIST     = 3.0000; // how tightly the arms wind per unit radius
const float DISK_ARM_SHARPNESS = 3.0000; // arm crest exponent: higher = narrower, brighter arms
const float DISK_ARM_STRENGTH  = 0.1500; // weak MRI-scale density structure; high values look like galactic arms
// light & screen
const float EXPOSURE      = 2.4000; // filmic exposure for the disk light (terminal text is untouched)
const float DRIFT_SPEED   = 1.0000; // how fast the hole floats around
const float WORK_AREA     = 0.3300; // bottom screen fraction kept undistorted
const float DILATION_MIN  = 0.2000; // disk pattern time rate at full size (gravitational time dilation theme)
// token mode
const float TOKEN_AREA_MIN = 0.0300; // MODE_TOKENS: shadow area at 0% context, as a fraction of the terminal area
const float TOKEN_AREA_MAX = 0.5000; // MODE_TOKENS: shadow area at 100% context. Looks bigger than it sounds: the bright disk reaches ~3x past the shadow radius, so 0.0313 already fills most of a screen height — and render cost scales with it.
const float TOKEN_HOME_X  = 0.9600; // MODE_TOKENS: corner-home x in uv (1.0 = right edge)
const float TOKEN_HOME_Y  = 0.0400; // MODE_TOKENS: corner-home y in uv (0.0 = screen top — Ghostty y runs top-down)
const float TOKEN_EASE    = 0.4500; // MODE_TOKENS: growth curve exponent; 1 = proportional, <1 front-loads growth, >1 back-loads it
const float TOKEN_VISUAL_FLOOR = 0.1800; // MODE_TOKENS: visual fill used at 0% context so a fresh Claude session is immediately visible
const float TOKEN_REACH   = 1.0000; // MODE_TOKENS: fraction of the playable screen the roam box covers at 100% context
const float TOKEN_CALM    = 0.2200; // MODE_TOKENS: drift speed at 0% context (near-still seed)
const float TOKEN_RUSH    = 2.0000; // MODE_TOKENS: drift speed at 100% context (noticeably quicker, never frantic)
// unfocused mode
const float UNFOCUSED_EAT_SEC = 1.8000; // focus-session seconds before the consume effect is fully armed
const float UNFOCUSED_GROW_SEC = 40.0000; // focus-session hunger window before the revealed hole reaches its cap
const float UNFOCUSED_GROW_EASE = 2.2000; // feed growth curve exponent: 1 = plain ease, >1 front-loads slowness (barely-there at first, then reveals)
const float UNFOCUSED_ROAM_RADIUS = 0.1200; // how far the feeding center wanders from its home point, in uv
const float UNFOCUSED_ROAM_SPEED = 0.1500; // Lissajous roam speed multiplier (slow — an ambient drift, not a dart)
const float UNFOCUSED_LEVEL   = 0.9500; // mass/glow while the terminal is unfocused
const float UNFOCUSED_START_RADIUS = 0.0350; // initial shadow radius as a fraction of terminal height
const float UNFOCUSED_END_RADIUS = 0.3600; // fed shadow radius as a fraction of terminal height
const float UNFOCUSED_CENTER_X = 0.5000; // consume point x in uv
const float UNFOCUSED_CENTER_Y = 0.4300; // consume point y in uv (Ghostty y runs top-down)
// MODE_TOKENS is silent while focused (see the token-mode branch below); once
// unfocused, a fuller Claude Code context makes the hole hungrier — bigger
// cap, faster feed. contextFill is 0 outside MODE_TOKENS, which reproduces
// today's fixed feed exactly.
const float UNFOCUSED_HUNGRY_END_RADIUS = 0.6500; // fed shadow radius cap at 100% context fill (mixed with UNFOCUSED_END_RADIUS by contextFill)
const float UNFOCUSED_HUNGRY_GROW_SEC   = 3.5000; // hunger window at 100% context fill (mixed with UNFOCUSED_GROW_SEC by contextFill)
// eating: glyphs spiral inward and stretch toward the hole before they cross
// the horizon, instead of just fading in place
const float UNFOCUSED_PULL_INNER = 0.7500; // consume band inner edge, in units of the shadow radius rh
const float UNFOCUSED_PULL_OUTER = 3.2000; // consume band outer edge, in units of rh — untouched beyond this
const float UNFOCUSED_PULL_MIN   = 0.6500; // inward drag fraction at the start of feeding
const float UNFOCUSED_PULL_MAX   = 1.0000; // inward drag fraction once fully fed
const float UNFOCUSED_SWIRL_MIN  = 2.0000; // spiral twist, radians, at the start of feeding
const float UNFOCUSED_SWIRL_MAX  = 6.5000; // spiral twist, radians, once fully fed

// Compile-time rendering budget. Maximum adds four turbulence octaves and
// 2x2 supersampling around the photon ring; lower tiers are one-line fallbacks.
#define QUALITY_LIGHTWEIGHT 0
#define QUALITY_BALANCED    1
#define QUALITY_MAXIMUM     2
#define QUALITY_LEVEL QUALITY_MAXIMUM
#define CINEMATIC 1

// Ghostty passes native fragment coordinates through unchanged: OpenGL has
// +Y up, while Metal has +Y down. Work in one canonical top-down screen space
// and convert terminal texture coordinates back at every sample.
#define GHOSTTY_Y_DOWN 0 // Linux/OpenGL = 0; macOS/Metal = 1

// Opt-in cinematic radiance layer. These remain top-level const floats because
// tuner/Sources/BlackHoleTuner/ParamSpec.swift parses this exact declaration shape.
const float CINE_SKY_GAIN       = 1.0000;
const float CINE_GLOW_GAIN      = 1.1000; // optically thin, geodesic-lensed coronal emission
const float CINE_GLOW_RADIUS    = 0.0500; // extra coronal opening H/r (kept small around the thin disk)
const float CINE_JET_GAIN       = 0.0000;
const float CINE_JET_ANGLE      = 0.1800;
const float CINE_JET_BETA       = 0.9000;
const float CINE_FILM_GRAIN     = 0.0080;
const float CINE_VIGNETTE       = 0.0800;
const float CINE_RING_CA        = 0.0000;
const float CINE_ACES           = 1.0000;

#if QUALITY_LEVEL == QUALITY_MAXIMUM
#define N_STEPS 128
#elif QUALITY_LEVEL == QUALITY_BALANCED
#define N_STEPS 80
#else
#define N_STEPS 48
#endif

// ---------------------------------------------------------------- size mode --
// What drives the hole's growth — the master intensity I that every visual
// (size, lensing, disk, dilation) feeds off. More modes to come.
#define MODE_POMODORO 0   // wall/session-clock 55/5 cycle + typing detector
#define MODE_TOKENS   1   // Claude Code context-window fill (live; see README)
#define MODE_DEMO     2   // self-running 42 s showcase loop for recording (see below)
#define SIZE_MODE MODE_TOKENS

// Live state for MODE_TOKENS rides in on the *cursor color*: claude-token.py
// encodes the context fill into an OSC 12 cursor color and the shader decodes
// it from iCurrentCursorColor every frame — no file rewrite, no reload, no
// recompile hitch, and each Ghostty surface gets its own hole. Encoding (keep
// in sync with the script's CURSOR_BASE): high nibbles are the fixed amber
// base #F_B_0_, low nibbles carry a 4-bit checksum and the fill byte — 16
// bits must line up before a color is trusted, so a theme's own cursor color
// can't accidentally drive the hole.
//   no signal in the color -> no Claude session -> hole is hidden entirely
//   fill byte 0            -> fresh session -> tiny seed hole in the corner
//   fill byte 1..250       -> context fill /250 -> grows, speeds up, roams
// TOKEN_LEVEL is a manual fallback used only when the cursor carries no
// signal — handy for hand-testing a size (edit + reload). Set it back to -1
// to hide the hole when no Claude token signal is present.
#define TOKEN_LEVEL 0.35 // token-level

const ivec3 TOKEN_BASE_HI = ivec3(0xF, 0xB, 0x0); // cursor-channel base, high nibbles

float tokenFromBytes(ivec3 v) {
    ivec3 lo = v & 0xF;
    if ((v >> 4) != TOKEN_BASE_HI || lo.r != (lo.g ^ lo.b ^ 0x5)) return -1.0;
    int fill = (lo.g << 4) | lo.b;
    return fill > 250 ? -1.0 : float(fill) / 250.0;
}

// Context fill decoded from one cursor color, or -1 when no signal.
// Ghostty hands the color over as plain sRGB bytes / 255 — no linearization,
// no premultiply (src/renderer/generic.zig) — so the raw decode is exact; the
// second attempt un-linearizes first in case a future renderer changes that.
float tokenDecode(vec3 cc) {
    vec3 c = clamp(cc, 0.0, 1.0);
    float lvl = tokenFromBytes(ivec3(floor(c * 255.0 + 0.5)));
    if (lvl >= 0.0) return lvl;
    vec3 s = mix(c * 12.92, 1.055 * pow(max(c, 1e-6), vec3(1.0 / 2.4)) - 0.055,
                 step(0.0031308, c));
    return tokenFromBytes(ivec3(floor(clamp(s, 0.0, 1.0) * 255.0 + 0.5)));
}

// Level updates arrive as discrete steps (1% statusline ticks), and a step in
// the level steps the whole warp field — size, lensing, roam box — in a
// single frame, which reads as a jerk. The shader is stateless, but Ghostty
// bumps iTimeCursorChange on ANY cursor change *including color* and
// snapshots the prior color into iPreviousCursorColor at that moment
// (src/renderer/generic.zig), so we can glide from the previous encoded
// level to the current one. A plain cursor *move* copies current into
// previous (same level twice), which merely ends a glide early — worst case
// is the old instant step.
//
// The glide duration scales with the jump. Small ticks must stay at the
// cadence floor: the snapshot is the previous *emitted* level, not the
// mid-glide display value, so during a rapid stream of 1% ticks (~300 ms
// apart) a longer glide would restart from too far back and stutter. Big
// isolated jumps (a heavy turn, the post-/compact snap-back) have no next
// tick breathing down their neck and can take their time.
const float TOKEN_GLIDE_MIN  = 0.0800; // glide floor, seconds — keep at the statusline refresh cadence
const float TOKEN_GLIDE_MAX  = 0.5500; // glide cap for huge jumps, seconds
const float TOKEN_GLIDE_RATE = 3.0000; // glide seconds per unit of level jump (3 -> a 10% jump glides for 0.3 s)

float tokenLevel() {
    float cur = tokenDecode(iCurrentCursorColor.rgb);
    if (cur < 0.0) return -1.0;
    float prev = tokenDecode(iPreviousCursorColor.rgb);
    if (prev < 0.0) return cur;
    float glideLo = min(TOKEN_GLIDE_MIN, TOKEN_GLIDE_MAX);
    float glideHi = max(TOKEN_GLIDE_MIN, TOKEN_GLIDE_MAX);
    float T = max(clamp(abs(cur - prev) * TOKEN_GLIDE_RATE,
                        glideLo, glideHi), 1e-5);
    return mix(prev, cur, smoothstep(0.0, T, iTime - iTimeCursorChange));
}

// ------------------------------------------------------------- demo mode --
// MODE_DEMO is a self-running 42 s showcase loop for recording: the hole
// grows from the corner seed to 100% exactly as MODE_TOKENS would (the level
// ramps over DEMO_GROW_SEC, then holds full size for the rest of the loop),
// while the disk look tours the tuner presets, crossfading near each slot
// boundary. Everything runs off iTime inside one compiled shader — no file
// rewrites, no reloads, no recompile hitches mid-recording. The tour starts
// and ends on Inferno (the defaults), so the only visible loop seam is the
// hole snapping back to the corner seed. ./demo-mode.sh on|off flips
// SIZE_MODE and reloads Ghostty.
const float DEMO_SEC      = 42.0000; // full loop length, seconds
const float DEMO_GROW_SEC = 40.0000; // 0 -> 100% over this; holds full after
const float DEMO_XFADE    = 0.1800; // preset crossfade, fraction of a slot

// The disk's whole look in one bundle, so the demo can blend presets; in the
// other modes it just carries the tunables above and the compiler folds it
// back to the same constants.
struct DiskLook {
    float temp, incl, roll, inner, outer, opac, dopp, beam,
          gain, contr, wind, speed, expo, star, thick, turb,
          filSharp, warp, armCount, armTwist, armSharp, armStr;
};
const DiskLook LOOK_DEFAULT = DiskLook(
    DISK_TEMP, DISK_INCL, DISK_ROLL, DISK_INNER, DISK_OUTER, DISK_OPACITY,
    DOPPLER_MIX, DISK_BEAM, DISK_GAIN, DISK_CONTRAST, DISK_WIND, DISK_SPEED,
    EXPOSURE, STAR_GAIN, DISK_THICKNESS, DISK_TURBULENCE,
    DISK_FILAMENT_SHARPNESS, DISK_WARP_STRENGTH, DISK_ARM_COUNT, DISK_ARM_TWIST,
    DISK_ARM_SHARPNESS, DISK_ARM_STRENGTH);
#define DEMO_N 8
// the tuner's presets (ParamSpec.swift), ~5.25 s each; Zen is skipped (too
// subtle to read in a quick demo) and the layered default bookends the loop
const DiskLook DEMO_TOUR[DEMO_N] = DiskLook[DEMO_N](
    //        temp    incl  roll   inner outer opac  dopp  beam gain contr wind speed expo star thick turb  filSh warp arms twist aSharp aStr
    DiskLook( 9000.0, 1.48,  0.18, 1.35, 10.0, 0.78, 0.90, 3.0, 1.6, 1.05, 6.0, 3.6, 1.00, 0.0, 0.12, 0.70,  2.2, 0.5, 2.0, 3.0,  3.0, 0.50), // layered
    DiskLook( 6500.0, 1.52,  0.10, 1.35,  8.0, 0.82, 0.55, 2.2, 1.4, 0.45, 5.0, 3.0, 1.10, 0.0, 0.08, 0.35,  1.8, 0.3, 2.0, 2.0,  2.5, 0.35), // gargantua
    DiskLook( 4200.0, 0.55, -0.30, 1.50,  6.0, 0.45, 0.95, 3.5, 1.6, 0.40, 3.0, 2.5, 1.05, 0.0, 0.22, 0.55,  1.5, 0.6, 1.0, 1.5,  2.0, 0.25), // m87* donut
    DiskLook( 7500.0, 0.30,  0.00, 1.60, 10.0, 0.50, 0.85, 2.8, 1.0, 0.90, 5.0, 3.0, 0.95, 0.0, 0.10, 0.65,  2.0, 0.5, 3.0, 2.5,  2.5, 0.40), // face-on ember
    DiskLook(15000.0, 1.30,  0.35, 1.50, 14.0, 0.35, 1.00, 4.0, 1.2, 1.30, 8.0, 5.0, 0.80, 0.0, 0.16, 0.85,  2.6, 0.7, 2.0, 4.0,  3.5, 0.60), // quasar
    DiskLook(18000.0, 1.05,  0.55, 1.40, 16.0, 0.30, 1.00, 5.0, 1.0, 1.50, 9.0, 6.0, 0.75, 0.0, 0.18, 0.95,  3.0, 0.8, 3.0, 5.0,  4.0, 0.70), // blazar
    DiskLook( 9000.0, 1.48,  0.18, 1.35, 10.0, 0.00, 1.00, 3.0, 0.0, 0.20, 4.0, 2.0, 1.00, 0.6, 0.08, 0.20,  2.2, 0.0, 2.0, 3.0,  3.0, 0.00), // pure lens
    DiskLook( 9000.0, 1.48,  0.18, 1.35, 10.0, 0.78, 0.90, 3.0, 1.6, 1.05, 6.0, 3.6, 1.00, 0.0, 0.12, 0.70,  2.2, 0.5, 2.0, 3.0,  3.0, 0.50)); // layered

DiskLook mixLook(DiskLook a, DiskLook b, float f) {
    return DiskLook(
        mix(a.temp,  b.temp,  f), mix(a.incl,  b.incl,  f),
        mix(a.roll,  b.roll,  f), mix(a.inner, b.inner, f),
        mix(a.outer, b.outer, f), mix(a.opac,  b.opac,  f),
        mix(a.dopp,  b.dopp,  f), mix(a.beam,  b.beam,  f),
        mix(a.gain,  b.gain,  f), mix(a.contr, b.contr, f),
        mix(a.wind,  b.wind,  f), mix(a.speed, b.speed, f),
        mix(a.expo,  b.expo,  f), mix(a.star,  b.star,  f),
        mix(a.thick, b.thick, f), mix(a.turb,  b.turb,  f),
        mix(a.filSharp, b.filSharp, f), mix(a.warp, b.warp, f),
        mix(a.armCount, b.armCount, f), mix(a.armTwist, b.armTwist, f),
        mix(a.armSharp, b.armSharp, f), mix(a.armStr, b.armStr, f));
}

DiskLook demoLook() {
    float demoSec = max(DEMO_SEC, 1e-4);
    float u = mod(iTime, demoSec) / demoSec * float(DEMO_N); // 0..N slot clock
    int   i = int(min(u, float(DEMO_N) - 0.001));
    float xfade = clamp(DEMO_XFADE, 1e-4, 1.0);
    float f = smoothstep(1.0 - xfade, 1.0, fract(u));          // blend at slot end
    return mixLook(DEMO_TOUR[i], DEMO_TOUR[(i + 1) % DEMO_N], f);
}

// ------------------------------------------------------ pomodoro, self-contained --
// Shaders have no memory between frames. Use wall time when iDate.w is
// available and Ghostty's session clock otherwise: the hole grows over each
// WORK_PERIOD_MIN, collapses as break time arrives, and stays gone for
// BREAK_MIN. Independently, iTimeCursorChange acts as a live typing detector.
const float WORK_PERIOD_MIN = 55.0000; // work minutes per cycle (growth phase)
const float BREAK_MIN       = 5.0000; // break minutes per cycle (hole gone)
const float IDLE_FADE_SEC   = 90.0000; // typing pause at which fading starts
const float TIME_SCALE      = 1.0000; // TESTING: 1 = normal clock; >1 fast-forwards growth via iTime (100 -> a full cycle in ~36 s). Set back to 1 for normal use.

// critical impact parameter of a Schwarzschild hole, in r_s: rays under this
// fall in; it is the apparent (shadow) radius seen from far away. Physics,
// not taste — a #define so the tuner can't drift it (when it was
// a const float, a stray slider drag in the tuner's "Other" group silently
// shrank every size mode by ~4.6x).
#define B_CRIT 2.5980762

// ------------------------------------------------------------------- noise --
float hash21(vec2 p) {
    p = fract(p * vec2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

// value noise whose y lattice wraps every perY cells — used for the disk's
// angular dimension so the streaks tile seamlessly across the atan branch cut
// (perY must be an integer; y must advance by exactly perY per full turn)
float vnoiseWrapY(vec2 p, float perY) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float y0 = mod(i.y, perY), y1 = mod(i.y + 1.0, perY);
    return mix(mix(hash21(vec2(i.x, y0)),       hash21(vec2(i.x + 1.0, y0)), f.x),
               mix(hash21(vec2(i.x, y1)),       hash21(vec2(i.x + 1.0, y1)), f.x),
               f.y);
}

float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
               mix(hash21(i + vec2(0.0, 1.0)),
                   hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

// mirrored repeat keeps lensed samples on-screen without edge smearing
vec2 mirrorUV(vec2 u) { return 1.0 - abs(1.0 - mod(u, 2.0)); }

vec2 screenUV(vec2 nativeCoord) {
#if GHOSTTY_Y_DOWN
    return nativeCoord;
#else
    return vec2(nativeCoord.x, 1.0 - nativeCoord.y);
#endif
}

vec2 textureUV(vec2 screenCoord) {
#if GHOSTTY_Y_DOWN
    return screenCoord;
#else
    return vec2(screenCoord.x, 1.0 - screenCoord.y);
#endif
}

vec2 rot(vec2 v, float a) {
    float c = cos(a), s = sin(a);
    return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// unit Lissajous wander: 2+2 incommensurate sines per axis, so the orbit
// never visibly repeats; scale the argument for speed, the result for reach
vec2 lissa(float t) {
    return vec2(0.75 * sin(t * 0.37) + 0.25 * sin(t * 0.83 + 1.0),
                0.70 * sin(t * 0.54 + 2.1) + 0.30 * sin(t * 1.07));
}

// Relative fraction of blackbody power landing in the CIE photopic response,
// fitted in log-temperature to a numerical Planck × CIE-y integral and
// normalized at 6500 K. This prevents cool/redshifted bolometric power from
// being incorrectly treated as equally visible RGB light.
float blackbodyVisibleEfficiency(float T) {
    // Below 500 K the visible fraction is astronomically negligible. Above
    // the fitted range, the Rayleigh-Jeans visible integral grows as T while
    // bolometric power grows as T^4, giving the T^-3 continuation.
    if (T < 500.0) return 0.0;
    float fitT = min(T, 100000.0);
    float x = log(fitT / 6500.0);
    float logEfficiency = x <= 0.0
        ? x * (0.09010161 + x * (-1.73784068 +
          x * (0.87094001 + x * (0.00243985 +
          x * 0.06190682))))
        : x * (0.06434657 + x * (-1.81558284 +
          x * (0.65987305 + x * (-0.13876271 +
          x * 0.01274781))));
    float efficiency = exp(logEfficiency);
    if (T > 100000.0)
        efficiency *= pow(100000.0 / T, 3.0);
    return efficiency;
}

// Planckian-locus chromaticity (CIE 1931 xy) converted to linear sRGB.
// The Y=1 chromaticity is scaled by the visible-power fit above; local T^4
// and Kerr g^4 then carry bolometric power and relativistic transport.
vec3 blackbodyLinear(float T) {
    float visibleEfficiency = blackbodyVisibleEfficiency(T);
    float chromaT = clamp(T, 500.0, 100000.0);
    float x;
    float y;
    if (chromaT < 1667.0) {
        // Log-temperature extension fitted to Planck × CIE 1931 integration,
        // constrained to meet the standard 1667 K locus continuously.
        float u = log(chromaT / 1667.0);
        x = 0.56463863 + u * (-0.16381365 +
            u * (0.01386265 + u * (0.08098260 +
            u * 0.01099022)));
        y = 0.40288703 + u * (0.03805963 +
            u * (-0.20382265 + u * (-0.21221117 -
            u * 0.04559722)));
    } else if (chromaT <= 25000.0) {
        // Published Planckian-locus fit over its native range.
        float T2 = chromaT * chromaT;
        float T3 = T2 * chromaT;
        x = chromaT <= 4000.0
          ? -0.2661239e9 / T3 - 0.2343580e6 / T2 +
             0.8776956e3 / chromaT + 0.179910
          : -3.0258469e9 / T3 + 2.1070379e6 / T2 +
             0.2226347e3 / chromaT + 0.240390;
        float x2 = x * x;
        float x3 = x2 * x;
        if (chromaT <= 2222.0)
            y = -1.1063814 * x3 - 1.3481102 * x2 +
                 2.1855583 * x - 0.2021968;
        else if (chromaT <= 4000.0)
            y = -0.9549476 * x3 - 1.3741859 * x2 +
                 2.0913702 * x - 0.1674887;
        else
            y = 3.0817580 * x3 - 5.8733867 * x2 +
                3.7511300 * x - 0.3700148;
    } else {
        // Hot-end CIE integration fit, continuous at 25,000 K.
        float u = log(chromaT / 25000.0);
        x = 0.25247299 + u * (-0.01375145 +
            u * (0.00673976 - u * 0.00136322));
        y = 0.25225483 + u * (-0.02047613 +
            u * (0.01077476 - u * 0.00246071));
    }

    float X = x / max(y, 1e-4);
    float Z = (1.0 - x - y) / max(y, 1e-4);
    vec3 rgb = max(vec3( 3.2406 * X - 1.5372 - 0.4986 * Z,
                        -0.9689 * X + 1.8758 + 0.0415 * Z,
                         0.0557 * X - 0.2040 + 1.0570 * Z), vec3(0.0));
    return rgb * visibleEfficiency;
}

vec3 filmicTonemap(vec3 x) {
    x = max(x, vec3(0.0));
    return clamp((x * (2.51 * x + 0.03)) /
                 (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);
}

#if CINEMATIC
vec3 cineACES(vec3 x) {
    x = max(x, vec3(0.0));
    // These published transforms are conventionally written row-major.
    // GLSL constructors consume columns, so spell the transpose explicitly;
    // using the printed row order here creates the magenta/green casts that
    // ACES is supposed to remove.
    const mat3 a = mat3(0.59719, 0.07600, 0.02840,
                        0.35458, 0.90834, 0.13383,
                        0.04823, 0.01566, 0.83777);
    const mat3 b = mat3( 1.60475, -0.10208, -0.00327,
                        -0.53108,  1.10813, -0.07276,
                        -0.07367, -0.00605,  1.07602);
    x = a * x;
    x = (x * (x + 0.0245786) - 0.000090537) /
        (x * (0.983729 * x + 0.4329510) + 0.238081);
    return clamp(b * x, 0.0, 1.0);
}

vec3 cineDiskTone(vec3 x) {
    return CINE_ACES > 0.5 ? cineACES(x) : filmicTonemap(x);
}
#endif

float kerrHorizon(float spin) {
    float a = clamp(abs(spin), 0.0, 0.998);
    return 0.5 * (1.0 + sqrt(max(1.0 - a * a, 0.0)));
}

// Circular equatorial Kerr ISCO, converted from GM/c^2 to the shader's
// r_s = 2GM/c^2. orbitDirection is +1 prograde or -1 retrograde.
float kerrISCO(float spin, float orbitDirection) {
    float a = clamp(spin, 0.0, 0.998);
    float oneMinus = max(1.0 - a * a, 0.0);
    float z1 = 1.0 + pow(oneMinus, 1.0 / 3.0) *
                     (pow(1.0 + a, 1.0 / 3.0) + pow(1.0 - a, 1.0 / 3.0));
    float z2 = sqrt(3.0 * a * a + z1 * z1);
    float branch = orbitDirection < 0.0 ? -1.0 : 1.0;
    float rM = 3.0 + z2 - branch *
               sqrt(max((3.0 - z1) * (3.0 + z1 + 2.0 * z2), 0.0));
    return 0.5 * rM;
}

// Frequency shift for a circular equatorial Kerr emitter observed at
// infinity: g = 1 / (u^t (1 - Omega lambda)).
float kerrCircularRedshift(float radiusRs, float spin,
                           float orbitDirection, float photonLambda) {
    float R = max(2.0 * radiusRs, 1.01);
    float a = clamp(spin, 0.0, 0.998);
    float sdir = orbitDirection < 0.0 ? -1.0 : 1.0;
    float gtt = -(1.0 - 2.0 / R);
    float gtphi = -2.0 * a / R;
    float gphiphi = R * R + a * a + 2.0 * a * a / R;
    float omega = sdir / max(pow(R, 1.5) + sdir * a, 0.05);
    float utInvSq = -(gtt + 2.0 * gtphi * omega +
                      gphiphi * omega * omega);
    float ut = inversesqrt(max(utInvSq, 1e-4));
    return 1.0 / max(ut * (1.0 - omega * photonLambda), 0.04);
}

float kerrBoyerLindquistRadius(float radiusRs, float heightRs,
                               float spin) {
    float a = clamp(spin, 0.0, 0.998);
    float rho2 = 4.0 * radiusRs * radiusRs; // shader r_s -> M=1
    float zM = 2.0 * heightRs;
    float oblate = rho2 - a * a;
    float R2 = 0.5 * (oblate +
                       sqrt(max(oblate * oblate +
                                4.0 * a * a * zM * zM, 0.0)));
    return sqrt(max(R2, 0.0));
}

// Stationary, axisymmetric off-plane emitter shift in the Kerr metric.
// The Cartesian marcher is only Kerr-inspired, so map its point to oblate
// Boyer-Lindquist coordinates, then blend a safe local ZAMO angular velocity
// toward disk rotation where the corona actually hugs the disk. Near the
// horizon the blend becomes ZAMO-like and the lapse drives g toward zero.
float kerrCoronaRedshift(float blRadiusM, float heightRs,
                         float cylindricalRs, float spin,
                         float orbitDirection, float photonLambda,
                         float diskCoupling) {
    float a = clamp(spin, 0.0, 0.998);
    float zM = 2.0 * heightRs;
    float R = max(blRadiusM, 1e-5);
    float R2 = R * R;
    float rPlus = 1.0 + sqrt(max(1.0 - a * a, 0.0));
    if (R <= rPlus * 1.0001) return 0.0;
    float cos2 = clamp(zM * zM / max(R2, 1e-5), 0.0, 1.0);
    float sin2 = max(1.0 - cos2, 1e-5);
    float sigma = R2 + a * a * cos2;
    float delta = R2 - 2.0 * R + a * a;
    if (delta <= 0.0) return 0.0;
    float bigA = (R2 + a * a) * (R2 + a * a) -
                 a * a * delta * sin2;
    float gtt = -(1.0 - 2.0 * R / max(sigma, 1e-5));
    float gtphi = -2.0 * a * R * sin2 / max(sigma, 1e-5);
    float gphiphi = bigA * sin2 / max(sigma, 1e-5);
    float omegaZamo = 2.0 * a * R / max(bigA, 1e-5);
    float sdir = orbitDirection < 0.0 ? -1.0 : 1.0;
    float cylindricalM = max(2.0 * cylindricalRs, 1.01);
    float omegaDisk = sdir /
                      max(pow(cylindricalM, 1.5) + sdir * a, 0.05);
    float coupling = clamp(diskCoupling, 0.0, 0.85);
    float omega = mix(omegaZamo, omegaDisk, coupling);
    float utInvSq = -(gtt + 2.0 * gtphi * omega +
                      gphiphi * omega * omega);
    if (utInvSq <= 1e-6) {
        omega = omegaZamo;
        utInvSq = -(gtt + 2.0 * gtphi * omega +
                    gphiphi * omega * omega);
    }
    float ut = inversesqrt(max(utInvSq, 1e-8));
    return 1.0 / max(ut * (1.0 - omega * photonLambda), 1e-5);
}

// Exact Kerr capture test at infinity. The real-time trajectory below keeps
// the stable Cartesian Schwarzschild + frame-dragging approximation, but the
// shadow itself must never inherit that approximation's strong-field leaks.
// For image-plane impact (alpha,beta), a Kerr photon is captured iff its
// radial potential has no turning point outside r+. Coordinates here are
// converted from the shader's r_s units to the standard M=1 units.
float kerrRadialPotential(float r, float xi, float eta, float a) {
    float delta = r * r - 2.0 * r + a * a;
    float P = r * r + a * a - a * xi;
    return (P * P - delta * (eta + (xi - a) * (xi - a))) /
           max(r * r * r * r, 1e-4);
}

// R/r^4 = 1 + c2/r^2 + c1/r^3 + c0/r^4, so every finite
// stationary point is a root of 2*c2*r^2 + 3*c1*r + 4*c0.
// Testing those roots, r+, and infinity is an exact global minimum test and
// avoids both the missed narrow wells and dozens of exp() calls from a grid.
float kerrEscapeSignedGradient(vec2 impact, float incl, float spin,
                               out vec2 signedGradient) {
    float a = clamp(spin, 0.0, 0.998);
    float b = length(impact);
    if (a < 1e-3) {
        signedGradient = impact / max(b, 1e-6);
        return b - B_CRIT;
    }

    float alpha = 2.0 * impact.x;
    float beta = 2.0 * impact.y;
    float si = max(sin(incl), 1e-3);
    float ci = cos(incl);
    float xi = -alpha * si;
    float eta = beta * beta + (alpha * alpha - a * a) * ci * ci;
    float rPlus = 1.0 + sqrt(max(1.0 - a * a, 0.0));
    float A = a * a - a * xi;
    float K = eta + (xi - a) * (xi - a);
    float c2 = 2.0 * A - K;
    float c1 = 2.0 * K;
    float c0 = A * A - a * a * K;
    float qa = 2.0 * c2;
    float qb = 3.0 * c1;
    float qc = 4.0 * c0;
    float lower = rPlus * 1.000001;
    float lowerPotential = kerrRadialPotential(lower, xi, eta, a);
    float minPotential = min(1.0, lowerPotential);
    float minRadius = lowerPotential < 1.0 ? lower : 1e20;

    if (abs(qa) > 1e-7) {
        float discriminant = qb * qb - 4.0 * qa * qc;
        if (discriminant >= 0.0) {
            float rootDisc = sqrt(discriminant);
            float r1 = (-qb - rootDisc) / (2.0 * qa);
            float r2 = (-qb + rootDisc) / (2.0 * qa);
            if (r1 > lower) {
                float v1 = kerrRadialPotential(r1, xi, eta, a);
                if (v1 < minPotential) {
                    minPotential = v1;
                    minRadius = r1;
                }
            }
            if (r2 > lower) {
                float v2 = kerrRadialPotential(r2, xi, eta, a);
                if (v2 < minPotential) {
                    minPotential = v2;
                    minRadius = r2;
                }
            }
        }
    } else if (abs(qb) > 1e-7) {
        float r1 = -qc / qb;
        if (r1 > lower) {
            float v1 = kerrRadialPotential(r1, xi, eta, a);
            if (v1 < minPotential) {
                minPotential = v1;
                minRadius = r1;
            }
        }
    }

    // At a stationary minimum, the envelope theorem gives the image-plane
    // gradient from the partial derivatives of R/r^4 alone. This is the exact
    // one-pixel AA scale without four neighboring Kerr solves or implicit
    // screen derivatives.
    if (minRadius < 1e10) {
        float r2 = minRadius * minRadius;
        float r4 = r2 * r2;
        float delta = r2 - 2.0 * minRadius + a * a;
        float P = r2 + a * a - a * xi;
        float dQdXi = (-2.0 * a * P -
                       2.0 * delta * (xi - a)) / max(r4, 1e-6);
        float dQdEta = -delta / max(r4, 1e-6);
        float dXiDx = -2.0 * si;
        float dEtaDx = 8.0 * impact.x * ci * ci;
        float dEtaDy = 8.0 * impact.y;
        signedGradient = -vec2(
            dQdXi * dXiDx + dQdEta * dEtaDx,
            dQdEta * dEtaDy);
    } else {
        signedGradient = vec2(0.0);
    }

    // Negative potential means an exterior forbidden band and therefore a
    // turning/escaping ray; positive everywhere means capture.
    return -minPotential;
}

float kerrEscapeSigned(vec2 impact, float incl, float spin) {
    vec2 ignoredGradient;
    return kerrEscapeSignedGradient(impact, incl, spin, ignoredGradient);
}

float kerrEscapeMask(vec2 impact, float pixelWorld,
                     float incl, float spin,
                     out float edgeDistancePixels) {
    float b = length(impact);
    // Conservative regions known to be well away from every Kerr critical
    // curve. No implicit derivatives occur in varying control flow.
    edgeDistancePixels = 1e6;
    if (b < 0.70) return 0.0;
    if (b > 4.00) return 1.0;

    vec2 signedGradient;
    float signedEscape = kerrEscapeSignedGradient(
        impact, incl, spin, signedGradient);
    float onePixel = max(length(signedGradient) *
                         max(pixelWorld, 1e-5), 1e-6);
    edgeDistancePixels = abs(signedEscape) / onePixel;
    float aa = onePixel * 1.35;
    return smoothstep(-aa, aa, signedEscape);
}

// Schwarzschild's exact planar term plus the leading gravitomagnetic field
// of a spinning mass. This is a stable Kerr approximation rather than a
// Boyer-Lindquist geodesic solver, but it produces frame dragging without a
// painted shadow offset.
vec3 rayAcceleration(vec3 x, vec3 v, float h2,
                     vec3 spinAxis, float spin,
                     float r2, float r) {
    r2 = max(r2, 1e-5);
    r = max(r, sqrt(1e-5));
    vec3 central = -1.5 * h2 * x / (r2 * r2 * r);
    vec3 rhat = x / r;
    vec3 angularMomentum = spinAxis * (0.25 * clamp(spin, -0.998, 0.998));
    vec3 gravitoMagnetic = (angularMomentum - 3.0 * rhat * dot(angularMomentum, rhat)) /
                          (r2 * r);
    return central + 2.0 * cross(v, gravitoMagnetic);
}

float diskNoise(float radius, float turns, float phase, float winding) {
    float n = 0.58 * vnoiseWrapY(vec2(radius * 0.55,
                                      turns * 7.0 + phase + radius * winding * 0.12), 7.0);
#if QUALITY_LEVEL >= QUALITY_BALANCED
    n += 0.27 * vnoiseWrapY(vec2(radius * 1.35,
                                 turns * 17.0 + phase * 1.9 + radius * winding * 0.25), 17.0);
#endif
#if QUALITY_LEVEL == QUALITY_MAXIMUM
    n += 0.10 * vnoiseWrapY(vec2(radius * 3.10,
                                 turns * 37.0 + phase * 3.7 + radius * winding * 0.53), 37.0);
    n += 0.05 * vnoiseWrapY(vec2(radius * 6.20,
                                 turns * 71.0 + phase * 7.1 + radius * winding), 71.0);
#endif
#if QUALITY_LEVEL == QUALITY_LIGHTWEIGHT
    return n / 0.58;
#elif QUALITY_LEVEL == QUALITY_BALANCED
    return n / 0.85;
#else
    return n;
#endif
}

// A fixed distant sky keyed by the same unmirrored plane coordinate used for
// terminal sampling. Unlike direction hashing under an orthographic camera,
// this produces a stable field across the whole screen; feeding it the
// geodesic's sky hit makes individual stars split into arcs and secondary
// images instead of swimming with the moving hole.
vec3 starsPlane(vec2 skyUV) {
    float aspect = iResolution.x / iResolution.y;
    vec2 metricUV = skyUV * vec2(aspect, 1.0);
    vec2 grid = metricUV * 76.0;
    vec2 id = floor(grid);
    vec2 f = fract(grid) - 0.5;
    float h = hash21(id);
    vec2 off = (vec2(hash21(id + 19.7), hash21(id + 47.1)) - 0.5) * 0.72;
    float d = length(f - off);
    float population = clamp((h - 0.935) / 0.065, 0.0, 1.0);
    float radius = mix(0.045, 0.095, population);
    float core = (1.0 - smoothstep(radius * 0.30, radius, d)) *
                 population;
    vec3 tint = mix(vec3(1.0, 0.68, 0.42), vec3(0.58, 0.76, 1.0),
                    hash21(id + 7.3));
    vec3 star = tint * core * mix(0.8, 4.5, population * population);

#if CINEMATIC
    if (h > 0.992) {
        vec2 delta = f - off;
        // Pixel-aware width plus a radial envelope keeps diffraction spikes
        // stable and prevents square, cell-edge truncation.
        float lineWidth = max(0.012, 0.65 * 76.0 / iResolution.y);
        float rays = exp(-abs(delta.x) / lineWidth) +
                     exp(-abs(delta.y) / lineWidth);
        float rayEnvelope = 1.0 - smoothstep(0.10, 0.38, d);
        star += tint * rays * rayEnvelope * (h - 0.992) / 0.008;
    }
    vec2 centered = (skyUV - 0.5) * vec2(aspect, 1.0);
    float dustAxis = centered.y + 0.10 * sin(centered.x * 3.7 + 0.8);
    float band = exp(-pow(dustAxis / 0.22, 2.0));
    float cloud = 0.38 + 0.62 *
                  vnoise(metricUV * 5.5 +
                         0.45 * vec2(vnoise(metricUV * 2.1),
                                     vnoise(metricUV * 2.1 + 13.7)));
    vec3 dust = mix(vec3(0.12, 0.07, 0.035),
                    vec3(0.035, 0.08, 0.16),
                    smoothstep(-0.18, 0.18, dustAxis));
    star += dust * band * cloud * 0.22 * CINE_SKY_GAIN;
#endif
    return star;
}

vec3 finishDiskRadiance(vec3 disk, vec2 p, float rh) {
    disk = max(disk, vec3(0.0));
#if CINEMATIC
    float radius = length(p);
    float vignette = 1.0 - CINE_VIGNETTE *
                     smoothstep(0.20, 1.20,
                                radius / max(7.0 * rh, 1e-4));
    vec3 toned = cineDiskTone(disk * vignette);
    // Grain belongs after the nonlinear display transform and is keyed to
    // actual screen pixels. Multiplicative, emission-gated grain cannot light
    // the empty sky or the shadow.
    float grain = (hash21(p * iResolution.y + vec2(iTime, 17.0)) - 0.5) *
                  CINE_FILM_GRAIN;
    float emissionMask = smoothstep(0.002, 0.12,
                                    max(max(toned.r, toned.g), toned.b));
    return max(toned * (1.0 + grain * emissionMask), vec3(0.0));
#else
    return filmicTonemap(disk);
#endif
}

// Signed antiderivative of the disk's vertical density profile:
// w=1 inside 0.35H, then a cubic smoothstep taper to zero at H.
float diskVerticalPrimitive(float z, float halfHeight) {
    float u = clamp(abs(z) / max(halfHeight, 1e-6), 0.0, 1.0);
    float integral;
    if (u <= 0.35) {
        integral = u;
    } else {
        float t = (u - 0.35) / 0.65;
        float t2 = t * t;
        integral = 0.35 + 0.65 *
                   (t - t * t2 + 0.5 * t2 * t2);
    }
    return (z < 0.0 ? -1.0 : 1.0) * halfHeight * integral;
}

vec3 traceNearField(vec2 p, vec2 center, float W, float rh,
                    float window, float shield, float t, float dil,
                    DiskLook L, float rin, float rout,
                    float spin, float horizon, bool includeBackground,
                    out vec3 diskLinearOutput) {
    vec2 pr = rot(vec2(p.x, -p.y), L.roll) * W;
    float Z0 = max(14.0, rout + 5.0);
    vec3 x = vec3(pr, Z0);
    vec3 v = vec3(0.0, 0.0, -1.0);
    float h2 = dot(pr, pr);

    float ci = cos(L.incl), si = sin(L.incl);
    vec3 n = vec3(0.0, si, ci);
    vec3 e2 = vec3(0.0, ci, -si);
    float sdir = L.speed < 0.0 ? -1.0 : 1.0;
    float patternSpeed = abs(L.speed);
    // Kerr's conserved axial impact parameter Lz/E in units of GM/c².
    // The ray is traced backward, hence the sign relative to x cross v.
    float photonLambda = -2.0 * dot(cross(x, normalize(v)), n);

    vec3 emitc = vec3(0.0);
    float trans = 1.0;
    bool captured = false;
    bool escaped = false;
    float sPrev = dot(x, n);
    vec3 xPrev = x;

    for (int i = 0; i < N_STEPS; i++) {
        float r2 = dot(x, x);
        float r = sqrt(r2);
        if (r < horizon) { captured = true; break; }
        if (x.z < -Z0 && v.z < 0.0) { escaped = true; break; }
        if (r2 > 4.0 * Z0 * Z0) { escaped = true; break; }

        // Spend integration steps where curvature changes fastest. Rays near
        // the photon region get roughly three times the resolution of the
        // approach and escape legs.
        float strongField = 1.0 - smoothstep(0.35, 2.4, abs(r - 1.5));
        float dt = clamp(mix(0.15, 0.055, strongField) * r, 0.015, 1.30);
        vec3 a = rayAcceleration(x, v, h2, n, spin, r2, r);
        v += a * (0.5 * dt);
        x += v * dt;
        float rNow2 = dot(x, x);
        float rNow = sqrt(rNow2);
        a = rayAcceleration(x, v, h2, n, spin, rNow2, rNow);
        v += a * (0.5 * dt);
        vec3 segment = x - xPrev;
        float segmentLength = -1.0; // evaluated lazily only for emitting matter

        // Integrate emission and absorption through a finite disk volume.
        // The closest point on this ray segment catches a thin slab even when
        // an adaptive step enters and exits it in one iteration.
        float s = dot(x, n);
        float planeDelta = sPrev - s;
        float tc = abs(planeDelta) < 1e-6
                 ? 0.5
                 : clamp(sPrev / planeDelta, 0.0, 1.0);
        vec3 xc = mix(xPrev, x, tc);
        vec2 diskPos = vec2(xc.x, dot(xc, e2));
        float rc = length(diskPos);
        float halfHeight = max(0.015, L.thick * rc);
        if (rc > rin && rc < rout && trans > 0.01) {
            float ds = s - sPrev;
            float slabEnter = 0.0;
            float slabLeave = 0.0;
            if (abs(ds) < 1e-7) {
                slabLeave = abs(sPrev) < halfHeight ? 1.0 : 0.0;
            } else {
                float ta = (-halfHeight - sPrev) / ds;
                float tb = ( halfHeight - sPrev) / ds;
                slabEnter = max(0.0, min(ta, tb));
                slabLeave = min(1.0, max(ta, tb));
            }
            float slabFraction = max(slabLeave - slabEnter, 0.0);
            float zEnter = sPrev + ds * slabEnter;
            float zLeave = sPrev + ds * slabLeave;
            // Exact integral of the tapered vertical profile over the clipped
            // segment. A perpendicular -H..H crossing is exactly 1.35H,
            // independent of the adaptive march step.
            float pathInDisk = 0.0;
            if (slabFraction > 0.0) {
                segmentLength = length(segment);
                if (abs(ds) < 1e-7) {
                    float verticalWeight =
                        1.0 - smoothstep(0.35 * halfHeight, halfHeight,
                                         abs(sPrev));
                    pathInDisk =
                        segmentLength * slabFraction * verticalWeight;
                } else {
                    float verticalIntegral = abs(
                        diskVerticalPrimitive(zLeave, halfHeight) -
                        diskVerticalPrimitive(zEnter, halfHeight));
                    pathInDisk =
                        segmentLength / abs(ds) * verticalIntegral;
                }
            }

            if (pathInDisk > 0.0) {
                float band = smoothstep(rin, rin * 1.18, rc) *
                             (1.0 - smoothstep(rout * 0.78, rout, rc));
                float phi = atan(diskPos.y, diskPos.x);
                float turns = phi / 6.2831853;

                float rM = max(2.0 * rc, 1.01);
                float omega = 1.0 /
                              max(pow(rM, 1.5) + sdir * spin, 0.05);
                float omegaInner = 1.0 /
                                   max(pow(max(2.0 * rin, 1.01), 1.5) +
                                       sdir * spin, 0.05);
                float orbitRate = omega / max(omegaInner, 1e-5);
                float phase = -t * patternSpeed * orbitRate * dil * sdir;
                // Domain-warp the turbulence sampling coordinates by a coarser,
                // independent noise field before the main octaves: bends the
                // layered stripes into swirling, marbled structure instead of
                // clean concentric bands. The warp field itself drifts slowly
                // over time (it rides on `phase`), so the marbling isn't static.
                float warpField = vnoiseWrapY(vec2(rc * 0.18, turns * 3.0 + phase * 0.3), 3.0) - 0.5;
                float warpedRadius = rc + warpField * L.warp * rc * 0.12;
                float warpedTurns = turns + warpField * L.warp * 0.35;
                float noiseValue = diskNoise(warpedRadius, warpedTurns, phase, L.wind);
                float turbulent = mix(1.0, mix(0.38, 1.62, noiseValue), clamp(L.turb, 0.0, 1.0));
                // Ridged shaping turns the noise field's mid-value contour into a
                // thin bright line rather than a blobby above-threshold patch —
                // the same trick used for ridged-multifractal terrain — so
                // filaments read as crisp streaks; L.filSharp narrows them further.
                float ridge = pow(clamp(1.0 - abs(2.0 * noiseValue - 1.0), 0.0, 1.0), max(L.filSharp, 0.1));
                float hotFilaments = 1.0 + L.contr * ridge;
                // A low-frequency spiral density wave (a few dominant arms)
                // layered on top of the fine turbulence, so the disk reads as
                // structured (galaxy-like) rather than uniformly noisy. The arm
                // pattern rotates at its own, slower rate than the fine
                // turbulence (the 0.6x phase scale), mimicking how real spiral
                // density waves outrun or lag the local orbital speed.
                float armPhase = turns * L.armCount * 6.2831853 + rc * L.armTwist - phase * 0.6;
                float armRidge = pow(0.5 + 0.5 * cos(armPhase), max(L.armSharp, 0.1));
                float arms = mix(1.0, armRidge, clamp(L.armStr, 0.0, 1.0));
                float density = band * turbulent * hotFilaments * arms;

                // Exact circular-equatorial Kerr emitter redshift for the ray's
                // conserved axial impact parameter. This single factor includes
                // gravitational redshift, transverse Doppler, line-of-sight
                // beaming and frame dragging without multiplying incompatible
                // Schwarzschild lapse and flat-space velocity approximations.
                float kerrShift = kerrCircularRedshift(
                    rc, spin, sdir, photonLambda);
                float gShift = mix(1.0, clamp(kerrShift, 0.06, 3.0), L.dopp);

                float edge = max(1.0 - sqrt(rin / rc), 0.0);
                float tprof = pow(rin / rc, 0.75) * pow(edge, 0.25) / 0.488;
                // MRI turbulence perturbs temperature more gently than density;
                // the fourth-power flux then turns its hottest ridges into fine,
                // physically plausible highlights.
                float tempPerturb = mix(0.92, 1.08, noiseValue);
                float localTempRatio = max(tprof * tempPerturb, 0.02);
                float observedTemp = L.temp * localTempRatio * max(gShift, 0.01);
                vec3 spectral = blackbodyLinear(observedTemp);
                float thermalPower = pow(clamp(localTempRatio, 0.0, 1.5), 4.0);
                float boost = pow(max(gShift, 0.05), L.beam);

                float tau = L.opac * density * pathInDisk /
                            max(1.35 * halfHeight, 0.02);
                float alpha = clamp(1.0 - exp(-tau), 0.0, 0.98);
                emitc += trans * spectral * (L.gain * thermalPower * boost * alpha);
                trans *= 1.0 - alpha;
            }
        }

#if CINEMATIC
        // A hot, optically thin corona hugging the inner disk. Unlike the old
        // screen-space halo this emission is accumulated on the bent ray, so
        // it is captured, redshifted and multiply imaged by the same geometry
        // as the disk. The smooth component gives HDR tonemapping something
        // to roll into a glow without painting light over the shadow.
        if (CINE_GLOW_GAIN > 0.0 && trans > 0.01) {
            float coronaHeight = dot(x, n);
            float coronaBL = kerrBoyerLindquistRadius(
                rNow, coronaHeight, spin);
            float horizonBL = 1.0 +
                              sqrt(max(1.0 - spin * spin, 0.0));
            if (coronaBL > horizonBL * 1.0001) {
                float coronaCyl2 =
                    max(rNow2 - coronaHeight * coronaHeight, 0.0);
                float coronaOuter = 1.25 * rout;
                if (coronaCyl2 < coronaOuter * coronaOuter) {
                    float coronaCyl = sqrt(coronaCyl2);
                    float coronaScale = max(2.2, 0.45 * rout);
                    float coronaOpening =
                        0.20 + 3.0 * CINE_GLOW_RADIUS;
                    float coronaH =
                        coronaOpening * (0.35 + coronaCyl);
                    float coronaRadial =
                        exp(-coronaCyl / coronaScale) *
                        (1.0 - smoothstep(0.75 * rout,
                                          coronaOuter, coronaCyl));
                    float coronaVertical =
                        exp(-abs(coronaHeight) / max(coronaH, 0.08));
                    float coronaInner =
                        smoothstep(horizonBL * 1.01,
                                   horizonBL * 1.35, coronaBL);
                    float coronaDensity =
                        coronaInner * coronaRadial * coronaVertical /
                        (1.0 + 0.10 * rNow2);
                    if (coronaDensity > 1e-4) {
                        // Off-plane Kerr emitter shift: ZAMO-like near the
                        // horizon/high above the disk, increasingly
                        // co-rotating inside the dense disk-hugging layer.
                        float diskCoupling = coronaVertical *
                            smoothstep(0.75 * rin, 1.35 * rin,
                                       coronaCyl);
                        float rawCoronaShift = kerrCoronaRedshift(
                            coronaBL, coronaHeight, coronaCyl,
                            spin, sdir, photonLambda, diskCoupling);
                        if (rawCoronaShift > 0.0) {
                            float coronaShift = mix(
                                1.0, clamp(rawCoronaShift, 0.0, 2.5),
                                L.dopp);
                            vec3 coronaColor =
                                blackbodyLinear(16000.0 * coronaShift);
                            if (segmentLength < 0.0)
                                segmentLength = length(segment);
                            float coronaPath = min(segmentLength, 1.0);
                            emitc +=
                                trans * coronaColor * CINE_GLOW_GAIN *
                                coronaDensity * pow(coronaShift, 4.0) *
                                coronaPath * 0.18;
                        }
                    }
                }
            }
        }

        // Optional optically thin polar outflow. It is off in the realistic
        // default (not every accreting hole has a visible jet); when enabled,
        // use a true conical cross-section and the backward-ray Doppler sign.
        if (CINE_JET_GAIN > 0.0 &&
            rNow > horizon * 1.1 && rNow < rout * 5.0) {
            float jetAxialSigned = dot(x, n);
            float jetAxial = abs(jetAxialSigned);
            float jetSide = jetAxialSigned < 0.0 ? -1.0 : 1.0;
            float jetRadius = 0.08 + tan(CINE_JET_ANGLE) * jetAxial;
            float jetCyl2 = max(rNow2 - jetAxialSigned * jetAxialSigned,
                                0.0);
            float jetSupport = 3.04 * max(jetRadius, 0.02);
            if (jetCyl2 < jetSupport * jetSupport) {
                float jetCyl = sqrt(jetCyl2);
                float cone = exp(-pow(jetCyl /
                                      max(jetRadius, 0.02), 2.0));
                float jetWindow =
                    smoothstep(horizon * 1.1, horizon * 1.8, rNow) *
                    (1.0 - smoothstep(rout * 2.4, rout * 5.0, rNow));
                float jetNoise = 0.55 + 0.45 * vnoiseWrapY(
                    vec2(rNow * 0.42, jetAxial * 0.8 + t * 0.7), 13.0);
                vec3 jetVelocity = n * jetSide * CINE_JET_BETA;
                float jetDoppler =
                    sqrt(max(1.0 - CINE_JET_BETA * CINE_JET_BETA, 0.01)) /
                    max(1.0 + dot(jetVelocity, normalize(v)), 0.06);
                if (segmentLength < 0.0)
                    segmentLength = length(segment);
                emitc += trans * blackbodyLinear(20000.0) *
                         CINE_JET_GAIN * cone *
                         jetWindow * jetNoise *
                         pow(max(jetDoppler, 0.05), 3.0) *
                         min(segmentLength, 1.0);
            }
        }
#endif

        sPrev = s;
        xPrev = x;
    }

    vec3 bg = vec3(0.0);
    // A ray which exhausts the budget near the photon shell is unresolved,
    // not captured. It keeps accumulated higher-order disk light but never
    // leaks terminal text through an unproven escape path.
    if (escaped && !captured && includeBackground) {
        vec3 d = normalize(v);
        if (d.z < -0.05) {
            float tpl = (-LENS_DEPTH - x.z) / d.z;
            vec3 hp = x + d * tpl;
            vec2 q = rot(hp.xy, -L.roll) / W;
            vec2 sp = vec2(q.x, -q.y);
            vec2 skyUV = center +
                         (p + (sp - p) * window * shield) /
                         vec2(iResolution.x / iResolution.y, 1.0);
            vec2 suv = mirrorUV(skyUV);
            float toward = smoothstep(0.05, 0.35, -d.z);
            float starWeight = L.star * window * shield * toward;
            if (starWeight > 1e-5)
                bg += starsPlane(skyUV) * starWeight;
            bg += texture(iChannel0, textureUV(suv)).rgb * toward;
        }
    }

    diskLinearOutput = emitc * L.expo * window * shield;
    return bg * trans;
}

// ------------------------------------------------------------------- image --
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2  res    = iResolution.xy;
    vec2  uv     = screenUV(fragCoord / res);
    float aspect = res.x / res.y;

    // Canonical screen space is top-down on both Ghostty backends.
    float yUp = 1.0 - uv.y;

    // smooth animation runs off iTime (advances every frame); per-mode envelopes
    // (wall clock / token fill) only set how big, how fast and how far it moves
    float t = iTime * DRIFT_SPEED;

    // disk look: the tunables verbatim, or the demo tour's current blend
    DiskLook L = LOOK_DEFAULT;
    if (SIZE_MODE == MODE_DEMO) L = demoLook();

    // Spin sets the horizon and the rotation-appropriate innermost stable
    // circular orbit. User tuning may move the disk outward, never inward.
    float spin = clamp(BH_SPIN, 0.0, 0.998);
    float orbitDirection = L.speed < 0.0 ? -1.0 : 1.0;
    float horizon = kerrHorizon(spin);
    float rin  = max(L.inner, kerrISCO(spin, orbitDirection));
    float rout = max(L.outer, rin + 0.5);

    // ---- per-mode state: master intensity I, size sz, and drift center ----
    // I drives lensing/disk/dilation; sz scales the shadow; center is the
    // hole's screen position. SIZE_MODE picks how the three are computed; both
    // branches compile and the dead one folds away at compile time.
    float I, sz;
    vec2  center;
    float contextFill = 0.0; // Claude Code context fill 0..1; MODE_TOKENS sets it, other modes leave it at 0 (no hunger coupling)
    if (SIZE_MODE == MODE_POMODORO) {
        // wall-clock cycle: grow through the work phase, collapse fast in the
        // last minute, stay gone through the break phase
        float workSec  = WORK_PERIOD_MIN * 60.0;
        float cycleSec = workSec + BREAK_MIN * 60.0;
        // Ghostty 1.3 declares iDate but leaves it at zero. Prefer real wall
        // time when a future renderer supplies it, and otherwise run a useful
        // session-relative clock. TIME_SCALE accelerates either source.
        float clockNow = iDate.w > 0.0 ? iDate.w : iTime;
        float wall = clockNow + iTime * (TIME_SCALE - 1.0);
        float phase    = mod(wall, cycleSec);
        float collapse = min(60.0, workSec * 0.15);  // scales down for short debug cycles
        float grow = clamp(phase / workSec, 0.0, 1.0)
                   * (1.0 - smoothstep(workSec - collapse, workSec, phase));
        // always-present floor: never gone while you work — small and slow at
        // cycle start, back to small when the break window arrives
        I = mix(0.12, 1.0, grow);
        // typing detector: cursor quiet -> you're pausing; the hole shrinks live
        // and is gone by the time the pause becomes a real break
        float idle = max(0.0, iTime - iTimeCursorChange);
        I *= 1.0 - smoothstep(IDLE_FADE_SEC, max(BREAK_MIN * 60.0, IDLE_FADE_SEC + 1.0), idle);
        sz = mix(0.22, 1.0, I);              // starts small, grows toward break time
        // lazy Lissajous drift, vertically confined so the hole and its disk
        // stay above the work area at the bottom; bounds adapt to size (the
        // disk's projected half-extent is rout/B_CRIT shadow radii), drift
        // follows size: a small calm hole hovers, a big one roams wide
        // (amplitude, not frequency — FM would jerk the phase as I evolves)
        float ext = (rout / B_CRIT) * HOLE_RADIUS * sz;
        float yLo = WORK_AREA + 0.12 + ext;  // clears shield band + wobble
        float yHi = max(yLo, 0.90 - ext);    // clears the screen top
        float spd = mix(0.35, 1.0, I);
        center = vec2(
            0.5 + (0.24 * sin(t * 0.21) + 0.05 * sin(t * 0.083)) * spd,
            1.0 - mix(yLo, yHi, 0.5 + (0.42 * sin(t * 0.157 + 2.0) + 0.08 * sin(t * 0.117)) * spd));
        center += I * vec2(0.040 * sin(t * 0.83) + 0.020 * sin(t * 1.31),
                           0.030 * sin(t * 1.03 + 1.0));
    } else if (SIZE_MODE == MODE_DEMO) {
        // ---- demo mode: self-running showcase loop, always visible ----
        // (the cursor channel is ignored here — see MODE_DEMO in the README)
        float lvl = min(mod(iTime, max(DEMO_SEC, 1e-4)) /
                        max(DEMO_GROW_SEC, 1e-4), 1.0);
        // TOKEN_EASE shapes the growth curve; TOKEN_VISUAL_FLOOR makes a
        // fresh Claude session visibly present instead of a tiny corner seed.
        float visualLvl = mix(TOKEN_VISUAL_FLOOR, 1.0, clamp(lvl, 0.0, 1.0));
        float g = pow(clamp(visualLvl, 0.0, 1.0), TOKEN_EASE);
        I = mix(0.10, 1.0, g);               // disk dilation / glow follow fill
        // Size is anchored to the *terminal area*: the shadow disk covers
        // TOKEN_AREA_MIN of the screen at 0% context and TOKEN_AREA_MAX at
        // 100%, whatever the window shape (area = pi*rh²/aspect, rh in units
        // of screen height). The radius interpolates linearly between the two
        // endpoints — interpolating the area instead would front-load the
        // felt size badly, since rh goes as sqrt(area).
        float rhMin = sqrt(TOKEN_AREA_MIN * aspect / 3.1415927);
        float rhMax = sqrt(TOKEN_AREA_MAX * aspect / 3.1415927);
        // HOLE_RADIUS doubles as a plain size dial here: at its 0.08 default
        // the AREA_MIN/MAX calibration is exact, and dragging it scales every
        // token-mode size proportionally around that.
        float rhT = mix(rhMin, rhMax, g) * (HOLE_RADIUS / 0.08);
        sz = rhT / max(HOLE_RADIUS, 1e-4);
        // ---- movement: a roam box growing out of the home corner ----
        // The allowed area starts collapsed onto the top-right corner and
        // expands left and down as the context fills, up to TOKEN_REACH of
        // the playable screen (everything above the work area); the hole
        // wanders pseudo-randomly through all of it (Lissajous — never
        // visibly repeats), faster as the fill grows. Margins keep the
        // shadow and bright inner disk on-screen while the hole is small,
        // then give up gracefully once it outgrows the band — a half-screen
        // hole has nowhere clean to be.
        float marg = min(rhT * mix(1.45, 0.90, g), 0.5 * (1.0 - WORK_AREA - 0.03));
        float xPad = marg / aspect;
        vec2  fullLo = vec2(min(xPad, 0.5), marg);
        vec2  fullHi = vec2(max(0.5, 1.0 - xPad),
                            max(marg, 1.0 - (WORK_AREA + 0.03 + marg)));
        vec2  corner = clamp(vec2(TOKEN_HOME_X, TOKEN_HOME_Y), fullLo, fullHi);
        float reach  = mix(0.06, max(TOKEN_REACH, 0.06), g); // a sliver of room even at 0%
        vec2  lo = vec2(mix(corner.x, fullLo.x, reach), fullLo.y);
        vec2  hi = vec2(fullHi.x, mix(corner.y, fullHi.y, reach));
        // Confinement must never *clip* the position: clipping saturates and
        // parks the hole dead against the wall for seconds — it reads as a
        // freeze. The wander is scaled to the available room instead, and a
        // small fast circular wobble rides on top so the hole stays visibly
        // alive even when one axis runs out of room entirely. Speed comes
        // from blending a calm and a rushed fixed-frequency orbit — NOT from
        // scaling t: iTime persists across reloads, so a g-dependent
        // t-multiplier would jump the phase on every token update (a visible
        // teleport once iTime is large).
        vec2  room   = max((hi - lo) * 0.5, vec2(0.0));
        vec2  wobAmp = min(vec2(0.010 + 0.030 * g), max(room * 0.35, vec2(0.006)));
        vec2  ampEff = max(room - wobAmp, vec2(0.0));
        vec2  wander = mix(lissa(t * TOKEN_CALM), lissa(t * TOKEN_RUSH), g);
        center = (lo + hi) * 0.5 + wander * ampEff
               + wobAmp * vec2(cos(t * 0.8), sin(t * 1.0));
    } else {
        // ---- token mode: Claude Code context-window fill ----
        // Deliberately silent while focused or idle — no ambient corner
        // hole any more (the vis<=0 early-return below shows a plain
        // terminal whenever I stays 0). contextFill is the sole trace of the
        // live fill that survives: it secretly drives how hungry the
        // unfocused feeding gets, further down.
        float live = tokenLevel();
        float lvl = live >= 0.0 ? live : TOKEN_LEVEL;
        contextFill = clamp(lvl, 0.0, 1.0);
        I = 0.0;
        sz = 0.0;
        center = vec2(0.5, 0.5);
    }

    // Ghostty exposes when focus was last gained, not when it was lost. The
    // stateless shader therefore accumulates hunger during the focus session
    // and reveals it when focus leaves: a quick glance away shows a small,
    // still-feeding hole; looking away after a long session reveals a mature
    // one immediately. `custom-shader-animation = always` keeps it moving.
    // Context fill shortens the hunger window and raises the eventual cap.
    float hungerAge = max(0.0, iTime - iTimeFocus);
    float eat = (iFocus > 0)
              ? 0.0
              : smoothstep(0.0, UNFOCUSED_EAT_SEC, hungerAge);
    float hungryGrowSec = mix(UNFOCUSED_GROW_SEC, UNFOCUSED_HUNGRY_GROW_SEC, contextFill);
    float growLinear = (iFocus > 0)
                     ? 0.0
                     : smoothstep(0.0, hungryGrowSec, hungerAge);
    // Front-loaded easing keeps short focus sessions lightly hungry, then
    // accelerates toward the mature reveal during a sustained session.
    float feed = pow(growLinear, UNFOCUSED_GROW_EASE);
    if (eat > 0.0) {
        float hungryEndRadius = mix(UNFOCUSED_END_RADIUS, UNFOCUSED_HUNGRY_END_RADIUS, contextFill);
        float fedRadius = mix(UNFOCUSED_START_RADIUS, hungryEndRadius, feed);
        float unfocusedSz = fedRadius / max(HOLE_RADIUS, 1e-4);
        // A real Lissajous roam (the same wander used elsewhere) instead of
        // a near-fixed point with a faint wobble, so it visibly drifts
        // rather than sitting still.
        vec2 chewCenter = vec2(UNFOCUSED_CENTER_X, UNFOCUSED_CENTER_Y)
                        + lissa(t * UNFOCUSED_ROAM_SPEED) * UNFOCUSED_ROAM_RADIUS;
        I = mix(I, max(I, mix(0.55, UNFOCUSED_LEVEL, feed)), eat);
        sz = mix(sz, max(sz, unfocusedSz), eat);
        center = mix(center, chewCenter, eat);
    }

    float vis = smoothstep(0.0, 0.10, I);  // hole vanishes entirely when rested
    if (vis <= 0.0) {
        fragColor = texture(iChannel0, textureUV(uv));
        return;
    }
    float rh = HOLE_RADIUS * sz;           // shadow radius in screen units

    // ---- gravitational time dilation (theme feature) ----
    // A heavier hole slows the clock locally: the accretion disk visibly winds
    // down as the hole grows. dil multiplies the disk's pattern rate, falling
    // from 1 toward DILATION_MIN as the hole reaches full mass.
    float dil = mix(1.0, DILATION_MIN, I);

    // shield: warp/disk/stars all fade to nothing over the work area — the
    // displacement (not the color) is faded, so there is no visible seam
    float focusShield = vis * smoothstep(WORK_AREA, WORK_AREA + 0.18, yUp);
    float shield = mix(focusShield, vis, eat);
    if (shield <= 0.0) {
        fragColor = texture(iChannel0, textureUV(uv));
        return;
    }

    // aspect-corrected frame centered on the hole (y in units of screen height)
    vec2  p    = (uv - center) * vec2(aspect, 1.0);
    float plen = length(p);

    // screen <-> world mapping: the shadow's true angular size is B_CRIT r_s,
    // and we want it rh screen units wide, so 1 screen unit = W Schwarzschild
    // radii. pr is the pixel in world units, y-up, with the system roll applied.
    float W  = B_CRIT / max(rh, 1e-4);
    vec2  pr = rot(vec2(p.x, -p.y), L.roll) * W;
    float b  = length(pr);              // the ray's impact parameter, in r_s

    // distance-window: real lensing falls off as 1/b and would shimmer text
    // across the whole screen as the hole drifts; fade it out a few disk
    // diameters away (deliberately unphysical, like the work-area shield)
    float window = exp(-pow(plen / (7.0 * rh), 2.0));

    float bmax = rout + 3.0;            // rays beyond this can't touch the disk
    float Z0   = max(14.0, rout + 5.0); // camera distance (shared with the tracer)

    // ================= far field: analytic weak deflection ==================
    // The geodesic region's rays start at the finite camera z = Z0 and get
    // projected back onto the sky plane, so they bend *less* than the
    // textbook alpha = 2 r_s/b from infinity — using that raw leaves a ~20%
    // displacement jump at the handoff radius, a visible circular seam.
    // This is the same finite-camera mapping, fitted against the integrator
    // (sub-1% at the boundary): disp = (2/b)(1.29u + 0.07)(L - 2.14u + 0.75)
    // in world units, with u = Z0/sqrt(Z0^2 + b^2).
    if (b >= bmax) {
        float u    = Z0 * inversesqrt(Z0 * Z0 + b * b);
        float defl = (2.0 / (W * W)) / max(plen, 1e-4)
                   * (1.29 * u + 0.07) * max(LENS_DEPTH - 2.14 * u + 0.75, 0.0)
                   * window * shield;
        vec2  dir  = p / max(plen, 1e-5);
        // The leading spin correction is tangential to the radial
        // Schwarzschild deflection and fades as 1/b. Gravitational lensing is
        // achromatic, so all terminal color channels share this sample.
        vec2 equator = vec2(cos(L.roll), sin(L.roll));
        float spinDefl = defl * spin * sin(L.incl) * 0.45 / max(b, 1.0);
        vec2 sp = p - dir * defl - equator * spinDefl;
        vec2 skyUV = center + sp / vec2(aspect, 1.0);
        vec2 suv = mirrorUV(skyUV);
        vec3 term = texture(iChannel0, textureUV(suv)).rgb;
        // same starfield as the geodesic region, lit through the weak-field
        // bend so stars don't pop at the boundary circle
        float starWeight = L.star * window * shield;
        if (starWeight > 1e-5)
            term += starsPlane(skyUV) * starWeight;
        fragColor = vec4(term, 1.0);
        return;
    }

    // ====================== near field: trace the geodesic ==================
    vec3 bgSample;
    vec3 diskLinear = vec3(0.0);
    vec3 diskTmp;
    float pixelWorld = W / res.y;
    float edgeDistancePixels;
    float escapeCoverage = kerrEscapeMask(pr, pixelWorld,
                                          L.incl, spin,
                                          edgeDistancePixels);
    bool shadowEdge = escapeCoverage > 0.01 && escapeCoverage < 0.99;
    // Tiny holes undersample higher-order disk images and high-frequency
    // turbulence. Widen only their Kerr-shaped sampling band to four pixels;
    // large holes retain the near-zero-cost exact-edge path.
    shadowEdge = shadowEdge ||
                 (pixelWorld > 0.04 && edgeDistancePixels < 4.0);
#if QUALITY_LEVEL == QUALITY_MAXIMUM
    if (shadowEdge) {
        float px = 1.0 / res.y;
        vec2 ps = p + vec2(-0.25, -0.25) * px;
        float subEscape = step(
            0.0, kerrEscapeSigned(
                rot(vec2(ps.x, -ps.y), L.roll) * W,
                L.incl, spin));
        bgSample = traceNearField(ps, center, W, rh, window, shield,
                                  t, dil, L, rin, rout, spin, horizon,
                                  true, diskLinear) * subEscape;

        ps = p + vec2(0.25, -0.25) * px;
        subEscape = step(
            0.0, kerrEscapeSigned(
                rot(vec2(ps.x, -ps.y), L.roll) * W,
                L.incl, spin));
        bgSample += traceNearField(ps, center, W, rh, window, shield,
                                   t, dil, L, rin, rout, spin, horizon,
                                   true, diskTmp) * subEscape;
        diskLinear += diskTmp;

        ps = p + vec2(-0.25, 0.25) * px;
        subEscape = step(
            0.0, kerrEscapeSigned(
                rot(vec2(ps.x, -ps.y), L.roll) * W,
                L.incl, spin));
        bgSample += traceNearField(ps, center, W, rh, window, shield,
                                   t, dil, L, rin, rout, spin, horizon,
                                   true, diskTmp) * subEscape;
        diskLinear += diskTmp;

        ps = p + vec2(0.25, 0.25) * px;
        subEscape = step(
            0.0, kerrEscapeSigned(
                rot(vec2(ps.x, -ps.y), L.roll) * W,
                L.incl, spin));
        bgSample += traceNearField(ps, center, W, rh, window, shield,
                                   t, dil, L, rin, rout, spin, horizon,
                                   true, diskTmp) * subEscape;
        diskLinear += diskTmp;
        bgSample *= 0.25;
        diskLinear *= 0.25;
    } else {
        bgSample = traceNearField(p, center, W, rh, window, shield,
                                  t, dil, L, rin, rout, spin, horizon,
                                  true, diskLinear) * escapeCoverage;
    }
#elif QUALITY_LEVEL == QUALITY_BALANCED
    if (shadowEdge) {
        float px = 1.0 / res.y;
        vec2 ps = p - vec2(0.25) * px;
        float subEscape = step(
            0.0, kerrEscapeSigned(
                rot(vec2(ps.x, -ps.y), L.roll) * W,
                L.incl, spin));
        bgSample = traceNearField(ps, center, W, rh, window, shield,
                                  t, dil, L, rin, rout, spin, horizon,
                                  true, diskLinear) * subEscape;
        ps = p + vec2(0.25) * px;
        subEscape = step(
            0.0, kerrEscapeSigned(
                rot(vec2(ps.x, -ps.y), L.roll) * W,
                L.incl, spin));
        bgSample += traceNearField(ps, center, W, rh, window, shield,
                                   t, dil, L, rin, rout, spin, horizon,
                                   true, diskTmp) * subEscape;
        bgSample *= 0.5;
        diskLinear = 0.5 * (diskLinear + diskTmp);
    } else {
        bgSample = traceNearField(p, center, W, rh, window, shield,
                                  t, dil, L, rin, rout, spin, horizon,
                                  true, diskLinear) * escapeCoverage;
    }
#else
    bgSample = traceNearField(p, center, W, rh, window, shield, t, dil,
                              L, rin, rout, spin, horizon,
                              true, diskLinear) * escapeCoverage;
#endif

#if CINEMATIC
    // Optional artistic CA remains disk-only and confined to the actual Kerr
    // edge. Lensing itself is achromatic, so the realistic default is zero.
    if (CINE_RING_CA > 0.0 && shadowEdge) {
        vec2 caOffset = normalize(p + vec2(1e-6)) * CINE_RING_CA / res.y;
        vec3 caLeft, caRight;
        traceNearField(p - caOffset, center, W, rh, window, shield, t, dil,
                       L, rin, rout, spin, horizon, false, caLeft);
        traceNearField(p + caOffset, center, W, rh, window, shield, t, dil,
                       L, rin, rout, spin, horizon, false, caRight);
        diskLinear = vec3(caLeft.r, diskLinear.g, caRight.b);
    }
#endif

    // Average HDR radiance first, then apply the nonlinear display transform
    // once. Exact Kerr coverage was applied only to terminal/sky light; disk
    // radiation in front of the horizon and its higher-order images remain.
    vec3 diskSample = finishDiskRadiance(diskLinear, p, rh);
    if (shield < 0.99999) {
        vec3 pristine = texture(iChannel0, textureUV(uv)).rgb;
        bgSample = mix(pristine, bgSample, clamp(shield, 0.0, 1.0));
    }
    vec3 col = bgSample + diskSample;

    // Glyphs spiral inward and stretch toward the hole before they cross the
    // horizon, rather than simply fading in place: sample the terminal at a
    // swirled, center-dragged position instead of straight at this pixel,
    // then fade that pulled sample to black approaching the horizon. Both
    // the drag and the twist grow with `feed`, so a longer-feeding hole
    // pulls text in more violently.
    float pullInner = min(UNFOCUSED_PULL_INNER, UNFOCUSED_PULL_OUTER) * rh;
    float pullOuter = max(max(UNFOCUSED_PULL_INNER, UNFOCUSED_PULL_OUTER) * rh,
                          pullInner + 1e-5);
    float eatT = eat * (1.0 - smoothstep(pullInner, pullOuter, plen));
    if (eatT > 0.0) {
        float pull  = eatT * mix(UNFOCUSED_PULL_MIN, UNFOCUSED_PULL_MAX, feed);
        float swirl = eatT * mix(UNFOCUSED_SWIRL_MIN, UNFOCUSED_SWIRL_MAX, feed);
        vec2  dragged = mix(rot(p, swirl), vec2(0.0), clamp(pull, 0.0, 1.0));
        vec2  suv = mirrorUV(center + dragged / vec2(aspect, 1.0));
        vec3  pulled = texture(iChannel0, textureUV(suv)).rgb;
        float ink = smoothstep(0.10, 0.70, max(max(pulled.r, pulled.g), pulled.b));
        vec3  swallowed = mix(pulled, vec3(0.0), eatT);
        col = mix(col, swallowed, eatT * mix(0.30, 0.90, ink));
    }
    fragColor = vec4(col, 1.0);
}
