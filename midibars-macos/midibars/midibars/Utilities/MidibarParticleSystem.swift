// Particle physics and visual style adapted from MIDIPlayer by sppmacd
// https://github.com/sppmacd/midiplayer (BSD 2-Clause License)

import CoreGraphics
import Foundation

// MARK: - Particle

struct MidibarParticle {
    enum Kind { case dust, smoke }

    var x, y: CGFloat      // position in rendering coordinate space (y increases upward)
    var vx, vy: CGFloat    // velocity px/s; positive vy = upward (away from piano)
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

private enum DustPhysics {
    static let xDragPerSec: CGFloat   = 0.55   // fraction of |vx| remaining after 1 s
    static let gravity: CGFloat       = 35.0   // px/s² pulling downward
    static let buoyancy: CGFloat      = 0.022  // px/s per temperature unit pushing upward
    static let tempDecayPerSec: Float = 0.30   // fraction of temperature left after 1 s (≈ 0.98^60)
    static let turbStr: CGFloat       = 20.0   // px/s² turbulence magnitude
}

private enum SmokePhysics {
    static let xDragPerSec: CGFloat   = 0.60
    static let gravity: CGFloat       = 12.0
    static let buoyancy: CGFloat      = 0.042
    static let tempDecayPerSec: Float = 0.55   // smoke cools slower (≈ 0.99^60)
    static let turbStr: CGFloat       = 6.0
}

// MARK: - Physics update

/// Advance all particles by `dt` seconds. Dead particles are removed in-place.
/// Positive vy is upward (both SpriteKit y-up and the flipped CG export context use this convention).
func updateMidibarParticles(_ particles: inout [MidibarParticle], dt: CGFloat) {
    for i in particles.indices.reversed() {
        var p = particles[i]

        let xDrag:     CGFloat
        let gravity:   CGFloat
        let buoyancy:  CGFloat
        let tempDecay: Float
        let turbStr:   CGFloat

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

        // Gravity (pulls downward) and buoyancy (pushes upward when hot)
        p.vy -= gravity * dt
        p.vy += CGFloat(p.temperature) * buoyancy * dt

        // Turbulence: random horizontal + upward-biased vertical (mirrors midiplayer's Perlin + (0,−0.6) bias)
        p.vx += CGFloat.random(in: -1...1) * turbStr * dt
        p.vy += (CGFloat.random(in: -1...1) * 0.4 + 0.6) * turbStr * dt  // 60% upward bias

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
/// `pos` must be in the caller's y-up coordinate space (SpriteKit or the flipped CG export context).
func emitMidibarParticles(
    at pos: CGPoint,
    noteColor: (r: CGFloat, g: CGFloat, b: CGFloat),
    velocity: CGFloat,      // MIDI velocity normalised 0–1
    config: ParticleConfiguration
) -> [MidibarParticle] {
    guard config.enabled else { return [] }

    let velScale       = max(0.3, velocity)
    let popFactor      = CGFloat(1 + Double(velocity) * (config.loudNotePopMultiplier - 1))
    let particleFactor = CGFloat(1 + Double(velocity) * (config.loudNoteParticleMultiplier - 1))

    // Slightly brighten note color (+50/255 per channel, clamped) — matches midiplayer
    let br = min(1, noteColor.r + 50.0 / 255.0)
    let bg = min(1, noteColor.g + 50.0 / 255.0)
    let bb = min(1, noteColor.b + 50.0 / 255.0)

    let count = max(1, Int(CGFloat(config.numToEmit) * velScale * particleFactor))
    var result: [MidibarParticle] = []
    result.reserveCapacity(count + 1)

    let angleCenter = config.emissionAngle * .pi / 180
    let angleRange  = config.emissionAngleRange * .pi / 180

    // ── Dust particles ────────────────────────────────────────────────────────
    for _ in 0..<count {
        let temperature = Float.random(in: 50...110)  // gamma-like spread around 80
        let angle = angleCenter + Double.random(in: -angleRange / 2 ... angleRange / 2)
        let spd   = CGFloat(config.speed + Double.random(in: -config.speedRange / 2 ... config.speedRange / 2))
                  * velScale * popFactor

        result.append(MidibarParticle(
            x: pos.x + CGFloat.random(in: -8...8),
            y: pos.y,
            vx: CGFloat(cos(angle)) * spd,
            vy: CGFloat(sin(angle)) * spd,  // angle 90° = straight up
            temperature: temperature,
            r: br, g: bg, b: bb,
            kind: .dust
        ))
    }

    // ── Smoke particle (one per note if enabled) ──────────────────────────────
    if config.mistEnabled && config.mistStrength > 0 {
        let smokeSpeed = CGFloat(config.speed * 0.25) * velScale
        result.append(MidibarParticle(
            x: pos.x + CGFloat.random(in: -12...12),
            y: pos.y,
            vx: CGFloat.random(in: -1...1) * smokeSpeed * 0.2,
            vy: smokeSpeed * CGFloat(config.mistStrength),
            temperature: Float.random(in: 50...110),
            r: br, g: bg, b: bb,
            kind: .smoke
        ))
    }

    return result
}
