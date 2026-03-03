import SpriteKit

class PianoParticleScene: SKScene {
    var particleConfig = ParticleConfiguration() {
        didSet {
            if oldValue.swirlStrength != particleConfig.swirlStrength {
                updateVortexField()
            }
        }
    }

    private var vortexNode: SKFieldNode?

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

    private static let mistTexture: SKTexture = {
        let diameter: CGFloat = 64
        let image = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let center = CGPoint(x: diameter / 2, y: diameter / 2)
            let radius = diameter / 2
            guard let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    NSColor(white: 1.0, alpha: 0.5).cgColor,
                    NSColor(white: 1.0, alpha: 0.15).cgColor,
                    NSColor(white: 1.0, alpha: 0.0).cgColor
                ] as CFArray,
                locations: [0.0, 0.3, 1.0]
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
        setupNoiseField()
    }

    private func setupNoiseField() {
        let noiseField = SKFieldNode.noiseField(withSmoothness: 0.5, animationSpeed: 0.4)
        noiseField.strength = 0.6
        noiseField.falloff = 0
        noiseField.region = SKRegion(size: CGSize(width: 1e5, height: 1e5))
        noiseField.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(noiseField)
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

        if config.mistEnabled && config.mistStrength > 0 {
            emitMist(at: position, color: color, velocity: velScale)
        }

        let emitter = SKEmitterNode()

        if config.useCircleParticle {
            emitter.particleTexture = Self.defaultTexture
        } else if let name = config.customTextureName {
            emitter.particleTexture = SKTexture(imageNamed: name)
        }

        emitter.particlePositionRange = CGVector(dx: 12, dy: 0)

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
        
//        // 1. WIDER SPAWN AREA - match the width of the note bar
//        // Change from a point source to a wide horizontal spread
//        emitter.particlePositionRange = CGVector(dx: 40, dy: 1)  // was dx: 12, dy: 0
//        // Add dy spread so particles don't all spawn on the exact same horizontal line
//
//        // 2. FAN OUT THE EMISSION ANGLE - full upward cone, not a narrow beam
//        emitter.emissionAngle = CGFloat.pi / 2               // straight up
//        emitter.emissionAngleRange = CGFloat.pi * 0.75       // ±67.5° wide fan (was likely narrow)
//
//        // 3. ADD TURBULENCE - this is the biggest fix for "stripes"
//        // Add a noise field to your scene to break up the columnar pattern
        let noiseField = SKFieldNode.noiseField(withSmoothness: 0.5, animationSpeed: 0.3)
        noiseField.strength = 0.8
        noiseField.position = CGPoint(x: size.width / 2, y: size.height / 2)
        noiseField.region = SKRegion(size: CGSize(width: 1e5, height: 1e5))
        noiseField.falloff = 0
        addChild(noiseField)
//
//        // 4. RANDOMIZE SPEED MORE — stripes happen when all particles travel same distance
        emitter.particleSpeed = CGFloat(config.speed) * velScale * CGFloat(popFactor)
        emitter.particleSpeedRange = CGFloat(config.speed) * 1.2  // range = 120% of base speed
//
//        // 5. ADD DRIFT — slight sideways acceleration breaks up columns
        emitter.xAcceleration = CGFloat.random(in: -30...30)  // random sideways drift per emitter
//
//        // 6. SCALE UP PARTICLES SLIGHTLY + more range = gaps fill in
//        emitter.particleScale = CGFloat(config.scale) * CGFloat(popFactor) * 1.3
//        emitter.particleScaleRange = CGFloat(config.scaleRange) + 0.4
//
//        // 7. STAGGER BIRTH — burst mode creates "wall" of simultaneous particles
//        // Increase birth rate but reduce numToEmit so they trickle out, not fire at once
        emitter.particleBirthRate = CGFloat(config.birthRate) * velScale * CGFloat(particleFactor) * 2.0
//        emitter.numParticlesToEmit = Int(Double(config.numToEmit) * Double(velScale) * particleFactor * 0.6)
//
//        // Bright central burst - fires in all directions
//        let emitter3 = SKEmitterNode()
//        emitter3.emissionAngleRange = .pi * 2       // 360° burst
//        emitter3.particleSpeed = 120
//        emitter3.particleSpeedRange = 80
//        emitter3.particleLifetime = 0.6             // short-lived, snappy
//        emitter3.particleBirthRate = 800
//        emitter3.numParticlesToEmit = 40
//        emitter3.particleScale = 0.15
//        emitter3.particleAlpha = 1.0
//        emitter3.particleAlphaSpeed = -2.5          // fast fade
//        emitter3.particleBlendMode = .add
//        emitter3.position = position
//        
//        // PRIMARY FOUNTAIN - tight upward column with spread
//        let emitter2 = SKEmitterNode()
//        emitter2.emissionAngle = .pi / 2
//        emitter2.emissionAngleRange = .pi / 5       // ~36° cone
//        emitter2.particleSpeed = 200
//        emitter2.particleSpeedRange = 120
//        emitter2.particleLifetime = 3.5
//        emitter2.yAcceleration = -40               // slight gravity drag
//        emitter2.particleScale = 0.08
//        emitter2.particleScaleSpeed = 0.03         // grows as it rises
//        emitter2.particleBirthRate = 300
//        emitter2.particleAlpha = 0.7
//        emitter2.particleAlphaSpeed = -0.15
//        emitter2.position = position
//        
//
//        // SECONDARY DRIFT LAYER - wider, slower, gives the "tree" width at top
//        let driftEmitter = SKEmitterNode()
//        driftEmitter.emissionAngleRange = .pi * 0.6
//        driftEmitter.particleSpeed = 60
//        driftEmitter.particleLifetime = 5.0       // lives long = reaches top of screen
//        driftEmitter.particleScale = 0.12
//        driftEmitter.particleScaleSpeed = 0.05
//        driftEmitter.yAcceleration = 10
//        driftEmitter.xAcceleration = CGFloat.random(in: -15...15)
//        driftEmitter.position = position
//        
//        emitter2.particleTexture = Self.defaultTexture
//        emitter3.particleTexture = Self.defaultTexture
//        driftEmitter.particleTexture = Self.defaultTexture
//        emitter2.particleColor = color
//        emitter3.particleColor = color
//        driftEmitter.particleColor = color
//        emitter2.particleColorBlendFactor = 1.0
//        emitter3.particleColorBlendFactor = 1.0
//        driftEmitter.particleColorBlendFactor = 1.0
        
        runEmitter(emitter)
//        runEmitter(emitter2)
//        runEmitter(emitter3)
//        runEmitter(driftEmitter)
    }
    
    private func runEmitter(_ emitter: SKEmitterNode) {
        addChild(emitter)

        let totalLife = Double(emitter.particleLifetime + emitter.particleLifetimeRange) + 0.1
        emitter.run(.sequence([
            .wait(forDuration: totalLife),
            .removeFromParent()
        ]))
    }

    private func emitMist(at position: CGPoint, color: NSColor, velocity: CGFloat) {
        let config = particleConfig
        let strength = CGFloat(config.mistStrength) * max(0.3, velocity)

        let emitter = SKEmitterNode()
        emitter.particleTexture = Self.mistTexture
        emitter.particlePositionRange = CGVector(dx: 20, dy: 0)
        emitter.particleBirthRate = 0
        emitter.numParticlesToEmit = 8
        emitter.emissionAngle = .pi / 2
        emitter.emissionAngleRange = .pi / 6
        emitter.particleLifetime = 2.0
        emitter.particleLifetimeRange = 0.8
        emitter.particleSpeed = 25
        emitter.particleSpeedRange = 20
        emitter.xAcceleration = 0
        emitter.yAcceleration = 15
        emitter.particleScale = 0.6
        emitter.particleScaleRange = 0.3
        emitter.particleScaleSpeed = -0.1
        emitter.particleAlpha = strength * 0.5
        emitter.particleAlphaSpeed = -0.2
        emitter.particleAlphaRange = 0.15
        emitter.particleColor = color
        emitter.particleColorBlendFactor = 0.6
        emitter.particleBlendMode = .alpha
        emitter.position = position
        emitter.zPosition = -1
        addChild(emitter)

        let totalLife = 3.0
        emitter.run(.sequence([
            .wait(forDuration: totalLife),
            .removeFromParent()
        ]))
    }

    private func updateVortexField() {
        vortexNode?.removeFromParent()
        vortexNode = nil

        guard particleConfig.swirlStrength != 0 else { return }

        let field = SKFieldNode.vortexField()
        field.strength = Float(particleConfig.swirlStrength)
        field.position = CGPoint(x: size.width / 2, y: size.height / 2)
        field.region = SKRegion(size: CGSize(width: 1e5, height: 1e5))
        field.falloff = 0
        addChild(field)
        vortexNode = field
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        vortexNode?.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    func removeAllParticles() {
        let vortex = vortexNode
        removeAllChildren()
        if let vortex { addChild(vortex) }
    }
}
