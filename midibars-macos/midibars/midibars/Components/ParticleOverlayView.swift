import SwiftUI
import SpriteKit

struct ParticleOverlayView: View {
    let scene: PianoParticleScene

    var body: some View {
        SpriteView(scene: scene, options: [.allowsTransparency])
            .allowsHitTesting(false)
    }
}
