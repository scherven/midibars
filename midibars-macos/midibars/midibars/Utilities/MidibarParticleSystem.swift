// Particle physics and visual style adapted from MIDIPlayer by sppmacd
// https://github.com/sppmacd/midiplayer (BSD 2-Clause License)

import CoreGraphics
import Foundation

// MARK: - Particle

struct MidibarParticle {
    enum Kind { case dust, smoke }

    var x, y: CGFloat      // position in rendering coordinate space
    var vx, vy: CGFloat    // velocity px/s; upSign determines which direction is "up"
    var temperature: Float // starts ~80, particle dies when < 1
    var r, g, b: CGFloat   // particle color (slightly brightened note color)
    var kind: Kind

    /// 0 (cold/dead) → 1 (just spawned / fully bright)
    var normalizedAlpha: CGFloat { CGFloat(max(0, min(temperature / 80.0, 1.0))) }
    var isAlive: Bool { temperature > 1.0 }

    // Base radii used by both SpriteKit and CoreGraphics renderers
    static let dustBaseRadius: CGFloat  = 14   // px
    static let smokeBaseRadius: CGFloat = 32   // px
    static let smokeMaxScale: CGFloat   = 3.0  // smoke expands this much as it cools
}

// MARK: - Physics constants (adapted from midiplayer defaults, tuned for pixel space ~1080p)
// midiplayer reference values (per 60 fps frame):
//   dust:  x_drag=1.01, temp_multiplier=4e-7, gravity=4e-5, temp_decay=0.98
//   smoke: x_drag=1.01, temp_multiplier=8e-7, gravity=4e-5, temp_decay=0.99
// These are converted to per-second rates below.

private enum DustPhysics {
    static let xDragPerSec: CGFloat  = 0.55   // fraction of |vx| remaining after 1 s  (0.98^60 ≈ 0.30 → tuned up slightly)
    static let gravity: CGFloat      = 35.0   // px/s² pulling "down"
    static let buoyancy: CGFloat     = 0.022  // px/s per temperature unit pushing "up"
    static let tempDecayPerSec: Float = 0.30  // fraction of temperature left after 1 s (0.98^60)
    static let turbStr: CGFloat      = 20.0   // px/s² turbulence magnitude
}

private enum SmokePhysics {
    static let xDragPerSec: CGFloat  = 0.60
    static let gravity: CGFloat      = 12.0
    static let buoyancy: CGFloat     = 0.042  // smoke rises faster when hot
    static let tempDecayPerSec: Float = 0.55  // smoke cools slower (0.99^60 ≈ 0.55)
    static let turbStr: CGFloat      = 6.0
}

// MARK: - Physics update

/// Advance all particles by `dt` seconds.
///
/// `upSign` controls which axis direction is "up" in the caller's coordinate space:
///   - `+1.0` for SpriteKit (positive y = upward) or for the flipped CG export context
///   - `-1.0` if you are in standard CG (positive y = downward)
///
/// Dead particles are removed in-place.
func updateMidibarParticles(
    _ particles: inout [MidibarParticle],
    dt: CGFloat,
    upSign: CGFloat = 1.0
) {
    for i in particles.indices.reversed() {
        var p = particles[i]

        let xDrag:    CGFloat
        let gravity:  CGFloat
        let buoyancy: CGFloat
        let tempDecay: Float
        let turbStr:  CGFloat

        switch p.kind {
        case .dust:
            xDrag     = DustPhysics.xDragPerSec
            gravity   = DustPhysics.gravity
            buoyancy  = DustPhysics.buoyancy
            tempDecay = DustPhysics.tempDecayPerSec
            turbStr   = DustPhysics.turbStr
        case .smoke:
            xDrag     = SmokePhysics.xDragPerSec
            gravity   = SmokePhysics.gravity
            buoyancy  = SmokePhysics.buoyancy
            tempDecay = SmokePhysics.tempDecayPerSec
            turbStr   = SmokePhysics.turbStr
        }

        // Horizontal exponential drag
        p.vx *= pow(xDrag, dt)

        // Gravity (pulls "down" = opposes upSign)
        p.vy -= gravity * upSign * dt

        // Buoyancy (pushes "up" when hot, proportional to temperature)
        p.vy += CGFloat(p.temperature) * buoyancy * upSign * dt

        // Turbulence: random horizontal + upward-biased vertical (matches midiplayer Perlin + (0,-0.6) bias)
        let turbX = CGFloat.random(in: -1...1) * turbStr * dt
        let turbY = (CGFloat.random(in: -1...1) * 0.4 + 0.6) * turbStr * upSign * dt  // 60% upward bias
        p.vx += turbX
        p.vy += turbY

        // Temperature decay → drives alpha fade and lifetime
        p.temperature *= pow(tempDecay, Float(dt))

        // Integrate position
        p.x += p.vx * dt
        p.y += p.vy * dt

        if p.isAlive {
            particles[i] = p
        } else {
            particles.remove(at: i)
        }
    }
}

