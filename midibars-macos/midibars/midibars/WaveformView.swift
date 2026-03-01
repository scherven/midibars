import SwiftUI
import AVFoundation

struct AudioWaveformPanel: View {
    @ObservedObject var project: ProjectState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(project.audioURL?.lastPathComponent ?? "Audio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

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
                                project.audioStartPercent = min(max(percent, 0), 100)
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
}

enum WaveformExtractor {
    static func loadSamples(from url: URL, targetCount: Int = 800) async -> [Float] {
        let asset = AVURLAsset(url: url)

        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else {
            return []
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        guard reader.startReading() else { return [] }

        var rawSamples = [Int16]()

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard length > 0 else { continue }

            let sampleCount = length / MemoryLayout<Int16>.stride
            var buffer = [Int16](repeating: 0, count: sampleCount)
            buffer.withUnsafeMutableBytes { ptr in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
            }
            rawSamples.append(contentsOf: buffer)
        }

        guard !rawSamples.isEmpty else { return [] }

        let binSize = max(rawSamples.count / targetCount, 1)
        var result = [Float]()
        result.reserveCapacity(min(targetCount, rawSamples.count))

        for start in stride(from: 0, to: rawSamples.count, by: binSize) {
            let end = min(start + binSize, rawSamples.count)
            var peak: Int32 = 0
            for i in start..<end {
                let v = abs(Int32(rawSamples[i]))
                if v > peak { peak = v }
            }
            result.append(Float(peak) / Float(Int16.max))
        }

        return result
    }
}
