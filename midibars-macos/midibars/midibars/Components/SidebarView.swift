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
        List {
            Section(isExpanded: $importExpanded) {
                importSectionContent
            } header: {
                SectionHeader(title: "Import", icon: "square.and.arrow.down")
            }

            if project.midiURL != nil {
                Section(isExpanded: $pianoExpanded) {
                    pianoSectionContent
                } header: {
                    SectionHeader(title: "Piano", icon: "pianokeys")
                }
            }

            Section(isExpanded: $barsExpanded) {
                barSectionContent
            } header: {
                SectionHeader(title: "Bars", icon: "chart.bar")
            }

            Section(isExpanded: $particlesExpanded) {
                particleSectionContent
            } header: {
                SectionHeader(title: "Particles", icon: "sparkles")
            }

            Section(isExpanded: $textExpanded) {
                textSectionContent
            } header: {
                SectionHeader(title: "Text / Titles", icon: "textformat")
            }

            Section(isExpanded: $transformExpanded) {
                transformSectionContent
            } header: {
                SectionHeader(title: "Transform", icon: "arrow.up.left.and.arrow.down.right")
            }

            Section(isExpanded: $cropExpanded) {
                cropSectionContent
            } header: {
                SectionHeader(title: "Crop", icon: "crop")
            }

            Section(isExpanded: $playbackExpanded) {
                playbackSectionContent
            } header: {
                SectionHeader(title: "Playback", icon: "play.circle")
            }
        }
        .foregroundStyle(Color.primary)
        .listStyle(.sidebar)
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
            VStack(alignment: .leading, spacing: 4) {
                Text("Color:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    colorChannelField("R", value: barBinding(\.colorRed))
                    colorChannelField("G", value: barBinding(\.colorGreen))
                    colorChannelField("B", value: barBinding(\.colorBlue))
                }
            }
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
                Text("Scale (size):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: particleBinding(\.scale), in: 0.05...0.8)
                    .controlSize(.small)
            }
            Toggle("Use note color", isOn: particleBinding(\.useNoteColor))
                .font(.caption)
                .toggleStyle(.switch)
                .controlSize(.small)
            if !project.particleConfig.useNoteColor {
                HStack(spacing: 6) {
                    colorChannelField("R", value: particleBinding(\.particleColorRed))
                    colorChannelField("G", value: particleBinding(\.particleColorGreen))
                    colorChannelField("B", value: particleBinding(\.particleColorBlue))
                }
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

    // MARK: - Text / Titles

    private var textSectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                project.textOverlays.append(TextOverlayItem())
                project.selectedTextOverlayID = project.textOverlays.last?.id
            } label: {
                Label("Add Text Box", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            textOverlays()

            if let id = project.selectedTextOverlayID,
               let index = project.textOverlays.firstIndex(where: { $0.id == id }) {
                textOverlayEditor(binding: Binding(
                    get: { index < project.textOverlays.count ? project.textOverlays[index] : TextOverlayItem() },
                    set: { var arr = project.textOverlays; arr[index] = $0; project.textOverlays = arr }
                ))
                Button("Remove") {
                    project.textOverlays.removeAll { $0.id == id }
                    project.selectedTextOverlayID = project.textOverlays.first?.id
                }
                .font(.caption)
                .foregroundStyle(.red)
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }
    
    private func textOverlays() -> some View {
        ForEach(project.textOverlays) { item in
            Button {
                project.selectedTextOverlayID = item.id
            } label: {
                textOverlay(item: item)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func textOverlay(item: TextOverlayItem) -> some View {
        HStack {
            Text(item.text.isEmpty ? "Text" : String(item.text.prefix(20)))
                .lineLimit(1)
                .font(.caption)
            Spacer()
            if project.selectedTextOverlayID == item.id {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
//                    .foregroundStyle(.accent)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(project.selectedTextOverlayID == item.id ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
    }

    private func textOverlayEditor(binding: Binding<TextOverlayItem>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Text", text: binding.text)
                .textFieldStyle(.roundedBorder)
                .font(.caption)

            HStack(spacing: 2) {
                Text("Font size:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("", value: binding.fontSize, format: .number.precision(.fractionLength(0)))
                    .font(.caption)
                    .monospacedDigit()
                    .textFieldStyle(.plain)
                    .frame(width: 36)
            }
            HStack(spacing: 6) {
                colorChannelField("R", value: binding.colorRed)
                colorChannelField("G", value: binding.colorGreen)
                colorChannelField("B", value: binding.colorBlue)
            }

            Group {
                HStack(spacing: 2) {
                    Text("Position X:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("", value: binding.positionX, format: .number.precision(.fractionLength(2)))
                        .font(.caption)
                        .monospacedDigit()
                        .textFieldStyle(.plain)
                        .frame(width: 40)
                }
                HStack(spacing: 2) {
                    Text("Position Y:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("", value: binding.positionY, format: .number.precision(.fractionLength(2)))
                        .font(.caption)
                        .monospacedDigit()
                        .textFieldStyle(.plain)
                        .frame(width: 40)
                }
            }

            Text("Fade in (video time)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text("At (s):")
                    .font(.caption2)
                TextField("", value: binding.fadeInAt, format: .number.precision(.fractionLength(1)))
                    .font(.caption)
                    .monospacedDigit()
                    .textFieldStyle(.plain)
                    .frame(width: 36)
                Text("Dur:")
                    .font(.caption2)
                TextField("", value: binding.fadeInDuration, format: .number.precision(.fractionLength(1)))
                    .font(.caption)
                    .monospacedDigit()
                    .textFieldStyle(.plain)
                    .frame(width: 36)
            }
            Text("Fade out (0 = stay on)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text("At (s):")
                    .font(.caption2)
                TextField("", value: binding.fadeOutAt, format: .number.precision(.fractionLength(1)))
                    .font(.caption)
                    .monospacedDigit()
                    .textFieldStyle(.plain)
                    .frame(width: 36)
                Text("Dur:")
                    .font(.caption2)
                TextField("", value: binding.fadeOutDuration, format: .number.precision(.fractionLength(1)))
                    .font(.caption)
                    .monospacedDigit()
                    .textFieldStyle(.plain)
                    .frame(width: 36)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    private func colorChannelField(_ label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("", value: value, format: .number.precision(.fractionLength(2)))
                .font(.caption)
                .monospacedDigit()
                .textFieldStyle(.plain)
                .frame(width: 32)
        }
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
