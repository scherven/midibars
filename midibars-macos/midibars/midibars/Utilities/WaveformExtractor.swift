import AVFoundation

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
