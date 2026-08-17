import Foundation

/// Display metadata for a shader tunable. Anything parsed from the shader that
/// has no spec still shows up, in the "Other" group, with a guessed range.
struct ParamSpec {
    let range: ClosedRange<Double>
    let group: String
    let help: String
    let def: Double

    init(_ range: ClosedRange<Double>, _ group: String, _ def: Double, _ help: String) {
        self.range = range
        self.group = group
        self.def = def
        self.help = help
    }
}

enum Specs {
    static let groupOrder = [
        "Black hole", "Accretion disk", "Color & light", "Motion & screen",
        "Token mode", "Unfocused", "Pomodoro", "Cinematic", "Other",
    ]

    static let all: [String: ParamSpec] = [
        // black hole
        "HOLE_RADIUS":   ParamSpec(0.01...0.25, "Black hole", 0.02, "Size dial. Pomodoro: shadow radius at full size, fraction of screen height. Token mode scales the area calibration proportionally"),
        "LENS_DEPTH":    ParamSpec(0.0...20.0, "Black hole", 13.0, "Distance from the hole to the terminal “sky” plane, in Schwarzschild radii — bigger bends text harder"),
        "STAR_GAIN":     ParamSpec(0.0...2.0, "Black hole", 0.055, "Brightness of the fixed, sky-plane starfield sampled through the gravitational lens (0 = off)"),
        "BH_SPIN":       ParamSpec(0.0...0.998, "Black hole", 0.85, "Kerr spin approximation: changes frame dragging, horizon size, ISCO, and disk orbital speed"),

        // disk geometry + matter
        "DISK_INNER":    ParamSpec(0.6...8.0, "Accretion disk", 1.35, "Inner edge in Schwarzschild radii; the shader clamps it to the rotation-appropriate Kerr ISCO"),
        "DISK_OUTER":    ParamSpec(4.0...20.0, "Accretion disk", 10.0, "Outer edge in Schwarzschild radii"),
        "DISK_INCL":     ParamSpec(0.0...1.5707, "Accretion disk", 1.42, "Inclination in radians: 0 = face-on, π/2 = edge-on (Interstellar look)"),
        "DISK_ROLL":     ParamSpec(-3.1416...3.1416, "Accretion disk", 0.18, "Rotation of the whole system in the screen plane, radians"),
        "DISK_THICKNESS": ParamSpec(0.0...0.35, "Accretion disk", 0.055, "Vertical half-height as a fraction of radius; 0 approaches an infinitely thin disk"),
        "DISK_GAIN":     ParamSpec(0.0...6.0, "Accretion disk", 3.2, "Disk emission brightness"),
        "DISK_OPACITY":  ParamSpec(0.0...4.0, "Accretion disk", 1.2, "Optical depth through the full tapered vertical column"),
        "DISK_SPEED":    ParamSpec(-10.0...10.0, "Accretion disk", 3.6, "Streak pattern speed; negative reverses the orbital direction"),
        "DISK_WIND":     ParamSpec(0.0...15.0, "Accretion disk", 6.0, "Spiral winding tightness of the streaks"),
        "DISK_CONTRAST": ParamSpec(0.0...2.0, "Accretion disk", 1.05, "Brightness contrast of hot turbulent filaments"),
        "DISK_TURBULENCE": ParamSpec(0.0...1.0, "Accretion disk", 0.7, "Mixture of layered turbulent density into the smooth disk"),
        "DISK_FILAMENT_SHARPNESS": ParamSpec(0.5...6.0, "Accretion disk", 2.2, "Ridge exponent for hot filaments: higher = thinner, crisper streak lines"),
        "DISK_WARP_STRENGTH": ParamSpec(0.0...1.5, "Accretion disk", 0.5, "Domain-warps the turbulence field for swirling, marbled structure (0 = off)"),
        "DISK_ARM_COUNT": ParamSpec(0.0...6.0, "Accretion disk", 2.0, "Number of dominant spiral density-wave arms overlaid on the turbulence"),
        "DISK_ARM_TWIST": ParamSpec(-10.0...10.0, "Accretion disk", 3.0, "How tightly the spiral arms wind per unit radius"),
        "DISK_ARM_SHARPNESS": ParamSpec(0.5...8.0, "Accretion disk", 3.0, "Arm crest exponent: higher = narrower, brighter arms"),
        "DISK_ARM_STRENGTH": ParamSpec(0.0...1.0, "Accretion disk", 0.15, "How strongly the arm pattern modulates density (0 = invisible, 1 = dominant)"),

        // color & light
        "DISK_TEMP":     ParamSpec(2000.0...20000.0, "Color & light", 7200.0, "CIE blackbody-locus temperature of the hottest annulus with visible-power weighting, Kelvin"),
        "DOPPLER_MIX":   ParamSpec(0.0...1.0, "Color & light", 1.0, "Kerr orbital redshift and relativistic beaming: 0 = off, 1 = full physical effect"),
        "DISK_BEAM":     ParamSpec(0.0...6.0, "Color & light", 4.0, "Transport exponent: observed bolometric intensity physically scales as g⁴"),
        "EXPOSURE":      ParamSpec(0.05...5.0, "Color & light", 2.4, "Tonemap exposure for the disk light; terminal text is never tonemapped"),

        // cinematic mode
        "CINE_SKY_GAIN":       ParamSpec(0.0...3.0, "Cinematic", 1.0, "Dust-band gain; STAR_GAIN still gates the whole sky"),
        "CINE_GLOW_GAIN":      ParamSpec(0.0...2.0, "Cinematic", 1.1, "Geodesic-traced, optically thin coronal emission gain"),
        "CINE_GLOW_RADIUS":    ParamSpec(0.0...0.20, "Cinematic", 0.05, "Extra coronal opening H/r around the thin disk"),
        "CINE_JET_GAIN":       ParamSpec(0.0...3.0, "Cinematic", 0.0, "Optional polar jet emission gain; off in the realistic default"),
        "CINE_JET_ANGLE":      ParamSpec(0.02...0.60, "Cinematic", 0.18, "Jet cone angle"),
        "CINE_JET_BETA":       ParamSpec(0.0...0.99, "Cinematic", 0.90, "Jet velocity as a fraction of light speed"),
        "CINE_FILM_GRAIN":     ParamSpec(0.0...0.10, "Cinematic", 0.008, "Emission-gated multiplicative film grain"),
        "CINE_VIGNETTE":       ParamSpec(0.0...1.0, "Cinematic", 0.08, "Hole-centered disk vignette"),
        "CINE_RING_CA":        ParamSpec(0.0...1.0, "Cinematic", 0.0, "Optional photon-ring channel separation; off because gravitational lensing is achromatic"),
        "CINE_ACES":           ParamSpec(0.0...1.0, "Cinematic", 1.0, "Use ACES-fitted tonemapping for disk light"),

        // motion & screen
        "DRIFT_SPEED":   ParamSpec(0.0...3.0, "Motion & screen", 1.0, "How fast the hole floats around"),
        "WORK_AREA":     ParamSpec(0.0...0.8, "Motion & screen", 0.33, "Bottom screen fraction kept completely undistorted"),
        "DILATION_MIN":  ParamSpec(0.0...1.0, "Motion & screen", 0.2, "Disk pattern time rate at full size — gravitational time dilation theme"),

        // token mode
        "TOKEN_LEVEL":   ParamSpec(-1.0...1.0, "Token mode", -1.0, "Preview any context fill — emits the OSC 12 cursor-color signal to every Ghostty surface (claude-token.py's channel); negative clears the signal and hides the hole. A live Claude session re-emits its own level, overriding the preview in its surface"),
        "TOKEN_AREA_MIN": ParamSpec(0.001...0.10, "Token mode", 0.03, "Shadow area at 0% context, as a fraction of the terminal area"),
        "TOKEN_AREA_MAX": ParamSpec(0.05...0.90, "Token mode", 0.50, "Shadow area at 100% context, as a fraction of the terminal area"),
        "TOKEN_HOME_X":  ParamSpec(0.0...1.0, "Token mode", 0.96, "Corner-home x in uv (1 = right edge)"),
        "TOKEN_HOME_Y":  ParamSpec(0.0...1.0, "Token mode", 0.04, "Corner-home y in uv (0 = screen top)"),
        "TOKEN_EASE":    ParamSpec(0.1...3.0, "Token mode", 0.45, "Growth curve exponent: 1 = proportional, <1 front-loads growth, >1 back-loads it"),
        "TOKEN_VISUAL_FLOOR": ParamSpec(0.0...0.8, "Token mode", 0.18, "Minimum visual fill applied to a fresh context so the seed hole is visible"),
        "TOKEN_REACH":   ParamSpec(0.0...1.0, "Token mode", 1.0, "How much of the playable screen the roam box covers at 100% context"),
        "TOKEN_CALM":    ParamSpec(0.0...1.0, "Token mode", 0.22, "Drift speed at 0% context"),
        "TOKEN_RUSH":    ParamSpec(0.0...3.0, "Token mode", 2.0, "Drift speed at 100% context"),
        "TOKEN_GLIDE_MIN": ParamSpec(0.01...1.0, "Token mode", 0.08, "Minimum smoothing time for context-level updates"),
        "TOKEN_GLIDE_MAX": ParamSpec(0.05...3.0, "Token mode", 0.55, "Maximum smoothing time for a large context-level jump"),
        "TOKEN_GLIDE_RATE": ParamSpec(0.1...15.0, "Token mode", 3.0, "Smoothing seconds per unit of context-level change"),

        // unfocused feeding
        "UNFOCUSED_EAT_SEC": ParamSpec(0.05...5.0, "Unfocused", 1.8, "Focus-session seconds before the consume effect is fully armed for reveal"),
        "UNFOCUSED_GROW_SEC": ParamSpec(1.0...90.0, "Unfocused", 40.0, "Focus-session hunger window before the revealed hole reaches its maximum radius"),
        "UNFOCUSED_GROW_EASE": ParamSpec(0.5...5.0, "Unfocused", 2.2, "Hunger curve exponent: 1 = plain ease, >1 keeps short focus sessions lightly hungry"),
        "UNFOCUSED_ROAM_RADIUS": ParamSpec(0.0...0.4, "Unfocused", 0.12, "How far the feeding center wanders from its home point, in uv"),
        "UNFOCUSED_ROAM_SPEED": ParamSpec(0.0...1.0, "Unfocused", 0.15, "Lissajous roam speed multiplier (slow — an ambient drift, not a dart)"),
        "UNFOCUSED_LEVEL": ParamSpec(0.0...1.0, "Unfocused", 0.95, "Disk and lens intensity while the terminal is unfocused"),
        "UNFOCUSED_START_RADIUS": ParamSpec(0.01...0.5, "Unfocused", 0.035, "Initial unfocused shadow radius as a fraction of terminal height"),
        "UNFOCUSED_END_RADIUS": ParamSpec(0.02...0.8, "Unfocused", 0.36, "Fully fed shadow radius as a fraction of terminal height"),
        "UNFOCUSED_CENTER_X": ParamSpec(0.0...1.0, "Unfocused", 0.5, "Horizontal feeding center (roam home point)"),
        "UNFOCUSED_CENTER_Y": ParamSpec(0.0...1.0, "Unfocused", 0.43, "Vertical feeding center (roam home point)"),
        "UNFOCUSED_HUNGRY_END_RADIUS": ParamSpec(0.02...0.9, "Unfocused", 0.65, "Fed shadow radius cap at 100% Claude Code context fill (mixed with UNFOCUSED_END_RADIUS by fill)"),
        "UNFOCUSED_HUNGRY_GROW_SEC": ParamSpec(1.0...60.0, "Unfocused", 3.5, "Hunger window at 100% context fill (mixed with UNFOCUSED_GROW_SEC by fill) — faster when fuller"),
        "UNFOCUSED_PULL_INNER": ParamSpec(0.1...2.0, "Unfocused", 0.75, "Eating consume band inner edge, in units of the shadow radius"),
        "UNFOCUSED_PULL_OUTER": ParamSpec(1.0...6.0, "Unfocused", 3.2, "Eating consume band outer edge, in units of the shadow radius"),
        "UNFOCUSED_PULL_MIN": ParamSpec(0.0...1.0, "Unfocused", 0.65, "Inward drag fraction toward the hole at the start of feeding"),
        "UNFOCUSED_PULL_MAX": ParamSpec(0.0...1.0, "Unfocused", 1.0, "Inward drag fraction toward the hole once fully fed"),
        "UNFOCUSED_SWIRL_MIN": ParamSpec(0.0...12.0, "Unfocused", 2.0, "Spiral twist in radians at the start of feeding"),
        "UNFOCUSED_SWIRL_MAX": ParamSpec(0.0...12.0, "Unfocused", 6.5, "Spiral twist in radians once fully fed"),

        // pomodoro
        "WORK_PERIOD_MIN": ParamSpec(1.0...120.0, "Pomodoro", 55.0, "Work minutes per cycle (growth phase)"),
        "BREAK_MIN":       ParamSpec(1.0...30.0, "Pomodoro", 5.0, "Break minutes per cycle (hole gone)"),
        "IDLE_FADE_SEC":   ParamSpec(10.0...600.0, "Pomodoro", 90.0, "Typing pause after which the hole starts fading"),
        "TIME_SCALE":      ParamSpec(1.0...200.0, "Pomodoro", 1.0, "Testing: >1 fast-forwards the wall/session-clock pomodoro cycle via iTime"),
    ]

