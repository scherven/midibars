import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @ObservedObject var project: ProjectState

    @State private var importing = false
    @State private var importTypes: [UTType] = []
    @State private var importingVideo = false
    @State private var importingAudio = false
    @State private var importingMIDI = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                importSection
                Divider()
                transformSection
                Divider()
                cropSection
                Divider()
                playbackSection
            }
            .padding(16)
        }
        .frame(width: 200)
        .fileImporter(isPresented: $importing, allowedContentTypes: importTypes) { result in
            if case .success(let url) = result {
                importFile(url: url)
            }
            resetImports()
        }
    }

    // MARK: - Import

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Import", icon: "square.and.arrow.down")

            FileImportRow(icon: "film", label: "Video", url: project.videoURL) {
                importing = true
                importingVideo = true
                importTypes = [.movie, .video]
            }
            FileImportRow(icon: "waveform", label: "Audio", url: project.audioURL) {
                importing = true
                importingAudio = true
                importTypes = [.mp3, .audio]
            }
            FileImportRow(icon: "pianokeys", label: "MIDI", url: project.midiURL) {
                importing = true
                importingMIDI = true
                importTypes = [.midi]
            }
        }
    }

    // MARK: - Transform

    private var transformSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Transform", icon: "arrow.up.left.and.arrow.down.right")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2) {
                    Text("Scale:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", value: $project.videoScale, formatter: {
                        let f = NumberFormatter()
                        f.maximumFractionDigits = 2
                        f.minimumFractionDigits = 0
                        return f
                    }())
                        .font(.caption)
                        .monospacedDigit()
                        .textFieldStyle(.plain)
                        .frame(width: 40)
                    Text("x")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $project.videoScale, in: 0.1...5.0)
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2) {
                    Text("Rotation:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", value: $project.videoRotation, format: .number.precision(.fractionLength(0...1)))
                        .font(.caption)
                        .monospacedDigit()
                        .textFieldStyle(.plain)
                        .frame(width: 36)
                    Text("°")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $project.videoRotation, in: 0...360)
                    .controlSize(.small)

                HStack(spacing: 4) {
                    ForEach([0.0, 90.0, 180.0, 270.0], id: \.self) { angle in
                        Button("\(Int(angle))°") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                project.videoRotation = angle
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }

            Button(action: project.resetTransform) {
                Label("Reset All", systemImage: "arrow.counterclockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Crop

    private var cropSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Crop", icon: "crop")

            CropSlider(label: "Top", value: $project.cropTop)
            CropSlider(label: "Bottom", value: $project.cropBottom)
            CropSlider(label: "Left", value: $project.cropLeft)
            CropSlider(label: "Right", value: $project.cropRight)
        }
    }

    // MARK: - Playback

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Playback", icon: "play.circle")

            if project.player != nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(project.currentTimeString)
                            .font(.caption)
                            .monospacedDigit()
                        Spacer()
                        Text(project.durationString)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $project.videoPercent, in: 0...100) { editing in
                        if editing {
                            project.beginSeeking()
                        } else {
                            project.endSeeking()
                        }
                    }
                    .controlSize(.small)
                    .onChange(of: project.videoPercent) { _, _ in
                        if project.isSeeking {
                            project.scrubVideo(to: project.videoPercent)
                        }
                    }
                }
            }

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
            .disabled(project.player == nil && project.audioPlayer == nil)

            if project.audioURL != nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 2) {
                        Text("Audio start:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("", value: $project.audioStartPercent, format: .number.precision(.fractionLength(0...2)))
                            .font(.caption)
                            .monospacedDigit()
                            .textFieldStyle(.plain)
                            .frame(width: 48)
                        Text("%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $project.audioStartPercent, in: 0...100)
                        .controlSize(.small)
                }
            }

            if project.midiURL != nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 2) {
                        Text("MIDI start:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("", value: $project.midiStartPercent, format: .number.precision(.fractionLength(0...2)))
                            .font(.caption)
                            .monospacedDigit()
                            .textFieldStyle(.plain)
                            .frame(width: 48)
                        Text("%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $project.midiStartPercent, in: 0...100)
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Helpers

    private func importFile(url: URL) {
        if importingVideo {
            project.loadVideo(url: url)
        } else if importingAudio {
            project.loadAudio(url: url)
        } else if importingMIDI {
            project.loadMIDI(url: url)
        }
    }

    private func resetImports() {
        importing = false
        importingVideo = false
        importingAudio = false
        importingMIDI = false
        importTypes = []
    }
}

// MARK: - Subviews

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

private struct CropSlider: View {
    let label: String
    @Binding var value: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .frame(width: 44, alignment: .leading)
                .foregroundStyle(.secondary)
            Slider(value: $value, in: 0...1.0)
                .controlSize(.small)
            TextField("", value: percentageBinding, format: .number.precision(.fractionLength(0...1)))
                .font(.caption)
                .monospacedDigit()
                .textFieldStyle(.plain)
                .frame(width: 32, alignment: .trailing)
            Text("%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var percentageBinding: Binding<Double> {
        Binding(
            get: { Double(value * 100) },
            set: { value = CGFloat(min(max($0, 0), 100) / 100) }
        )
    }
}
