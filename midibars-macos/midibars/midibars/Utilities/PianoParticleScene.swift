import SpriteKit

class PianoParticleScene: SKScene {
    var particleConfig = ParticleConfiguration()

    private static let defaultTexture: SKTexture = {
        let diameter: CGFloat = 16
        let image = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: rect)
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

    /// Emit particles at a normalized position (0-1 range in both axes, SwiftUI-style origin at top-left).
    /// The scene converts to SpriteKit coordinates internally.
    func emitParticles(atNormalized normalizedPoint: CGPoint, color: NSColor) {
        guard particleConfig.enabled, size.width > 0, size.height > 0 else { return }

        let position = CGPoint(
            x: normalizedPoint.x * size.width,
            y: (1 - normalizedPoint.y) * size.height
        )

        let emitter = SKEmitterNode()
        let config = particleConfig

        if config.useCircleParticle {
            emitter.particleTexture = Self.defaultTexture
        } else if let name = config.customTextureName {
            emitter.particleTexture = SKTexture(imageNamed: name)
        }

        emitter.particleBirthRate = CGFloat(config.birthRate)
        emitter.numParticlesToEmit = config.numToEmit
        emitter.emissionAngle = CGFloat(config.emissionAngle * .pi / 180)
        emitter.emissionAngleRange = CGFloat(config.emissionAngleRange * .pi / 180)

        emitter.particleLifetime = CGFloat(config.lifetime)
        emitter.particleLifetimeRange = CGFloat(config.lifetimeRange)

        emitter.particleSpeed = CGFloat(config.speed)
        emitter.particleSpeedRange = CGFloat(config.speedRange)

        emitter.xAcceleration = CGFloat(config.xAcceleration)
        emitter.yAcceleration = CGFloat(config.yAcceleration)

        emitter.particleScale = CGFloat(config.scale)
        emitter.particleScaleRange = CGFloat(config.scaleRange)
        emitter.particleScaleSpeed = CGFloat(config.scaleSpeed)

        emitter.particleAlpha = CGFloat(config.alpha)
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

        let totalLife = config.lifetime + config.lifetimeRange + 0.1
        emitter.run(.sequence([
            .wait(forDuration: totalLife),
            .removeFromParent()
        ]))
    }

    func removeAllParticles() {
        removeAllChildren()
    }
}