    static func spec(for name: String, value: Double) -> ParamSpec {
        if let s = all[name] { return s }
        let hi = max(abs(value) * 4.0, 1.0)
        return ParamSpec(value < 0 ? -hi...hi : 0...hi, "Other", value, "")
    }

    /// Presets in the spirit of the Bruneton demo's scene settings.
    static let presets: [(String, [String: Double])] = [
        ("Defaults", all.filter { $0.key != "TOKEN_LEVEL" }.mapValues(\.def)),
        ("Cinematic", [
            "CINE_SKY_GAIN": 1.0, "CINE_GLOW_GAIN": 0.65,
            "CINE_GLOW_RADIUS": 0.07,
            "CINE_JET_GAIN": 0.35, "CINE_JET_ANGLE": 0.18,
            "CINE_JET_BETA": 0.90, "CINE_FILM_GRAIN": 0.012,
            "CINE_VIGNETTE": 0.12, "CINE_RING_CA": 0.0,
            "CINE_ACES": 1.0, "STAR_GAIN": 0.6,
            "DISK_TEMP": 6200, "DISK_THICKNESS": 0.05,
            "DISK_TURBULENCE": 0.08, "DISK_CONTRAST": 0.18,
        ]),
        ("Gargantua", [
            "BH_SPIN": 0.90, "DISK_TEMP": 6500, "DISK_INCL": 1.52,
            "DISK_ROLL": 0.10, "DISK_INNER": 1.3, "DISK_OUTER": 8.0,
            "DISK_THICKNESS": 0.08, "DISK_OPACITY": 0.82,
            "DOPPLER_MIX": 0.55, "DISK_BEAM": 2.2, "DISK_GAIN": 1.4,
            "DISK_CONTRAST": 0.45, "DISK_TURBULENCE": 0.35,
            "STAR_GAIN": 0.0, "EXPOSURE": 1.1,
        ]),
        ("Quasar", [
            "BH_SPIN": 0.95, "DISK_TEMP": 15000, "DISK_INCL": 1.30, "DISK_INNER": 1.5,
            "DISK_OUTER": 14.0, "DISK_OPACITY": 0.35, "DOPPLER_MIX": 1.0,
            "DISK_BEAM": 4.0, "DISK_GAIN": 1.2, "DISK_CONTRAST": 1.3,
            "DISK_WIND": 8.0, "DISK_THICKNESS": 0.16,
            "DISK_TURBULENCE": 0.85, "STAR_GAIN": 0.0, "EXPOSURE": 0.8,
        ]),
        ("Face-on ember", [
            "DISK_TEMP": 7500, "DISK_INCL": 0.30, "DISK_ROLL": 0.0,
            "DISK_INNER": 1.6, "DISK_OUTER": 10.0, "DISK_OPACITY": 0.5,
            "DOPPLER_MIX": 0.85, "DISK_BEAM": 2.8, "DISK_GAIN": 1.0,
            "DISK_CONTRAST": 0.9, "DISK_THICKNESS": 0.10,
            "DISK_TURBULENCE": 0.65, "STAR_GAIN": 0.0, "EXPOSURE": 0.95,
        ]),
        // the EHT image of M87*: warm orange donut, nearly face-on, one
        // beamed bright side, smooth haze instead of filaments
        ("M87* donut", [
            "BH_SPIN": 0.94, "DISK_TEMP": 4200, "DISK_INCL": 0.55, "DISK_ROLL": -0.30,
            "DISK_INNER": 1.5, "DISK_OUTER": 6.0, "DISK_OPACITY": 0.45,
            "DOPPLER_MIX": 0.95, "DISK_BEAM": 3.5, "DISK_GAIN": 1.6,
            "DISK_CONTRAST": 0.4, "DISK_WIND": 3.0, "DISK_SPEED": 2.5,
            "DISK_THICKNESS": 0.22, "DISK_TURBULENCE": 0.55,
            "STAR_GAIN": 0.0, "EXPOSURE": 1.05,
        ]),
        // violently hot and fast: a huge thin jet-fed disk, heavily beamed
        ("Blazar", [
            "DISK_TEMP": 18000, "DISK_INCL": 1.05, "DISK_ROLL": 0.55,
            "BH_SPIN": 0.98, "DISK_INNER": 1.4, "DISK_OUTER": 16.0, "DISK_OPACITY": 0.30,
            "DOPPLER_MIX": 1.0, "DISK_BEAM": 5.0, "DISK_GAIN": 1.0,
            "DISK_CONTRAST": 1.5, "DISK_WIND": 9.0, "DISK_SPEED": 6.0,
            "DISK_THICKNESS": 0.18, "DISK_TURBULENCE": 0.95,
            "STAR_GAIN": 0.0, "EXPOSURE": 0.75,
        ]),
        // dense molten edge-on disk, thick filaments, everything overdriven
        ("Inferno", [
            "DISK_TEMP": 7000, "DISK_INCL": 1.50, "DISK_ROLL": 0.35,
            "DISK_INNER": 1.4, "DISK_OUTER": 8.0, "DISK_OPACITY": 0.90,
            "DOPPLER_MIX": 0.6, "DISK_BEAM": 2.5, "DISK_GAIN": 2.2,
            "DISK_CONTRAST": 1.6, "DISK_WIND": 7.0, "DISK_SPEED": 5.0,
            "DISK_THICKNESS": 0.10, "DISK_TURBULENCE": 0.90,
            "STAR_GAIN": 0.0, "EXPOSURE": 1.2,
        ]),
        // no disk at all: just the spinning shadow, lensed starfield and text
        ("Pure lens", [
            "DISK_GAIN": 0.0, "DISK_OPACITY": 0.0, "STAR_GAIN": 0.6,
            "DOPPLER_MIX": 1.0, "EXPOSURE": 1.0,
        ]),
        // barely-there companion for focused work: dim, slow, no starfield
        ("Zen", [
            "DISK_TEMP": 7000, "DISK_INCL": 1.45, "DISK_ROLL": 0.15,
            "DISK_INNER": 3.5, "DISK_OUTER": 7.0, "DISK_OPACITY": 0.40,
            "DOPPLER_MIX": 0.5, "DISK_BEAM": 2.0, "DISK_GAIN": 0.5,
            "DISK_CONTRAST": 0.3, "DISK_WIND": 3.0, "DISK_SPEED": 1.5,
            "DISK_THICKNESS": 0.06, "DISK_TURBULENCE": 0.25,
            "STAR_GAIN": 0.0, "EXPOSURE": 0.7,
        ]),
    ]

    static func grouped(_ params: [ShaderParam]) -> [(String, [ShaderParam])] {
        groupOrder.compactMap { group in
            let members = params.filter { spec(for: $0.name, value: $0.value).group == group }
            return members.isEmpty ? nil : (group, members)
        }
    }
}
