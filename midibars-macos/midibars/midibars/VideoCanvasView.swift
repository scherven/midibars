import SwiftUI
import AVFoundation
import AppKit

struct VideoCanvasView: View {
    @ObservedObject var project: ProjectState
    @GestureState private var gestureScale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let canvasSize = canvasDisplaySize(in: geo.size)

            ZStack {
                Color(nsColor: .textBackgroundColor)

                ZStack {
                    Color.black

                    if let player = project.player {
                        PlayerView(player: player)
                            .rotationEffect(.degrees(project.videoRotation))
                            .mask {
                                GeometryReader { maskGeo in
                                    Rectangle()
                                        .padding(.top, maskGeo.size.height * project.cropTop)
                                        .padding(.bottom, maskGeo.size.height * project.cropBottom)
                                        .padding(.leading, maskGeo.size.width * project.cropLeft)
                                        .padding(.trailing, maskGeo.size.width * project.cropRight)
                                }
                            }
                            .scaleEffect(project.videoScale * gestureScale)
                            .offset(
                                x: project.videoOffset.width + dragOffset.width,
                                y: project.videoOffset.height + dragOffset.height
                            )
                    } else {
                        emptyState
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .clipped()
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                .gesture(dragGesture)
                .gesture(magnifyGesture)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "film")
                .font(.system(size: 40, weight: .ultraLight))
            Text("Import a video to begin")
                .font(.subheadline)
        }
        .foregroundStyle(.white.opacity(0.3))
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                project.videoOffset.width += value.translation.width
                project.videoOffset.height += value.translation.height
                dragOffset = .zero
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($gestureScale) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                project.videoScale *= value.magnification
            }
    }

    private func canvasDisplaySize(in available: CGSize) -> CGSize {
        let inset: CGFloat = 0
        let maxW = max(available.width - inset * 2, 100)
        let maxH = max(available.height - inset * 2, 100)
        let aspect = project.canvasAspectRatio

        if maxW / maxH > aspect {
            return CGSize(width: maxH * aspect, height: maxH)
        } else {
            return CGSize(width: maxW, height: maxW / aspect)
        }
    }
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerNSView {
        PlayerNSView(player: player)
    }

    func updateNSView(_ nsView: PlayerNSView, context: Context) {
        nsView.playerLayer.player = player
    }
}

class PlayerNSView: NSView {
    let playerLayer: AVPlayerLayer

    init(player: AVPlayer) {
        playerLayer = AVPlayerLayer(player: player)
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
