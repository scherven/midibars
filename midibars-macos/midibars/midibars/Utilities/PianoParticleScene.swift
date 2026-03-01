import SpriteKit

class PianoParticleScene: SKScene {
    var particleConfig = ParticleConfiguration()

    private static let defaultTexture: SKTexture = {
        let diameter: CGFloat = 32
        let image = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let center = CGPoint(x: diameter / 2, y: diameter / 2)
            let radius = diameter / 2
            guard let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    NSColor.white.cgColor,
                    NSColor(white: 1.0, alpha: 0.4).cgColor,
                    NSColor(white: 1.0, alpha: 0.0).cgColor
                ] as CFArray,
                locations: [0.0, 0.35, 1.0]
            ) else { return false }
            ctx.drawRadialGradient(
                gradient,
                startCenter: center, startRadius: 0,
                endCenter: center, endRadius: radius,
                options: .drawsAfterEndLocation
            )
            return true
        }
        return SKTexture(image: image)
    }()

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
    }

    override convenience init() {
        self.init(size: CGSize(width: 1, height: 1))
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        backgroundColor = .clear
        scaleMode = .resizeFill
    }

    /// Emit particles at a normalized position (0-1 range, SwiftUI-style origin at top-left).
    /// `velocity` is 0.0-1.0 (from MIDI 0-127); louder = brighter, faster, more particles.
    /// `noteDuration` is the note length in seconds; longer notes get more swirl when configured.
    func emitParticles(atNormalized normalizedPoint: CGPoint, color: NSColor, velocity: CGFloat, noteDuration: Double = 0) {
        guard particleConfig.enabled, size.width > 0, size.height > 0 else { return }

        let velScale = max(0.3, velocity)
        let config = particleConfig

        let popFactor = 1 + Double(velocity) * (config.loudNotePopMultiplier - 1)
        let particleFactor = 1 + Double(velocity) * (config.loudNoteParticleMultiplier - 1)
        let durationCap = min(noteDuration, 2.0)
        let swirlFactor = 1 + (durationCap / 2.0) * (config.longNoteSwirlMultiplier - 1)

        let position = CGPoint(
            x: normalizedPoint.x * size.width,
            y: (1 - normalizedPoint.y) * size.height
        )

        let emitter = SKEmitterNode()

        if config.useCircleParticle {
            emitter.particleTexture = Self.defaultTexture
        } else if let name = config.customTextureName {
            emitter.particleTexture = SKTexture(imageNamed: name)
        }

        emitter.particlePositionRange = CGVector(dx: 8, dy: 0)

        emitter.particleBirthRate = CGFloat(config.birthRate) * velScale * CGFloat(particleFactor)
        emitter.numParticlesToEmit = Int(Double(config.numToEmit) * Double(velScale) * particleFactor)
        emitter.emissionAngle = CGFloat(config.emissionAngle * .pi / 180)
        emitter.emissionAngleRange = CGFloat(config.emissionAngleRange * .pi / 180)

        emitter.particleLifetime = CGFloat(config.lifetime) * velScale
        emitter.particleLifetimeRange = CGFloat(config.lifetimeRange)

        emitter.particleSpeed = CGFloat(config.speed) * velScale * CGFloat(popFactor)
        emitter.particleSpeedRange = CGFloat(config.speedRange)

        emitter.xAcceleration = CGFloat(config.xAcceleration)
        emitter.yAcceleration = CGFloat(config.yAcceleration) * velScale

        emitter.particleScale = CGFloat(config.scale) * CGFloat(popFactor)
        emitter.particleScaleRange = CGFloat(config.scaleRange)
        emitter.particleScaleSpeed = CGFloat(config.scaleSpeed)

        emitter.particleRotationSpeed = CGFloat(config.rotationSpeed) * CGFloat(swirlFactor)
        emitter.particleRotationRange = CGFloat(config.rotationRange) * CGFloat(swirlFactor)

        emitter.particleAlpha = CGFloat(config.alpha) * velScale
        emitter.particleAlphaSpeed = CGFloat(config.alphaSpeed)
        emitter.particleAlphaRange = CGFloat(config.alphaRange)

        if config.useNoteColor {
            emitter.particleColor = color
        } else {
            emitter.particleColor = NSColor(
                red: config.particleColorRed,
                green: config.particleColorGreen,
                blue: config.particleColorBlue,
                alpha: 1.0
            )
        }
        emitter.particleColorBlendFactor = CGFloat(config.colorBlendFactor)
        emitter.particleColorBlendFactorRange = CGFloat(config.colorBlendFactorRange)

        emitter.particleBlendMode = .add
        emitter.position = position
        addChild(emitter)

        let totalLife = Double(emitter.particleLifetime + emitter.particleLifetimeRange) + 0.1
        emitter.run(.sequence([
            .wait(forDuration: totalLife),
            .removeFromParent()
        ]))
    }

    func removeAllParticles() {
        removeAllChildren()
    }
}
