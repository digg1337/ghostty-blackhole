# Ghostty Blackhole

![Ghostty Blackhole demo](demo.gif)

**Landing page:** [s13k.dev/blackhole](https://s13k.dev/blackhole/)

A black hole floating inside your [Ghostty](https://ghostty.org) terminal. It
starts small and grows to swallow your screen, driven by whichever **size mode**
you pick: a built-in *pomodoro* clock (grow through the hour, demand a break,
leave you alone once you take it), or *token mode*, where it tracks how full
**Claude Code's context window** is in real time.

Modeled on [Eric Bruneton's black hole shader](https://ebruneton.github.io/black_hole_shader/).
A Ghostty custom shader is a single Shadertoy-style fragment pass with no
lookup textures, so every near-field pixel integrates its own light path live.
The exact planar Schwarzschild term is augmented with the leading
gravitomagnetic field of a rapidly spinning mass (`BH_SPIN`), giving a stable
Kerr-inspired approximation with frame dragging, a spin-dependent horizon and
ISCO, and asymmetric lensing. Your terminal contents are the background sky.

## What it renders

- **The shadow** — the exact Kerr radial photon potential decides whether a
  screen ray has an exterior turning point or is captured. This keeps the
  silhouette clean, spin-shifted, and correctly non-circular even though the
  live path integrator uses a faster Kerr-inspired approximation. The
  potential minimum is solved analytically from its stationary points rather
  than sampled, so narrow near-extremal escape wells are not missed.
- **Gravitational lensing** — escaped rays are projected back onto the
  terminal "sky" plane: text bends, magnifies, and shows the mirrored
  secondary image inside the Einstein ring. Far from the hole this hands off
  to achromatic weak-field deflection plus a tangential spin correction, so
  only pixels near the hole pay for integration.
- **Accretion disk** — a finite-height, optically participating disk rather
  than an infinitely thin painted plane. Rays integrate emission and
  absorption along their path through layered, orbitally sheared turbulence;
  the far side arcs *over and under* the shadow and the photon region contains
  higher-order disk images. A Shakura–Sunyaev temperature profile is converted
  along the CIE blackbody locus into linear sRGB, shifted with the circular
  Kerr emitter redshift, weighted by a fitted Planck/CIE visible-power
  fraction, transported with the bolometric `g⁴` law, and then filmically
  tonemapped.
- **Disk structure** — the fine turbulence is domain-warped by a second,
  coarser noise field (`DISK_WARP_STRENGTH`) for swirling, marbled density
  instead of clean concentric bands; hot filaments are ridge-shaped
  (`DISK_FILAMENT_SHARPNESS`) into crisp streak lines rather than blobby
  patches; and a low-frequency spiral density wave (`DISK_ARM_COUNT`,
  `DISK_ARM_TWIST`, `DISK_ARM_SHARPNESS`, `DISK_ARM_STRENGTH`) is layered on
  top so the disk reads as galaxy-like structure, not uniform noise — the
  arm pattern rotates at its own, slower rate than the fine turbulence.
- **Photon ring** — rays winding near the `1.5 r_s` photon sphere pick up
  every disk crossing; the bright thin ring is emergent, not drawn.
- **Lensed starfield** — a fixed procedural sky is sampled at the same
  unmirrored sky-plane hit as the terminal, so stars split into arcs and
  secondary images without swimming as the hole moves.
- **Gravitational time dilation** — the disk pattern at radius `r` advances
  with the circular Kerr angular velocity; the whole pattern also winds down
  as the hole grows heavier (`DILATION_MIN`).
- The hole drifts on a slow Lissajous path, confined to the upper part of
  the screen — the bottom `WORK_AREA` fraction (your prompt) is never
  distorted. Drift speed and reach follow its size: small and calm, big
  and restless.
- **Quality tiers** — maximum quality uses 128 adaptive geodesic steps, four
  turbulence octaves, and 2x2 linear-radiance supersampling on the exact Kerr
  shadow edge. Balanced and lightweight compile-time fallbacks are available
  near the top of the shader.

## Pomodoro mode

The break reminder is computed entirely inside the shader — no daemon, no
shell hooks, nothing outside `blackhole.glsl`.

Shaders are stateless (no buffers persist between frames, and Ghostty has no
custom uniforms), so a shader cannot remember when *your* work streak began.
The schedule uses the wall clock via `iDate` when available and otherwise
falls back to Ghostty's session clock (`iTime`):

- **Cycle**: the hole is always present while you work — it starts small at
  the cycle floor, grows over `WORK_PERIOD_MIN` (default 55 min), collapses
  back to small in the last minute, and stays small through `BREAK_MIN`
  (default 5 min). With 55+5 the peak hits at five-to-the-hour — a fixed,
  predictable rhythm.
- **Typing detector**: `iTimeCursorChange` tracks cursor activity in your
  terminal. Stop using it for `IDLE_FADE_SEC` (default 90 s) and the hole
  shrinks live, gone entirely after a few minutes of quiet — it never nags
  while you aren't actually working.

The trade-off of self-containment: with a real `iDate` it is an hourly bell,
not a per-streak stopwatch. Stock Ghostty through 1.3 declares `iDate` but
leaves it at zero, so the fallback starts a fresh session-relative cycle when
the renderer starts. `TIME_SCALE` accelerates either clock for testing. Token
mode, the default, is unaffected.

## Size modes

What drives the hole is selected by `SIZE_MODE` near the top of `blackhole.glsl`:

- `MODE_POMODORO` — the self-contained wall/session-clock schedule described
  above. Works standalone, with no setup beyond the shader.
- `MODE_TOKENS` *(default)* — the hole tracks **Claude Code's context-window
  fill**. Requires the bundled command (below).
- `MODE_DEMO` — a self-running **42-second showcase loop** for recording demos:
  the hole grows from the corner seed to 100 % exactly as token mode would,
  while the disk look tours the tuner presets (Layered → Gargantua → M87* donut
  → Face-on ember → Quasar → Blazar → Pure lens → Layered), crossfading at each
  ~5 s slot boundary. Everything runs off `iTime` inside one compiled shader —
  no reloads, so a recording never hitches. Toggle it with `./demo-mode.sh
  on|off` (which also reloads Ghostty); the cursor channel is ignored in demo
  mode, so a live Claude session can't disturb a recording. Record any full
  cycle — the loop restart is obvious (the hole snaps back to the corner
  seed).

### Unfocused feeding

Token mode is deliberately silent while the terminal is focused — no ambient
corner hole, just your plain terminal, however full Claude's context window
gets. Look away and that changes: focus protects the lower `WORK_AREA` so the
prompt stays readable, and losing focus opens that shield, moves the hole to
the terminal center, and reveals its hunger while dragging and darkening
nearby glyphs (below). Ghostty exposes the timestamp when focus was last
*gained*, but no blur timestamp; a stateless shader therefore cannot start an
exact timer at focus loss. Hunger accumulates invisibly during the focus
session and is revealed when you look away: a quick glance shows a small,
still-growing hole, while looking away after a long session reveals a mature
one immediately. It requires `custom-shader-animation = always`.

`UNFOCUSED_GROW_EASE` shapes that focus-session hunger curve. The feeding
center then wanders on the same Lissajous roam the rest of the shader uses
(`UNFOCUSED_ROAM_RADIUS`/`UNFOCUSED_ROAM_SPEED`), so the revealed hole visibly
drifts rather than sitting still.

The cap and the growth window both track how full Claude's context window
is, *live* — so a session that keeps growing while you're tabbed away makes
the hole hungrier in real time:

| Context fill | Feed cap (radius) | Hunger window |
|---|---|---|
| 0% / no session | `UNFOCUSED_END_RADIUS` (36%) | `UNFOCUSED_GROW_SEC` (40s) |
| 100% | `UNFOCUSED_HUNGRY_END_RADIUS` (65%) | `UNFOCUSED_HUNGRY_GROW_SEC` (3.5s) |

**Eating the text.** Near the hole, glyphs don't just fade in place — the
terminal is sampled at a position spiraled and dragged toward the hole
center instead of straight ahead, so text visibly stretches and spirals
inward before it's swallowed and fades to black. Both the drag
(`UNFOCUSED_PULL_MIN`/`MAX`) and the twist (`UNFOCUSED_SWIRL_MIN`/`MAX`)
strengthen the longer the hole has been feeding, within a band around the
shadow (`UNFOCUSED_PULL_INNER`/`OUTER`, in shadow radii).

### Token mode

While focused, the hole is completely absent — Claude's context fill only
becomes visible once you unfocus, through the feeding behavior above:

- **Focused** — plain terminal, always, session or not.
- **Unfocused, live session** — the feeding hole appears at center; how big
  it gets and how fast is driven by the context fill, live (see the hunger
  table above).
- **Unfocused, no session** — `TOKEN_LEVEL` still drives the fallback fill
  used for hunger; `-1` means no hunger boost (today's fixed feed).

#### How it works

Ghostty custom shaders take no custom uniforms — but they *do* get the cursor
color (`iCurrentCursorColor`), and any program can set the cursor color with a
standard OSC 12 escape. So the token count rides in on the cursor: a single
bundled script, `claude-token.py`, is wired into Claude Code three ways and
encodes the context fill into the low nibbles of an amber cursor color
(`#f5b000` empty → `#f0bf0a` full); the shader decodes it back out every
frame. The fixed high nibbles plus a 4-bit checksum form a 16-bit signature,
so a theme's own cursor color can't accidentally summon a black hole. No file
is rewritten, nothing reloads, there is no recompile hitch — updates land on
the next frame.

Level steps land smoothly, too: Ghostty bumps `iTimeCursorChange` on any
cursor change *including color* and snapshots the old color into
`iPreviousCursorColor`, so the shader decodes both and glides between the two
levels — discrete updates read as continuous motion instead of popping the
whole warp field. The glide time scales with the jump (`TOKEN_GLIDE_*`):
1 % ticks ease over 0.3 s, a 10 % jump takes 1 s, capped at 1.5 s.

| Wiring | When it fires | What it does |
|--------|---------------|--------------|
| `statusLine`  | every assistant turn | encodes the context fill (`0..1`, 1/250 steps) into the cursor color and prints a built-in-style line: `⚫️ ██████░░░░ 61%  ·  Fable 5  ·  Projects/blackhole  ·  ⎇ main  ·  $1.27  ·  5h 24% · wk 41%` (the last segment is your Claude usage limits; a window past 80 % also shows its reset time) |
| `SessionStart` hook | session start / resume / `/clear` | resets to the corner seed (`0.0`) |
| `SessionEnd` hook | session exit (`/exit`, `ctrl-d`, …) | resets the cursor color (OSC 112) — no signature means no hole |

A cursor color without the signature means "no session", so a bare install
shows nothing until a live session encodes a real fill. (The shader's
`TOKEN_LEVEL` define remains as a manual override for hand-testing a size;
it only applies while the cursor carries no signal.)

#### Install token mode

Two pieces — the shader and the command:

1. Point Ghostty at the shader (see [Install](#install) below) with
   `SIZE_MODE MODE_TOKENS` (the default).
2. Add this to **`~/.claude/settings.json`** (adjust the path), then start a new
   Claude Code session:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "/path/to/blackhole_ghostty/claude-token.py"
     },
     "hooks": {
       "SessionStart": [{ "hooks": [{ "type": "command", "command": "/path/to/blackhole_ghostty/claude-token.py" }] }],
       "SessionEnd":   [{ "hooks": [{ "type": "command", "command": "/path/to/blackhole_ghostty/claude-token.py" }] }]
     }
   }
   ```

This is global, so the hole reacts to *any* Claude Code session. A few notes:

- The cursor color is per-surface state, so every Ghostty split/window gets
  its **own** hole — concurrent sessions in different surfaces don't fight.
- Your cursor turns accretion-disk amber while a session is live (that *is*
  the data channel). Anything else recoloring the cursor gets overwritten at
  the next statusline refresh; a cursor without the signature simply means
  "no hole".
- Inside tmux/screen the OSC would need a passthrough to reach Ghostty —
  token mode is built for plain Ghostty sessions.
- To opt out, set `SIZE_MODE MODE_POMODORO` and remove the entries above.

## Install

Requires Ghostty 1.3+ (for the cursor shader uniforms).

Clone the repo, then add to your Ghostty config (`~/.config/ghostty/config`
or `~/Library/Application Support/com.mitchellh.ghostty/config` on macOS):

```ini
custom-shader = /path/to/blackhole_ghostty/blackhole.glsl
custom-shader-animation = always
```

The checked-in shader targets this machine's Linux/OpenGL backend. On macOS,
change `#define GHOSTTY_Y_DOWN 0` near the top of `blackhole.glsl` to `1`.

Reload the config (`cmd+shift+,` on macOS) or open a new window.

## Tuning

### Tuner app (macOS)

A native SwiftUI control panel in the spirit of
[Bruneton's demo page](https://ebruneton.github.io/black_hole_shader/demo/demo.html)
lives in `tuner/`: grouped sliders for every shader tunable, presets
(*Gargantua*, *Quasar*, *M87\* donut*, *Blazar*, *Inferno*, *Zen*, …),
live two-way sync with the file, and every nudge hot-reloads Ghostty
instantly via `SIGUSR2`.

![The presets — Defaults, Gargantua, Quasar, Face-on ember, M87* donut, Blazar, Inferno, Pure lens, Zen](presets-grid.png)

```sh
cd tuner && swift run            # run it
./tuner/make-app.sh              # or bundle tuner/dist/Black Hole Tuner.app
```

Or just edit the constants at the top of `blackhole.glsl` and reload
(`cmd+shift+,`).

### Constants

At the top of `blackhole.glsl`. Radii are in Schwarzschild radii (`r_s`). The
ISCO depends on `BH_SPIN` and is `3 r_s` only for a non-spinning hole.

| Constant          | Effect                                                  |
|-------------------|---------------------------------------------------------|
| `HOLE_RADIUS`     | Size dial — pomodoro: shadow radius at full size; token mode: proportional scale for the area calibration |
| `LENS_DEPTH`      | Distance from hole to the terminal "sky" plane, in `r_s` — bigger bends text harder |
| `STAR_GAIN`       | Lensed starfield brightness (0 = off)                   |
| `BH_SPIN`         | Kerr spin approximation controlling frame dragging, horizon, ISCO, and orbital speed |
| `DISK_INNER` / `DISK_OUTER` | Disk inner/outer edge in `r_s` (inner clamps to the prograde or retrograde ISCO selected by `DISK_SPEED`) |
| `DISK_INCL`       | Disk inclination, radians: `0` face-on, `π/2` edge-on   |
| `DISK_ROLL`       | Rotation of the whole system in the screen plane        |
| `DISK_THICKNESS`  | Vertical disk half-height divided by radius             |
| `DISK_GAIN`       | Disk emission brightness                                |
| `DISK_OPACITY`    | Optical depth through the full tapered vertical column  |
| `DISK_TEMP`       | CIE blackbody-locus temperature of the hottest annulus, with visible-power weighting, Kelvin |
| `DOPPLER_MIX`     | Circular-Kerr redshift/beaming strength: `0` off, `1` full |
| `DISK_BEAM`       | Transport exponent — bolometric intensity uses physical `g⁴` |
| `DISK_SPEED`      | Streak pattern speed; negative reverses the orbit       |
| `DISK_WIND`       | Spiral winding tightness of the streaks                 |
| `DISK_CONTRAST`   | Streak contrast: `0` = smooth haze, higher = sharp filaments |
| `DISK_TURBULENCE` | Mixture of layered turbulent density into the smooth disk |
| `DISK_FILAMENT_SHARPNESS` | Ridge exponent for hot filaments — higher = thinner, crisper streak lines |
| `DISK_WARP_STRENGTH` | Domain-warps the turbulence field for swirling, marbled structure (0 = off) |
| `DISK_ARM_COUNT` / `DISK_ARM_TWIST` | Number of spiral density-wave arms, and how tightly they wind per unit radius |
| `DISK_ARM_SHARPNESS` / `DISK_ARM_STRENGTH` | Arm crest exponent (narrower = brighter) and how strongly arms modulate density |
| `EXPOSURE`        | Tonemap exposure for disk light (text is never tonemapped) |
| `DRIFT_SPEED`     | How fast the hole floats around                         |
| `WORK_AREA`       | Bottom screen fraction kept completely undistorted      |
| `DILATION_MIN`    | Disk's pattern time rate when the hole is fully grown (lower = more slowdown) |
| `TOKEN_AREA_MIN`  | Token mode: base shadow area at 0% context (default 3% before the visual floor) |
| `TOKEN_AREA_MAX`  | Token mode: shadow area at 100% context (default 50%; render cost scales with it) |
| `TOKEN_HOME_X` / `TOKEN_HOME_Y` | Token mode: corner-home position in uv (`1,0` = exact top-right; y runs top-down) |
| `TOKEN_EASE`      | Token mode: growth curve exponent — `1` = proportional, `<1` front-loads growth, `>1` keeps it small until late |
| `TOKEN_REACH`     | Token mode: how much of the playable screen the roam box covers at 100% context |
| `TOKEN_CALM` / `TOKEN_RUSH` | Token mode: drift speed at 0% / 100% context     |
| `UNFOCUSED_EAT_SEC` | Focus-session seconds before the consume effect is fully armed |
| `UNFOCUSED_GROW_SEC` / `UNFOCUSED_HUNGRY_GROW_SEC` | Hunger window at 0% / 100% context fill (interpolated live by fill) |
| `UNFOCUSED_GROW_EASE` | Feed growth curve exponent — `1` = plain ease, `>1` front-loads slowness |
| `UNFOCUSED_LEVEL`   | Disk/lens intensity while the terminal is unfocused     |
| `UNFOCUSED_START_RADIUS` | Initial unfocused shadow radius, fraction of terminal height |
| `UNFOCUSED_END_RADIUS` / `UNFOCUSED_HUNGRY_END_RADIUS` | Fed shadow radius cap at 0% / 100% context fill (interpolated live by fill) |
| `UNFOCUSED_CENTER_X` / `UNFOCUSED_CENTER_Y` | Feeding center — Lissajous roam home point (y runs top-down) |
| `UNFOCUSED_ROAM_RADIUS` / `UNFOCUSED_ROAM_SPEED` | How far and how fast the feeding center wanders from its home point |
| `UNFOCUSED_PULL_INNER` / `UNFOCUSED_PULL_OUTER` | Eating band inner/outer edge, in shadow radii |
| `UNFOCUSED_PULL_MIN` / `UNFOCUSED_PULL_MAX` | Inward drag fraction toward the hole at the start / end of feeding |
| `UNFOCUSED_SWIRL_MIN` / `UNFOCUSED_SWIRL_MAX` | Spiral twist, radians, at the start / end of feeding |
| `WORK_PERIOD_MIN` | Work minutes per pomodoro cycle (growth phase)          |
| `BREAK_MIN`       | Break minutes per cycle (hole stays small)              |
| `IDLE_FADE_SEC`   | Typing pause after which the hole starts to fade        |
| `TIME_SCALE`      | Testing only: `1` = real schedule; `>1` fast-forwards growth via `iTime` |

### Cinematic mode

Cinematic mode is a compile-time layer selected beside `QUALITY_LEVEL` in
`blackhole.glsl` (enabled by default). It adds geodesic-traced coronal
emission, a structured lensed deep-space sky, optional relativistic polar
jets, and restrained disk-only film effects. It remains one stateless fragment
pass: terminal text, token decoding, and unfocused feeding are unchanged.

| Constant | Effect |
|---|---|
| `CINE_SKY_GAIN` | Dust-band gain; the whole sky remains gated by `STAR_GAIN` |
| `CINE_GLOW_GAIN` / `CINE_GLOW_RADIUS` | Optically thin coronal emission and opening |
| `CINE_JET_GAIN` / `CINE_JET_ANGLE` / `CINE_JET_BETA` | Jet brightness, cone angle, and relativistic speed |
| `CINE_FILM_GRAIN` | Emission-gated multiplicative grain; never lights the shadow |
| `CINE_VIGNETTE` | Hole-centered disk vignette |
| `CINE_RING_CA` | Optional photon-ring-only chromatic separation (off by default because gravity is achromatic) |
| `CINE_ACES` | Selects ACES-fitted disk tonemapping when at least `0.5` |

`QUALITY_LEVEL` selects `QUALITY_MAXIMUM` (128 adaptive steps, four turbulence
octaves and 2x2 exact-shadow-edge supersampling), `QUALITY_BALANCED` (80 steps
and two edge samples), or `QUALITY_LIGHTWEIGHT` (48 steps and one turbulence
octave). HDR disk radiance is averaged before ACES and grain. The ray-traced
area scales with the hole, so lower this tier or
`TOKEN_AREA_MAX` if a large high-DPI terminal becomes sluggish.

To eyeball any token level without a Claude session, drive the cursor-color
channel by hand from a plain shell inside Ghostty: `./token-test.sh 0.42`
holds a level, `./token-test.sh sweep` runs 0 → 100 % over 25 s, and
`./token-test.sh off` hides the hole again. (Don't run it in a surface with a
live session — its statusline re-emits the real level every refresh.) Note
that a size glide only survives while the cursor holds still — any cursor
move makes Ghostty snapshot previous = current, ending the transition early —
which is why the hold mode lingers ~1.6 s before exiting back to the prompt.

For a fast debug loop, set `TIME_SCALE` to e.g. `100` to watch a complete
pomodoro cycle — growth, collapse, break — in about 36 seconds, then set it
back to `1`. It fast-forwards via `iTime`, including when `iTime` is already
the fallback clock. The period knobs also accept fractional minutes.

## Uniforms Ghostty gives custom shaders (1.3)

`iResolution`, `iTime`, `iTimeDelta`, `iFrameRate`, `iFrame`, `iMouse`
(unused), `iDate` (wall clock — declared but stuck at zero through Ghostty
1.3, so pomodoro mode falls back to `iTime`), `iChannel0` (the terminal, `iChannel1-3`
unused), `iCurrentCursor`/`iPreviousCursor` (xy position, zw size),
`iCurrentCursorColor`/`iPreviousCursorColor`, `iCurrentCursorStyle`/
`iPreviousCursorStyle`, `iCursorVisible`, `iTimeCursorChange`, `iFocus`,
`iTimeFocus`, `iPalette[256]`, `iBackgroundColor`, `iForegroundColor`,
`iCursorColor`, `iCursorText`, `iSelectionForegroundColor`,
`iSelectionBackgroundColor`. No persistent buffers between frames — shaders
are stateless, which is why the pomodoro uses renderer-provided clocks.

Three gotchas worth knowing if you hack on this:

- Ghostty's native `fragCoord` y-axis is backend-dependent: **up** on
  Linux/OpenGL and **down** on macOS/Metal. The shader normalizes its internal
  layout to top-down. Keep `GHOSTTY_Y_DOWN 0` on Linux; set it to `1` on macOS.
- To trigger a config reload from a script, send `SIGUSR2` — but find the
  PID with `ps`, not `pgrep`/`pkill`: those silently exclude their own
  ancestors, and Ghostty is an ancestor of any shell running inside it.
- Claude Code spawns statusLine/hook commands with **no controlling
  terminal**, so `/dev/tty` fails there — `claude-token.py` finds the
  session's pty by walking its ancestors with `ps -o ppid=,tty=`.

## License

MIT — see [LICENSE](LICENSE).

Inspired by [Eric Bruneton's black hole shader](https://github.com/ebruneton/black_hole_shader)
(BSD-3-Clause). No code from that project is used here — this shader is an
independent screen-space approximation written from scratch; the credit is
for the idea and the physics it demonstrates.
