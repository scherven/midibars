import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @ObservedObject var project: ProjectState

    @State private var importing = false
    @State private var importTypes: [UTType] = []
    @State private var importingVideo = false
    @State private var importingAudio = false
    @State private var importingMIDI = false

    @State private var importExpanded = true
    @State private var transformExpanded = true
    @State private var cropExpanded = true
    @State private var pianoExpanded = true
    @State private var barsExpanded = true
    @State private var particlesExpanded = true
    @State private var textExpanded = true
    @State private var playbackExpanded = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                DisclosureGroup(isExpanded: $importExpanded) {
                    importSectionContent
                } label: {
                    SectionHeader(title: "Import", icon: "square.and.arrow.down")
                        .animation(.default, value: importExpanded)
                }

                if project.midiURL != nil {
                    DisclosureGroup(isExpanded: $pianoExpanded) {
                        pianoSectionContent
                    } label: {
                        SectionHeader(title: "Piano", icon: "pianokeys")
                    }
                }

                DisclosureGroup(isExpanded: $barsExpanded) {
                    barSectionContent
                } label: {
                    SectionHeader(title: "Bars", icon: "chart.bar")
                }

                DisclosureGroup(isExpanded: $particlesExpanded) {
                    particleSectionContent
                } label: {
                    SectionHeader(title: "Particles", icon: "sparkles")
                }

                DisclosureGroup(isExpanded: $textExpanded) {
                    TextOverlaySectionView(project: project)
                } label: {
                    SectionHeader(title: "Text / Titles", icon: "textformat")
                }

                DisclosureGroup(isExpanded: $transformExpanded) {
                    transformSectionContent
                } label: {
                    SectionHeader(title: "Transform", icon: "arrow.up.left.and.arrow.down.right")
                }

                DisclosureGroup(isExpanded: $cropExpanded) {
                    cropSectionContent
                } label: {
                    SectionHeader(title: "Crop", icon: "crop")
                }

                DisclosureGroup(isExpanded: $playbackExpanded) {
                    playbackSectionContent
                } label: {
                    SectionHeader(title: "Playback", icon: "play.circle")
                }
            }
            .padding(.horizontal)
            .transaction { $0.animation = nil }
        }
        .frame(width: 220)
        .fileImporter(isPresented: $importing, allowedContentTypes: importTypes) { result in
            if case .success(let url) = result {
                importFile(url: url)
            }
            resetImports()
        }
    }

    // MARK: - Import

    private var importSectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {

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
        .padding(.top, 4)
    }

    // MARK: - Bars

    private var barSectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Corner radius:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    TextField("", value: barBinding(\.cornerRadius), format: .number.precision(.fractionLength(0...1)))
                        .font(.caption)
                        .monospacedDigit()
                        .textFieldStyle(.plain)
                        .frame(width: 36)
                    Slider(value: barBinding(\.cornerRadius), in: 0...20)
                        .controlSize(.small)
                }
            }
            ColorPicker("Color:", selection: rgbBinding(
                red: barBinding(\.colorRed),
                green: barBinding(\.colorGreen),
                blue: barBinding(\.colorBlue)
            ), supportsOpacity: false)
            .font(.caption)
        }
        .padding(.top, 4)
    }

    private func barBinding(_ keyPath: WritableKeyPath<BarConfiguration, Double>) -> Binding<Double> {
        Binding(
            get: { project.barConfig[keyPath: keyPath] },
            set: { var c = project.barConfig; c[keyPath: keyPath] = $0; project.barConfig = c }
        )
    }

    // MARK: - Particles

    private var particleSectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Enabled", isOn: particleBinding(\.enabled))
                .font(.caption)
                .toggleStyle(.switch)
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 4) {
                Text("Speed:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    TextField("", value: particleBinding(\.speed), format: .number.precision(.fractionLength(0)))
                        .font(.caption)
                        .monospacedDigit()
                        .textFieldStyle(.plain)
                        .frame(width: 40)
                    Slider(value: particleBinding(\.speed), in: 20...300)
                        .controlSize(.small)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Spread:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: particleBinding(\.emissionAngleRange), in: 10...180)
                    .controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Loud note pop:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: particleBinding(\.loudNotePopMultiplier), in: 1.0...3.0)
                    .controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Loud note particles:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: particleBinding(\.loudNoteParticleMultiplier), in: 1.0...3.0)
                    .controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Sustained emit (s):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    TextField("", value: particleBinding(\.sustainedEmitInterval), format: .number.precision(.fractionLength(2)))
                        .font(.caption)
                        .monospacedDigit()
                        .textFieldStyle(.plain)
                        .frame(width: 36)
                    Slider(value: particleBinding(\.sustainedEmitInterval), in: 0...0.2)
                        .controlSize(.small)
                }
            }
            Toggle("Mist", isOn: particleBinding(\.mistEnabled))
                .font(.caption)
                .toggleStyle(.switch)
                .controlSize(.small)
            if project.particleConfig.mistEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mist strength:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: particleBinding(\.mistStrength), in: 0.1...1.0)
                        .controlSize(.small)
                }
            }
            Toggle("Use note color", isOn: particleBinding(\.useNoteColor))
                .font(.caption)
                .toggleStyle(.switch)
                .controlSize(.small)
            if !project.particleConfig.useNoteColor {
                ColorPicker("Color:", selection: rgbBinding(
                    red: particleBinding(\.particleColorRed),
                    green: particleBinding(\.particleColorGreen),
                    blue: particleBinding(\.particleColorBlue)
                ), supportsOpacity: false)
                .font(.caption)
            }
        }
        .padding(.top, 4)
    }

    private func particleBinding<T>(_ keyPath: WritableKeyPath<ParticleConfiguration, T>) -> Binding<T> {
        Binding(
            get: { project.particleConfig[keyPath: keyPath] },
            set: { var c = project.particleConfig; c[keyPath: keyPath] = $0; project.particleConfig = c }
        )
    }

    private func rgbBinding(red: Binding<Double>, green: Binding<Double>, blue: Binding<Double>) -> Binding<Color> {
        Binding<Color>(
            get: {
                Color(red: red.wrappedValue, green: green.wrappedValue, blue: blue.wrappedValue)
            },
            set: { newColor in
                if let components = NSColor(newColor).usingColorSpace(.sRGB) {
                    red.wrappedValue = Double(components.redComponent)
                    green.wrappedValue = Double(components.greenComponent)
                    blue.wrappedValue = Double(components.blueComponent)
                }
            }
        )
    }

    // MARK: - Transform

    private var transformSectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2) {
                    Text("Scale:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", value: $project.videoScale, formatter: scaleNumberFormatter)
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
                        .tint(Color(nsColor: .controlBackgroundColor))
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
        .padding(.top, 4)
    }

    // MARK: - Crop

    private var cropSectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            CropSlider(label: "Top", value: $project.cropTop)
            CropSlider(label: "Bottom", value: $project.cropBottom)
            CropSlider(label: "Left", value: $project.cropLeft)
            CropSlider(label: "Right", value: $project.cropRight)
        }
        .padding(.top, 4)
    }

    // MARK: - Playback

    private var playbackSectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            .tint(Color(nsColor: .controlBackgroundColor))
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
        .padding(.top, 4)
    }

    // MARK: - Piano

    private var pianoSectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Show Overlay", isOn: $project.showPianoOverlay)
                .font(.caption)
                .toggleStyle(.switch)
                .controlSize(.small)

            Button {
                if project.isSettingPiano {
                    project.isSettingPiano = false
                } else {
                    project.isAdjustingKeys = false
                    project.isSettingPiano = true
                    project.showPianoOverlay = true
                }
            } label: {
                Label(
                    project.isSettingPiano ? "Done" : "Set Position",
                    systemImage: project.isSettingPiano ? "checkmark.circle" : "hand.point.up.left"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Color(nsColor: .controlBackgroundColor))
            .controlSize(.small)

            Button {
                if project.isAdjustingKeys {
                    project.isAdjustingKeys = false
                } else {
                    project.isSettingPiano = false
                    project.ensurePianoEdgesPopulated()
                    project.isAdjustingKeys = true
                    project.showPianoOverlay = true
                }
            } label: {
                Label(
                    project.isAdjustingKeys ? "Done Adjusting" : "Adjust Keys",
                    systemImage: project.isAdjustingKeys ? "checkmark.circle" : "slider.horizontal.3"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Color(nsColor: .controlBackgroundColor))
            .controlSize(.small)

            if !project.pianoWhiteKeyEdges.isEmpty {
                Button("Reset Key Widths") {
                    project.pianoWhiteKeyEdges = []
                    if project.isAdjustingKeys {
                        project.ensurePianoEdgesPopulated()
                    }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Low:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", value: $project.pianoLowNote, format: .number)
                        .font(.caption)
                        .monospacedDigit()
                        .textFieldStyle(.plain)
                        .frame(width: 30)
                    Text(noteName(project.pianoLowNote))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 4) {
                    Text("High:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("", value: $project.pianoHighNote, format: .number)
                        .font(.caption)
                        .monospacedDigit()
                        .textFieldStyle(.plain)
                        .frame(width: 30)
                    Text(noteName(project.pianoHighNote))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.top, 4)
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
