import SwiftUI

struct MIDIPianoRollPanel: View {
    @ObservedObject var project: ProjectState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "pianokeys")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(project.midiURL?.lastPathComponent ?? "MIDI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
//                if let data = project.midiData {
//                    Text("\(data.notes.count) notes")
//                        .font(.caption2)
//                        .foregroundStyle(.tertiary)
//                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if project.isLoadingMIDI {
                ProgressView("Loading MIDI…")
                    .font(.caption)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let midiData = project.midiData {
                GeometryReader { geo in
                    PianoRollView(
                        data: midiData,
                        startPercent: project.midiStartPercent,
                        playbackPercent: project.midiPlaybackPercent
                    )
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onEnded { value in
                                let percent = Double(value.location.x / geo.size.width) * 100.0
                                project.midiStartPercent = min(max(percent, 0), 100)
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

struct PianoRollView: View {
    let data: MIDIData
    var startPercent: Double = 0
    var playbackPercent: Double = 0

    var body: some View {
        Canvas { context, size in
            guard !data.notes.isEmpty, data.duration > 0 else { return }

            let pitchSpan = max(Int(data.maxPitch) - Int(data.minPitch) + 1, 1)
            let noteHeight = size.height / CGFloat(pitchSpan)
            let timeScale = size.width / data.duration

            drawOctaveLines(context: context, size: size, pitchSpan: pitchSpan, noteHeight: noteHeight)
            drawNotes(context: context, size: size, noteHeight: noteHeight, timeScale: timeScale)

            let startX = size.width * CGFloat(startPercent / 100.0)
            var startLine = Path()
            startLine.move(to: CGPoint(x: startX, y: 0))
            startLine.addLine(to: CGPoint(x: startX, y: size.height))
            context.stroke(startLine, with: .color(.red), lineWidth: 1.5)

            let playX = size.width * CGFloat(playbackPercent / 100.0)
            var playLine = Path()
            playLine.move(to: CGPoint(x: playX, y: 0))
            playLine.addLine(to: CGPoint(x: playX, y: size.height))
            context.stroke(playLine, with: .color(.green), lineWidth: 1.5)
        }
    }

    private func drawOctaveLines(context: GraphicsContext, size: CGSize, pitchSpan: Int, noteHeight: CGFloat) {
        let basePitch = Int(data.minPitch)
        for pitch in stride(from: ((basePitch / 12) + 1) * 12, through: Int(data.maxPitch), by: 12) {
            let offset = CGFloat(pitch - basePitch)
            let y = size.height - offset * noteHeight
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(.primary.opacity(0.06)), lineWidth: 0.5)
        }
    }

    private func drawNotes(context: GraphicsContext, size: CGSize, noteHeight: CGFloat, timeScale: Double) {
        let basePitch = Int(data.minPitch)

        for note in data.notes {
            let x = note.startTime * timeScale
            let w = max(note.duration * timeScale, 1.5)
            let pitchOffset = CGFloat(Int(note.pitch) - basePitch)
            let y = size.height - (pitchOffset + 1) * noteHeight

            let insetY = noteHeight * 0.08
            let rect = CGRect(x: x, y: y + insetY, width: w, height: noteHeight - insetY * 2)
            let radius = min(noteHeight * 0.15, 2)

            let velocity = Double(note.velocity) / 127.0
            let opacity = 0.35 + 0.65 * velocity

            let shape = RoundedRectangle(cornerRadius: radius)
            context.fill(shape.path(in: rect), with: .color(.accentColor.opacity(opacity)))
        }
    }
}