// MARK: - Emission

/// Spawn particles for one note event and return them.
///
/// Call site sets `upSign` to match its coordinate space (same as `updateMidibarParticles`).
func emitMidibarParticles(
    at pos: CGPoint,
    noteColor: (r: CGFloat, g: CGFloat, b: CGFloat),
    velocity: CGFloat,      // MIDI velocity normalised 0–1
    config: ParticleConfiguration,
    upSign: CGFloat = 1.0
) -> [MidibarParticle] {
    guard config.enabled else { return [] }

    let velScale      = max(0.3, velocity)
    let popFactor     = CGFloat(1 + Double(velocity) * (config.loudNotePopMultiplier    - 1))
    let particleFactor = CGFloat(1 + Double(velocity) * (config.loudNoteParticleMultiplier - 1))

    // Slightly brighten note color (+50/255 on each channel, clamped) — matches midiplayer
    let br = min(1, noteColor.r + 50.0 / 255.0)
    let bg = min(1, noteColor.g + 50.0 / 255.0)
    let bb = min(1, noteColor.b + 50.0 / 255.0)

    var result: [MidibarParticle] = []

    // ── Dust particles ────────────────────────────────────────────────────────
    let count = max(1, Int(CGFloat(config.numToEmit) * velScale * particleFactor))
    let angleCenter = config.emissionAngle * .pi / 180
    let angleRange  = config.emissionAngleRange * .pi / 180

    for _ in 0..<count {
        // Gamma-like temperature spread around 80 (matches ParticleTemperatureMean in midiplayer)
        let temperature = Float.random(in: 50...110)

        let angle = angleCenter + Double.random(in: -angleRange / 2 ... angleRange / 2)
        let spd   = CGFloat(config.speed + Double.random(in: -config.speedRange / 2 ... config.speedRange / 2))
                  * velScale * popFactor

        // Velocity: angle 90° = straight up in standard math.
        // upSign flips vy so "up" always means away from the piano.
        let vx = CGFloat(cos(angle)) * spd
        let vy = CGFloat(sin(angle)) * spd * upSign

        result.append(MidibarParticle(
            x: pos.x + CGFloat.random(in: -8...8),
            y: pos.y,
            vx: vx, vy: vy,
            temperature: temperature,
            r: br, g: bg, b: bb,
            kind: .dust
        ))
    }

    // ── Smoke particle (one per note if mist enabled) ─────────────────────────
    if config.mistEnabled && config.mistStrength > 0 {
        let temperature = Float.random(in: 50...110)
        let smokeSpeed  = CGFloat(config.speed * 0.25) * velScale
        let vy = smokeSpeed * upSign * CGFloat(config.mistStrength)

        result.append(MidibarParticle(
            x: pos.x + CGFloat.random(in: -12...12),
            y: pos.y,
            vx: CGFloat.random(in: -1...1) * smokeSpeed * 0.2,
            vy: vy,
            temperature: temperature,
            r: br, g: bg, b: bb,
            kind: .smoke
        ))
    }

    return result
}
