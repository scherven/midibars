import SwiftUI

struct MIDIPianoRollPanel: View {
    @ObservedObject var project: ProjectState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PanelHeaderView(
                icon: "pianokeys",
                title: project.midiURL?.lastPathComponent ?? "MIDI"
            )

            if project.isLoadingMIDI {
                ProgressView("Loading MIDI…")
                    .font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let midiData = project.midiData {
                GeometryReader { geo in
                    PianoRollView(
                        data: midiData,
                        barConfig: project.barConfig,
                        startPercent: project.midiStartPercent,
                        playbackPercent: project.midiPlaybackPercent
                    )
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onEnded { value in
                                let percent = Double(value.location.x / geo.size.width) * 100.0
                                project.midiStartPercent = clampedPercent(percent)
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
