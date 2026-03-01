import SwiftUI

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

                    if project.midiData != nil || project.showPianoOverlay || project.isSettingPiano || project.isAdjustingKeys {
                        PianoOverlayView(project: project)
                    }

                    if project.particleConfig.enabled {
                        ParticleOverlayView(scene: project.particleScene)
                    }

                    if !project.textOverlays.isEmpty {
                        TextOverlayView(project: project, canvasSize: canvasSize)
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .clipped()
                .contentShape(Rectangle())
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
        let inset: CGFloat = 10
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
