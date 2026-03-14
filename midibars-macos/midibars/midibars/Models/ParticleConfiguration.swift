import Foundation

struct ParticleConfiguration: Codable, Equatable {
    var enabled: Bool = true

    // MARK: - Emission

    /// Number of dust particles spawned per note event.
    var numToEmit: Int = 8
    /// Angle (degrees) for initial velocity direction; 90 = straight up.
    var emissionAngle: Double = 90
    /// Random spread around emissionAngle (degrees).
    var emissionAngleRange: Double = 60

    // MARK: - Speed

    var speed: Double = 100
    var speedRange: Double = 180

    // MARK: - Velocity response

    /// Scale/speed boost for louder notes (1 = none, 2 = double at full velocity).
    var loudNotePopMultiplier: Double = 1.5
    /// Extra particles for louder notes (1 = none, 2 = double at full velocity).
    var loudNoteParticleMultiplier: Double = 1.5
    /// Re-emit for held notes every N seconds (0 = only on note-on).
    var sustainedEmitInterval: Double = 0.05

    // MARK: - Color

    var useNoteColor: Bool = true
    var particleColorRed: Double = 1.0
    var particleColorGreen: Double = 0.3
    var particleColorBlue: Double = 0.3

    // MARK: - Smoke

    /// Enable the expanding smoke blob that accompanies each note.
    var mistEnabled: Bool = true
    /// Smoke particle alpha multiplier (0 = off, 1 = full opacity).
    var mistStrength: Double = 0.35
}
