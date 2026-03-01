import SwiftUI

struct AudioWaveformPanel: View {
    @ObservedObject var project: ProjectState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PanelHeaderView(
                icon: "waveform",
                title: project.audioURL?.lastPathComponent ?? "Audio"
            )

            if project.isLoadingWaveform {
                ProgressView("Analyzing audio…")
                    .font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !project.waveformSamples.isEmpty {
                GeometryReader { geo in
                    WaveformView(
                        samples: project.waveformSamples,
                        startPercent: project.audioStartPercent,
                        playbackPercent: project.playbackPercent
                    )
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onEnded { value in
                                let percent = Double(value.location.x / geo.size.width) * 100.0
                                project.audioStartPercent = clampedPercent(percent)
                            }
                    )
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
