import Foundation

struct ParticleConfiguration: Codable, Equatable {
    var enabled: Bool = true

    // MARK: - Emission

    var birthRate: Double = 80
    var numToEmit: Int = 40
    var emissionAngle: Double = 90
    var emissionAngleRange: Double = 150

    // MARK: - Lifetime

    var lifetime: Double = 1.2
    var lifetimeRange: Double = 0.5

    // MARK: - Speed

    var speed: Double = 120
    var speedRange: Double = 60

    // MARK: - Acceleration

    var xAcceleration: Double = 0
    var yAcceleration: Double = 40

    // MARK: - Scale

    var scale: Double = 0.2
    var scaleRange: Double = 0.12
    var scaleSpeed: Double = -0.15

    // MARK: - Rotation (swirl)

    var rotationSpeed: Double = 2.0
    var rotationRange: Double = 4.0

    // MARK: - Alpha

    var alpha: Double = 1.0
    var alphaSpeed: Double = -0.7
    var alphaRange: Double = 0.3

    // MARK: - Color

    var useNoteColor: Bool = true
    var particleColorRed: Double = 1.0
    var particleColorGreen: Double = 0.3
    var particleColorBlue: Double = 0.3
    var colorBlendFactor: Double = 1.0
    var colorBlendFactorRange: Double = 0.2

    // MARK: - Shape

    var useCircleParticle: Bool = true
    var customTextureName: String? = nil
}
