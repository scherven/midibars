import Foundation

struct ParticleConfiguration: Codable, Equatable {
    var enabled: Bool = true

    // MARK: - Emission

    /// Birth rate is no longer used — kept for Codable compatibility.
    var birthRate: Double = 80
    /// Number of dust particles spawned per note event.
    var numToEmit: Int = 8
    /// Angle (degrees) for initial velocity direction; 90 = straight up.
    var emissionAngle: Double = 90
    /// Random spread around emissionAngle (degrees).
    var emissionAngleRange: Double = 60

    // MARK: - Lifetime
    // Particle lifetime is now driven by temperature decay (see MidibarParticleSystem.swift).
    // These fields are kept for Codable compatibility but are currently unused.

    var lifetime: Double = 3.0
    var lifetimeRange: Double = 0.5

    // MARK: - Speed

    var speed: Double = 100
    var speedRange: Double = 180

    // MARK: - Acceleration
    // Physics (gravity, buoyancy, drag) are now internal constants in MidibarParticleSystem.swift.
    // These fields are kept for Codable compatibility but are no longer applied.

    var xAcceleration: Double = 0
    var yAcceleration: Double = 0

    // MARK: - Scale
    // Particle size is controlled by MidibarParticle.dustBaseRadius / smokeBaseRadius.
    // These fields are kept for Codable compatibility.

    var scale: Double = 1.0
    var scaleRange: Double = 0.0
    var scaleSpeed: Double = 0.0

    // MARK: - Rotation (unused — kept for Codable compatibility)

    var rotationSpeed: Double = 0.0
    var rotationRange: Double = 0.0
    var longNoteSwirlMultiplier: Double = 1.0
    var swirlStrength: Double = 0

    // MARK: - Velocity / duration response

    /// Scale/speed boost for louder notes (1 = none, 2 = double at full velocity).
    var loudNotePopMultiplier: Double = 1.5
    /// Extra particles for louder notes (1 = none, 2 = double at full velocity).
    var loudNoteParticleMultiplier: Double = 1.5
    /// Re-emit for held notes every N seconds (0 = only on note-on).
    var sustainedEmitInterval: Double = 0.05

    // MARK: - Alpha (unused — temperature now drives alpha; kept for Codable compatibility)

    var alpha: Double = 1.0
    var alphaSpeed: Double = 0.0
    var alphaRange: Double = 0.0

    // MARK: - Color

    var useNoteColor: Bool = true
    var particleColorRed: Double = 1.0
    var particleColorGreen: Double = 0.3
    var particleColorBlue: Double = 0.3
    var colorBlendFactor: Double = 1.0
    var colorBlendFactorRange: Double = 0.0

    // MARK: - Shape (unused — kept for Codable compatibility)

    var useCircleParticle: Bool = true
    var customTextureName: String? = nil

    // MARK: - Mist / smoke

    /// Enable the expanding smoke blob that accompanies each note.
    var mistEnabled: Bool = true
    /// Smoke particle alpha multiplier (0 = off, 1 = full opacity).
    var mistStrength: Double = 0.35
}
