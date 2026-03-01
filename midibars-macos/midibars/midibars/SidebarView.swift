import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @ObservedObject var project: ProjectState

    @State private var importingVideo = false
    @State private var importingAudio = false
    @State private var importingMIDI = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Import", icon: "square.and.arrow.down")

                FileImportRow(icon: "film", label: "Video", url: project.videoURL) {
                    importingVideo = true
                }
                FileImportRow(icon: "waveform", label: "Audio", url: project.audioURL) {
                    importingAudio = true
                }
                FileImportRow(icon: "pianokeys", label: "MIDI", url: project.midiURL) {
                    importingMIDI = true
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Transform", icon: "arrow.up.left.and.arrow.down.right")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Scale: \(project.videoScale, specifier: "%.2f")x")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Slider(value: $project.videoScale, in: 0.1...5.0)
                        .controlSize(.small)
                }

                Button(action: project.resetTransform) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Playback", icon: "play.circle")

                Button(action: project.togglePlayback) {
                    Label(
                        project.isPlaying ? "Pause" : "Play",
                        systemImage: project.isPlaying ? "pause.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
                .keyboardShortcut(KeyEquivalent(" "), modifiers: [])
                .disabled(project.player == nil)
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 200)
        .fileImporter(isPresented: $importingVideo, allowedContentTypes: [.movie, .video]) { result in
            if case .success(let url) = result { project.loadVideo(url: url) }
        }
        .fileImporter(isPresented: $importingAudio, allowedContentTypes: [.mp3, .audio]) { result in
            if case .success(let url) = result { project.loadAudio(url: url) }
        }
        .fileImporter(isPresented: $importingMIDI, allowedContentTypes: [.midi]) { result in
            if case .success(let url) = result { project.loadMIDI(url: url) }
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct FileImportRow: View {
    let icon: String
    let label: String
    let url: URL?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if let url {
                        Text(url.lastPathComponent)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(url != nil ? Color.accentColor.opacity(0.07) : Color(nsColor: .controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }
}
