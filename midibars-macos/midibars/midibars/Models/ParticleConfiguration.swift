import Foundation

struct ParticleConfiguration: Codable, Equatable {
    var enabled: Bool = true

    // MARK: - Emission

    var birthRate: Double = 80
    var numToEmit: Int = 30
    var emissionAngle: Double = 270
    var emissionAngleRange: Double = 90

    // MARK: - Lifetime

    var lifetime: Double = 0.6
    var lifetimeRange: Double = 0.3

    // MARK: - Speed

    var speed: Double = 150
    var speedRange: Double = 50

    // MARK: - Acceleration

    var xAcceleration: Double = 0
    var yAcceleration: Double = -200

    // MARK: - Scale

    var scale: Double = 0.15
    var scaleRange: Double = 0.1
    var scaleSpeed: Double = -0.2

    // MARK: - Alpha

    var alpha: Double = 1.0
    var alphaSpeed: Double = -1.5
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
