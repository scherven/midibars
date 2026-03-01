import SwiftUI

struct WaveformView: View {
    let samples: [Float]
    var startPercent: Double = 0
    var playbackPercent: Double = 0

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }

            let midY = size.height / 2
            let barWidth = size.width / CGFloat(samples.count)

            var waveform = Path()
            for (i, sample) in samples.enumerated() {
                let x = CGFloat(i) * barWidth + barWidth / 2
                let amplitude = CGFloat(sample) * midY * 0.9
                waveform.move(to: CGPoint(x: x, y: midY - amplitude))
                waveform.addLine(to: CGPoint(x: x, y: midY + amplitude))
            }
            context.stroke(
                waveform,
                with: .color(.accentColor.opacity(0.6)),
                lineWidth: max(barWidth * 0.7, 1)
            )

            var centerLine = Path()
            centerLine.move(to: CGPoint(x: 0, y: midY))
            centerLine.addLine(to: CGPoint(x: size.width, y: midY))
            context.stroke(centerLine, with: .color(.primary.opacity(0.08)), lineWidth: 0.5)

            drawVerticalLine(in: context, size: size, atPercent: startPercent, color: .red)
            drawVerticalLine(in: context, size: size, atPercent: playbackPercent, color: .green)
        }
    }
}
