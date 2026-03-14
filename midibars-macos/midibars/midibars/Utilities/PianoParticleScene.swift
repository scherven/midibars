import SpriteKit

class PianoParticleScene: SKScene {
    var particleConfig = ParticleConfiguration() {
        didSet { /* no per-config setup needed */ }
    }

    // MARK: - State

    private var particles: [MidibarParticle] = []
    private var dustNodes: [SKSpriteNode] = []
    private var smokeNodes: [SKSpriteNode] = []
    private var lastUpdateTime: TimeInterval = 0

    // MARK: - Textures (matching midiplayer glow shader)
    // Shader: solid white core (inner 4% of radius), then max(0, 0.7 - sqrt(r/outerR)) falloff.

    private static let dustTexture: SKTexture = {
        let diameter: CGFloat = 32
        let image = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let cs = CGColorSpaceCreateDeviceRGB()
            let center = CGPoint(x: diameter / 2, y: diameter / 2)
            let radius = diameter / 2
            // Stops mirror the midiplayer fragment shader output (see MidibarParticleSystem.swift header)
            let colors: [CGColor] = [
                NSColor(white: 1, alpha: 1.00).cgColor,   // loc 0.00 – core center
                NSColor(white: 1, alpha: 1.00).cgColor,   // loc 0.04 – core edge
                NSColor(white: 1, alpha: 0.36).cgColor,   // loc 0.15
                NSColor(white: 1, alpha: 0.18).cgColor,   // loc 0.30
                NSColor(white: 1, alpha: 0.00).cgColor,   // loc 0.51 – glow ends
                NSColor(white: 1, alpha: 0.00).cgColor,   // loc 1.00
            ]
            let locs: [CGFloat] = [0.00, 0.04, 0.15, 0.30, 0.51, 1.00]
            guard let gradient = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locs)
            else { return false }
            ctx.drawRadialGradient(gradient,
                startCenter: center, startRadius: 0,
                endCenter:   center, endRadius: radius,
                options: .drawsAfterEndLocation)
            return true
        }
        return SKTexture(image: image)
    }()

    private static let smokeTexture: SKTexture = {
        let diameter: CGFloat = 64
        let image = NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let cs = CGColorSpaceCreateDeviceRGB()
            let center = CGPoint(x: diameter / 2, y: diameter / 2)
            let radius = diameter / 2
            // Soft blob, no hard core – smoke is blurry and diffuse
            let colors: [CGColor] = [
                NSColor(white: 1, alpha: 0.30).cgColor,
                NSColor(white: 1, alpha: 0.10).cgColor,
                NSColor(white: 1, alpha: 0.00).cgColor,
            ]
            let locs: [CGFloat] = [0.0, 0.5, 1.0]
            guard let gradient = CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locs)
            else { return false }
            ctx.drawRadialGradient(gradient,
                startCenter: center, startRadius: 0,
                endCenter:   center, endRadius: radius,
                options: .drawsAfterEndLocation)
            return true
        }
        return SKTexture(image: image)
    }()

    // MARK: - Lifecycle

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

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        let dt: CGFloat
        if lastUpdateTime == 0 {
            dt = 0
        } else {
            dt = CGFloat(min(currentTime - lastUpdateTime, 0.05)) // cap at 50 ms
        }
        lastUpdateTime = currentTime

        guard dt > 0 else { return }

        // Advance shared physics (SpriteKit: y increases upward → upSign = +1)
        updateMidibarParticles(&particles, dt: dt, upSign: 1.0)

        // Sync node pool to particle array
        syncNodes()
    }

    // MARK: - Emission

    /// Emit particles at a SwiftUI-normalised position (origin top-left, 0–1).
    /// `velocity` is MIDI velocity 0–1; `noteDuration` is note length in seconds (unused in new physics).
    func emitParticles(atNormalized normalizedPoint: CGPoint,
                       color: NSColor,
                       velocity: CGFloat,
                       noteDuration: Double = 0)
    {
        guard particleConfig.enabled, size.width > 0, size.height > 0 else { return }

        // Convert SwiftUI (top-left origin) → SpriteKit (bottom-left, y-up)
        let pos = CGPoint(
            x: normalizedPoint.x * size.width,
            y: (1 - normalizedPoint.y) * size.height
        )

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)

        let new = emitMidibarParticles(
            at: pos,
            noteColor: (r, g, b),
            velocity: velocity,
            config: particleConfig,
            upSign: 1.0
        )
        particles.append(contentsOf: new)
    }

    // MARK: - Node pool management

    private func syncNodes() {
        var dustIdx  = 0
        var smokeIdx = 0

        for p in particles {
            switch p.kind {
            case .dust:
                applyDust(p, to: getOrCreateDustNode(at: dustIdx))
                dustIdx += 1
            case .smoke:
                applySmoke(p, to: getOrCreateSmokeNode(at: smokeIdx))
                smokeIdx += 1
            }
        }

        // Hide pooled nodes beyond what the live particle list needs
        for i in dustIdx..<dustNodes.count   { dustNodes[i].isHidden  = true }
        for i in smokeIdx..<smokeNodes.count { smokeNodes[i].isHidden = true }
    }

    private func getOrCreateDustNode(at index: Int) -> SKSpriteNode {
        if index < dustNodes.count {
            dustNodes[index].isHidden = false
            return dustNodes[index]
        }
        let node = SKSpriteNode(texture: Self.dustTexture)
        node.blendMode = .add
        node.zPosition = 1
        addChild(node)
        dustNodes.append(node)
        return node
    }

    private func getOrCreateSmokeNode(at index: Int) -> SKSpriteNode {
        if index < smokeNodes.count {
            smokeNodes[index].isHidden = false
            return smokeNodes[index]
        }
        let node = SKSpriteNode(texture: Self.smokeTexture)
        node.blendMode = .add
        node.zPosition = 0
        addChild(node)
        smokeNodes.append(node)
        return node
    }

    private func applyDust(_ p: MidibarParticle, to node: SKSpriteNode) {
        node.position = CGPoint(x: p.x, y: p.y)
        node.alpha = p.normalizedAlpha
        // Dust radius in pt: dustBaseRadius = 14 px; SKSpriteNode default texture size = 32 pt → scale accordingly
        let scale = (MidibarParticle.dustBaseRadius * 2) / 32.0
        node.setScale(scale)
        node.color = NSColor(red: p.r, green: p.g, blue: p.b, alpha: 1)
        node.colorBlendFactor = 1.0
    }

    private func applySmoke(_ p: MidibarParticle, to node: SKSpriteNode) {
        node.position = CGPoint(x: p.x, y: p.y)
        // Smoke expands as it cools: scale from 1× to smokeMaxScale× over lifetime
        let coolFraction = CGFloat(1.0 - p.normalizedAlpha)  // 0 = just spawned, 1 = cold
        let scale = (1.0 + coolFraction * (MidibarParticle.smokeMaxScale - 1.0))
                  * (MidibarParticle.smokeBaseRadius * 2) / 64.0
        node.setScale(scale)
        node.alpha = p.normalizedAlpha * CGFloat(particleConfig.mistStrength) * 0.6
        node.color = NSColor(red: p.r, green: p.g, blue: p.b, alpha: 1)
        node.colorBlendFactor = 0.7
    }

    // MARK: - Cleanup

    func removeAllParticles() {
        particles.removeAll()
        dustNodes.forEach { $0.removeFromParent() }
        smokeNodes.forEach { $0.removeFromParent() }
        dustNodes.removeAll()
        smokeNodes.removeAll()
    }
}
