import SwiftUI

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

            drawVerticalLine(in: context, size: size, atPercent: startPercent, color: .red)
            drawVerticalLine(in: context, size: size, atPercent: playbackPercent, color: .green)
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
