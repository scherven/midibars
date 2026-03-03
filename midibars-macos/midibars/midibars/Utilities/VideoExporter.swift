import Foundation
import AVFoundation
import CoreGraphics
import CoreText
import AppKit

// MARK: - Errors

enum ExportError: LocalizedError {
    case noMedia
    case writerSetupFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noMedia: return "No video, audio, or MIDI to export."
        case .writerSetupFailed(let msg): return "Writer setup failed: \(msg)"
        case .cancelled: return "Export cancelled."
        }
    }
}

// MARK: - Export Snapshot

struct ExportSnapshot: @unchecked Sendable {
    let videoURL: URL?
    let audioURL: URL?
    let midiData: MIDIData?

    let videoOffset: CGSize
    let videoScale: CGFloat
    let videoRotation: Double

    let cropTop: CGFloat
    let cropBottom: CGFloat
    let cropLeft: CGFloat
    let cropRight: CGFloat

    let audioStartPercent: Double
    let midiStartPercent: Double

    let pianoTopLeft: CGPoint
    let pianoTopRight: CGPoint
    let pianoBottomLeft: CGPoint
    let pianoBottomRight: CGPoint
    let pianoLowNote: Int
    let pianoHighNote: Int
    let pianoWhiteKeyEdges: [Double]

    let barConfig: BarConfiguration
    let particleConfig: ParticleConfiguration

    let textOverlays: [TextOverlayItem]
    let globalTextFadeInAt: Double
    let globalTextFadeInDuration: Double
    let globalTextFadeOutAt: Double
    let globalTextFadeOutDuration: Double
    let globalTextFontName: String

    let canvasDisplaySize: CGSize

    @MainActor
    init(from p: ProjectState) {
        videoURL = p.videoURL
        audioURL = p.audioURL
        midiData = p.midiData
        videoOffset = p.videoOffset
        videoScale = p.videoScale
        videoRotation = p.videoRotation
        cropTop = p.cropTop
        cropBottom = p.cropBottom
        cropLeft = p.cropLeft
        cropRight = p.cropRight
        audioStartPercent = p.audioStartPercent
        midiStartPercent = p.midiStartPercent
        pianoTopLeft = p.pianoTopLeft
        pianoTopRight = p.pianoTopRight
        pianoBottomLeft = p.pianoBottomLeft
        pianoBottomRight = p.pianoBottomRight
        pianoLowNote = p.pianoLowNote
        pianoHighNote = p.pianoHighNote
        pianoWhiteKeyEdges = p.pianoWhiteKeyEdges
        barConfig = p.barConfig
        particleConfig = p.particleConfig
        textOverlays = p.textOverlays
        globalTextFadeInAt = p.globalTextFadeInAt
        globalTextFadeInDuration = p.globalTextFadeInDuration
        globalTextFadeOutAt = p.globalTextFadeOutAt
        globalTextFadeOutDuration = p.globalTextFadeOutDuration
        globalTextFontName = p.globalTextFontName
        canvasDisplaySize = p.lastCanvasDisplaySize
    }
}

// MARK: - Export Particle

private struct ExportParticle {
    var x, y: CGFloat
    var vx, vy: CGFloat
    var age, maxAge: CGFloat
    var scale, scaleSpeed: CGFloat
    var alpha, alphaSpeed: CGFloat
    var r, g, b: CGFloat

    var isAlive: Bool { age < maxAge && alpha > 0.005 && scale > 0.001 }
}

// MARK: - VideoExporter

@MainActor
class VideoExporter: ObservableObject {
    @Published var progress: Double = 0
    @Published var exportStartDate: Date?
    @Published var isExporting = false
    @Published var isFinished = false
    @Published var errorMessage: String?
    @Published var outputURL: URL?
    /// Recent frame render times in seconds (slower frames = harder work). Kept for speed wave UI.
    @Published var frameTimeSamples: [TimeInterval] = []

    private var exportTask: Task<Void, Never>?
    private static let maxFrameTimeSamples = 80

    func startExport(project: ProjectState, projectName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(projectName)_export.mp4"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? FileManager.default.removeItem(at: url)

        let snapshot = ExportSnapshot(from: project)

        outputURL = url
        isExporting = true
        isFinished = false
        errorMessage = nil
        progress = 0
        exportStartDate = Date()
        frameTimeSamples = []

        exportTask = Task.detached { [weak self] in
            do {
                try await Self.performExport(snapshot: snapshot, outputURL: url) { p, frameTime in
                    Task { @MainActor in
                        self?.progress = p
                        guard let self else { return }
                        self.frameTimeSamples.append(frameTime)
                        if self.frameTimeSamples.count > Self.maxFrameTimeSamples {
                            self.frameTimeSamples.removeFirst()
                        }
                    }
                }
                await MainActor.run {
                    self?.isExporting = false
                    self?.isFinished = true
                    self?.exportStartDate = nil
                }
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: url)
                await MainActor.run {
                    self?.isExporting = false
                    self?.exportStartDate = nil
                }
            } catch {
                try? FileManager.default.removeItem(at: url)
                await MainActor.run {
                    self?.isExporting = false
                    self?.errorMessage = error.localizedDescription
                    self?.exportStartDate = nil
                }
            }
        }
    }

    func cancel() {
        exportTask?.cancel()
        exportTask = nil
    }

    func openOutputFile() {
        guard let url = outputURL else { return }
        NSWorkspace.shared.open(url)
    }

    func revealInFinder() {
        guard let url = outputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func reset() {
        isExporting = false
        isFinished = false
        errorMessage = nil
        progress = 0
        exportStartDate = nil
        outputURL = nil
        frameTimeSamples = []
    }

    // MARK: - Export Pipeline

    nonisolated private static func performExport(
        snapshot: ExportSnapshot,
        outputURL: URL,
        progressHandler: @Sendable @escaping (Double, TimeInterval) -> Void
    ) async throws {
        var outputWidth = 1920
        var outputHeight = 1080
        var fps: Double = 30
        var totalDuration: Double = 0

        if let videoURL = snapshot.videoURL {
            _ = videoURL.startAccessingSecurityScopedResource()
            let asset = AVAsset(url: videoURL)
            let dur = try await asset.load(.duration)
            totalDuration = CMTimeGetSeconds(dur)
            if let track = try? await asset.loadTracks(withMediaType: .video).first {
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let rect = CGRect(origin: .zero, size: size).applying(transform)
                let w = Int(abs(rect.width))
                let h = Int(abs(rect.height))
                if w > 0 && h > 0 { outputWidth = w; outputHeight = h }
                let nomFPS = try await track.load(.nominalFrameRate)
                if nomFPS > 0 { fps = Double(nomFPS) }
            }
        }

        // For 90° or 270° user rotation, output frame must be portrait (swap width/height).
        let normalizedRotation = (snapshot.videoRotation.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        if normalizedRotation == 90 || normalizedRotation == 270 {
            swap(&outputWidth, &outputHeight)
        }

        if totalDuration <= 0, let audioURL = snapshot.audioURL {
            _ = audioURL.startAccessingSecurityScopedResource()
            let asset = AVAsset(url: audioURL)
            let dur = try await asset.load(.duration)
            totalDuration = CMTimeGetSeconds(dur)
        }

        if totalDuration <= 0, let midiData = snapshot.midiData, midiData.duration > 0 {
            totalDuration = midiData.duration
        }

        guard totalDuration > 0 else { throw ExportError.noMedia }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: outputWidth,
            AVVideoHeightKey: outputHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: outputWidth * outputHeight * 4,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false

        let pbAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: outputWidth,
            kCVPixelBufferHeightKey as String: outputHeight,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pbAttrs
        )
        writer.add(videoInput)

        // Audio setup
        var audioWriterInput: AVAssetWriterInput?
        var audioReaderOutput: AVAssetReaderTrackOutput?
        var audioReader: AVAssetReader?
        var audioStartCMTime = CMTime.zero

        if let audioURL = snapshot.audioURL {
            _ = audioURL.startAccessingSecurityScopedResource()
            let audioAsset = AVAsset(url: audioURL)
            if let track = try? await audioAsset.loadTracks(withMediaType: .audio).first {
                var sampleRate: Double = 44100
                var channels: Int = 2
                if let fmts = try? await track.load(.formatDescriptions), let fmt = fmts.first {
                    if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt) {
                        sampleRate = asbd.pointee.mSampleRate
                        channels = max(1, Int(asbd.pointee.mChannelsPerFrame))
                    }
                }

                let reader = try AVAssetReader(asset: audioAsset)
                let pcm: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: sampleRate,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false,
                    AVNumberOfChannelsKey: channels,
                ]
                let output = AVAssetReaderTrackOutput(track: track, outputSettings: pcm)
                reader.add(output)

                let audioDur = CMTimeGetSeconds(try await audioAsset.load(.duration))
                let startSec = audioDur * max(0, min(1, snapshot.audioStartPercent / 100.0))
                audioStartCMTime = CMTime(seconds: startSec, preferredTimescale: Int32(sampleRate))

                reader.startReading()
                audioReaderOutput = output
                audioReader = reader

                let aac: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: channels,
                    AVEncoderBitRateKey: 192000,
                ]
                let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: aac)
                aInput.expectsMediaDataInRealTime = false
                writer.add(aInput)
                audioWriterInput = aInput
            }
        }

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let totalDurationCMTime = CMTime(seconds: totalDuration, preferredTimescale: 600)

        // Audio writing on a background queue
        let audioFinished = DispatchSemaphore(value: 0)
        if let aWriterInput = audioWriterInput, let aOutput = audioReaderOutput {
            let audioQ = DispatchQueue(label: "com.midibars.audioExport")
            let startCMT = audioStartCMTime
            let durCMT = totalDurationCMTime
            aWriterInput.requestMediaDataWhenReady(on: audioQ) {
                while aWriterInput.isReadyForMoreMediaData {
                    guard let sample = aOutput.copyNextSampleBuffer() else {
                        aWriterInput.markAsFinished()
                        audioFinished.signal()
                        return
                    }
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                    let adjusted = CMTimeSubtract(pts, startCMT)
                    if CMTimeCompare(adjusted, .zero) < 0 { continue }
                    if CMTimeCompare(adjusted, durCMT) >= 0 {
                        aWriterInput.markAsFinished()
                        audioFinished.signal()
                        return
                    }
                    var timing = CMSampleTimingInfo(
                        duration: CMSampleBufferGetDuration(sample),
                        presentationTimeStamp: adjusted,
                        decodeTimeStamp: .invalid
                    )
                    var retimed: CMSampleBuffer?
                    CMSampleBufferCreateCopyWithNewTiming(
                        allocator: nil, sampleBuffer: sample,
                        sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                        sampleBufferOut: &retimed
                    )
                    if let retimed { aWriterInput.append(retimed) }
                }
            }
        } else {
            audioFinished.signal()
        }

        // Video frame generation
        var imageGenerator: AVAssetImageGenerator?
        if let videoURL = snapshot.videoURL {
            let asset = AVAsset(url: videoURL)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.requestedTimeToleranceBefore = .zero
            gen.requestedTimeToleranceAfter = .zero
            gen.appliesPreferredTrackTransform = true
            imageGenerator = gen
        }

        let totalFrames = Int(ceil(totalDuration * fps))
        var particles: [ExportParticle] = []
        var previouslyActiveNotes: Set<UInt8> = []
        var lastSustainedEmitTime: Double = 0
        var previousMidiTime: Double = 0
        let dt = 1.0 / fps
        let w = CGFloat(outputWidth)
        let h = CGFloat(outputHeight)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var frameStartTime = CFAbsoluteTimeGetCurrent()

        for frame in 0..<totalFrames {
            try Task.checkCancellation()

            let time = Double(frame) * dt
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)

            var videoFrame: CGImage?
            if let gen = imageGenerator {
                videoFrame = try? gen.copyCGImage(at: cmTime, actualTime: nil)
            }

            // Get pixel buffer from pool
            guard let pool = adaptor.pixelBufferPool else { continue }
            var pbOut: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pbOut)
            guard let pixelBuffer = pbOut else { continue }

            CVPixelBufferLockBaseAddress(pixelBuffer, [])

            let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)!
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

            guard let ctx = CGContext(
                data: baseAddress,
                width: outputWidth,
                height: outputHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            ) else {
                CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
                continue
            }

            // Flip context to top-left origin (matches SwiftUI / pixel buffer row order)
            ctx.translateBy(x: 0, y: h)
            ctx.scaleBy(x: 1, y: -1)

            // Black background
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

            // Video frame
            if let videoFrame {
                drawVideoFrame(videoFrame, in: ctx, snapshot: snapshot, w: w, h: h)
            }

            // MIDI bars
            drawMidiBars(in: ctx, snapshot: snapshot, time: time, w: w, h: h)

            // Particles
            let midiTime = computeMidiTime(snapshot: snapshot, videoTime: time)
            emitParticlesForFrame(
                snapshot: snapshot, midiTime: midiTime,
                particles: &particles,
                previouslyActiveNotes: &previouslyActiveNotes,
                lastSustainedEmitTime: &lastSustainedEmitTime,
                previousMidiTime: &previousMidiTime,
                w: w, h: h
            )
            updateParticles(&particles, dt: CGFloat(dt), config: snapshot.particleConfig)
            drawParticles(particles, in: ctx, w: w, h: h)

            // Text overlays
            drawTextOverlays(in: ctx, snapshot: snapshot, videoTime: time, videoDuration: totalDuration, w: w, h: h)

            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

            while !videoInput.isReadyForMoreMediaData {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            adaptor.append(pixelBuffer, withPresentationTime: cmTime)

            let frameEndTime = CFAbsoluteTimeGetCurrent()
            let frameDuration = frameEndTime - frameStartTime
            frameStartTime = frameEndTime
            progressHandler(Double(frame) / Double(totalFrames), frameDuration)
        }

        videoInput.markAsFinished()
        audioFinished.wait()

        if let audioReader, audioReader.status == .reading {
            audioReader.cancelReading()
        }

        await writer.finishWriting()
        if writer.status == .failed, let err = writer.error {
            throw err
        }
        progressHandler(1.0, 0)
    }

    // MARK: - Video Frame Drawing

    nonisolated private static func drawVideoFrame(
        _ image: CGImage, in ctx: CGContext,
        snapshot: ExportSnapshot, w: CGFloat, h: CGFloat
    ) {
        let videoAspect = CGFloat(image.width) / CGFloat(image.height)
        let canvasAspect = w / h
        let fittedW: CGFloat, fittedH: CGFloat
        if videoAspect > canvasAspect {
            fittedW = w; fittedH = w / videoAspect
        } else {
            fittedH = h; fittedW = h * videoAspect
        }

        let scaleRatio: CGFloat = snapshot.canvasDisplaySize.width > 0
            ? w / snapshot.canvasDisplaySize.width
            : 1.0
        let offsetX = snapshot.videoOffset.width * scaleRatio
        let offsetY = snapshot.videoOffset.height * scaleRatio

        ctx.saveGState()

        // Crop clip in canvas space
        let cropRect = CGRect(
            x: w * snapshot.cropLeft,
            y: h * snapshot.cropTop,
            width: w * (1 - snapshot.cropLeft - snapshot.cropRight),
            height: h * (1 - snapshot.cropTop - snapshot.cropBottom)
        )
        ctx.clip(to: cropRect)

        // Move to center + offset, then scale, then rotate
        ctx.translateBy(x: w / 2 + offsetX, y: h / 2 + offsetY)
        ctx.scaleBy(x: snapshot.videoScale, y: snapshot.videoScale)
        let rad = CGFloat(snapshot.videoRotation * .pi / 180)
        ctx.rotate(by: rad)

        let rect = CGRect(x: -fittedW / 2, y: -fittedH / 2, width: fittedW, height: fittedH)
        drawCGImage(image, in: rect, context: ctx)

        ctx.restoreGState()
    }

    /// Draw a CGImage right-side-up in a flipped context.
    nonisolated private static func drawCGImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.origin.x, y: rect.origin.y + rect.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    // MARK: - MIDI Bars

    nonisolated private static func drawMidiBars(
        in ctx: CGContext, snapshot: ExportSnapshot, time: Double, w: CGFloat, h: CGFloat
    ) {
        guard let midiData = snapshot.midiData, midiData.duration > 0 else { return }

        let midiTime = computeMidiTime(snapshot: snapshot, videoTime: time)

        let tl = CGPoint(x: snapshot.pianoTopLeft.x * w, y: snapshot.pianoTopLeft.y * h)
        let tr = CGPoint(x: snapshot.pianoTopRight.x * w, y: snapshot.pianoTopRight.y * h)

        let whites = whiteNotes(low: snapshot.pianoLowNote, high: snapshot.pianoHighNote)
        let whiteIndexMap = Dictionary(uniqueKeysWithValues: whites.enumerated().map { ($1, $0) })
        let edges = effectiveEdges(snapshot: snapshot, whiteCount: whites.count)

        let dx = tr.x - tl.x
        let dy = tr.y - tl.y
        let lineLen = hypot(dx, dy)
        guard lineLen > 1 else { return }

        // In flipped context: Y increases downward. "Up" toward top = negative Y.
        var upX = -dy / lineLen
        var upY = dx / lineLen
        if upY > 0 { upX = -upX; upY = -upY }

        let midY = (tl.y + tr.y) / 2
        let spawnDist: CGFloat = abs(upY) > 0.001 ? abs(midY / upY) : midY
        guard spawnDist > 1 else { return }

        let barLeadTime: Double = 2.0
        let barMinHeight: CGFloat = 8
        let speed = spawnDist / CGFloat(barLeadTime)
        let cr = CGFloat(snapshot.barConfig.cornerRadius)
        let blackKeyWidthRatio: Double = 0.55
        let whiteBarWidthRatio: Double = 0.6

        let rightX = dx / lineLen
        let rightY = dy / lineLen

        let barColor = CGColor(
            red: CGFloat(snapshot.barConfig.colorRed),
            green: CGFloat(snapshot.barConfig.colorGreen),
            blue: CGFloat(snapshot.barConfig.colorBlue),
            alpha: 0.8
        )
        ctx.setFillColor(barColor)

        for note in midiData.notes {
            let start = note.startTime
            let dur = note.duration
            let pitch = Int(note.pitch)
            let noteH = max(barMinHeight, CGFloat(dur) * speed)
            let effectiveEnd = start + max(dur, Double(noteH / speed))

            guard midiTime >= start - barLeadTime, midiTime <= effectiveEnd else { continue }
            guard pitch >= snapshot.pianoLowNote, pitch <= snapshot.pianoHighNote else { continue }

            let lf: Double, rf: Double
            if isBlackKey(pitch) {
                let fracs = blackKeyFracs(note: pitch, whiteIndexMap: whiteIndexMap, edges: edges, ratio: blackKeyWidthRatio)
                guard fracs.0 < fracs.1 else { continue }
                (lf, rf) = fracs
            } else {
                guard let idx = whiteIndexMap[pitch] else { continue }
                let kl = edges[idx]; let kr = edges[idx + 1]
                let inset = (kr - kl) * (1 - whiteBarWidthRatio) / 2
                lf = kl + inset; rf = kr - inset
            }

            let pL = lerpPt(tl, tr, t: CGFloat(lf))
            let pR = lerpPt(tl, tr, t: CGFloat(rf))

            let perpOff: CGFloat, curH: CGFloat
            if midiTime < start {
                let progress = CGFloat((midiTime - (start - barLeadTime)) / barLeadTime)
                perpOff = spawnDist * (1 - progress)
                curH = noteH
            } else {
                let elapsed = CGFloat(midiTime - start)
                perpOff = 0
                curH = max(0, noteH - speed * elapsed)
            }
            guard curH > 0.5 else { continue }

            let barWidth = hypot(pR.x - pL.x, pR.y - pL.y)
            guard barWidth > 0.5 else { continue }

            let originX = pL.x + perpOff * upX
            let originY = pL.y + perpOff * upY

            let clampedCR = min(cr, barWidth / 2, curH / 2)
            let localRect = CGRect(x: 0, y: 0, width: barWidth, height: curH)

            var xform = CGAffineTransform(
                a: rightX, b: rightY,
                c: upX, d: upY,
                tx: originX, ty: originY
            )
            let path = CGPath(roundedRect: localRect, cornerWidth: clampedCR, cornerHeight: clampedCR, transform: &xform)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.setFillColor(barColor)
        }
    }

    // MARK: - Particle System

    nonisolated private static func emitParticlesForFrame(
        snapshot: ExportSnapshot, midiTime: Double,
        particles: inout [ExportParticle],
        previouslyActiveNotes: inout Set<UInt8>,
        lastSustainedEmitTime: inout Double,
        previousMidiTime: inout Double,
        w: CGFloat, h: CGFloat
    ) {
        guard snapshot.particleConfig.enabled else {
            previouslyActiveNotes = []
            previousMidiTime = midiTime
            return
        }
        guard let midiData = snapshot.midiData, midiData.duration > 0 else { return }

        let currentActive: Set<UInt8> = Set(midiData.notes.filter {
            midiTime >= $0.startTime && midiTime < $0.startTime + $0.duration
        }.map(\.pitch))

        let newHits = currentActive.subtracting(previouslyActiveNotes)

        var missedNotes: Set<UInt8> = []
        if previousMidiTime > 0, previousMidiTime < midiTime {
            missedNotes = Set(midiData.notes.filter {
                $0.startTime >= previousMidiTime &&
                $0.startTime + $0.duration <= midiTime &&
                !currentActive.contains($0.pitch)
            }.map(\.pitch))
        }
        let prevTime = previousMidiTime
        previousMidiTime = midiTime

        let sustInterval = snapshot.particleConfig.sustainedEmitInterval
        let shouldEmitSustained = sustInterval > 0 && (midiTime - lastSustainedEmitTime) >= sustInterval
        if shouldEmitSustained { lastSustainedEmitTime = midiTime }
        previouslyActiveNotes = currentActive

        var notesToEmit = shouldEmitSustained ? currentActive : newHits
        notesToEmit.formUnion(missedNotes)
        guard !notesToEmit.isEmpty else { return }

        let config = snapshot.particleConfig
        let whites = whiteNotes(low: snapshot.pianoLowNote, high: snapshot.pianoHighNote)
        let whiteIndexMap = Dictionary(uniqueKeysWithValues: whites.enumerated().map { ($1, $0) })
        let edges = effectiveEdges(snapshot: snapshot, whiteCount: whites.count)
        let blackKeyWidthRatio: Double = 0.55

        for pitch in notesToEmit {
            guard let fraction = keyFractionOnTopEdge(
                pitch: Int(pitch), edges: edges, whiteIndexMap: whiteIndexMap, blackKeyWidthRatio: blackKeyWidthRatio
            ) else { continue }

            let tlPt = CGPoint(x: snapshot.pianoTopLeft.x * w, y: snapshot.pianoTopLeft.y * h)
            let trPt = CGPoint(x: snapshot.pianoTopRight.x * w, y: snapshot.pianoTopRight.y * h)
            let emitPos = lerpPt(tlPt, trPt, t: fraction)

            let velocity: CGFloat
            let noteDuration: Double
            if let note = midiData.notes.first(where: {
                $0.pitch == pitch && midiTime >= $0.startTime && midiTime < $0.startTime + $0.duration
            }) {
                velocity = CGFloat(note.velocity) / 127.0
                noteDuration = note.duration
            } else if let note = midiData.notes.first(where: {
                $0.pitch == pitch &&
                $0.startTime >= prevTime &&
                $0.startTime + $0.duration <= midiTime
            }) {
                velocity = CGFloat(note.velocity) / 127.0
                noteDuration = note.duration
            } else {
                velocity = 0.8; noteDuration = 0
            }

            let (cr, cg, cb): (CGFloat, CGFloat, CGFloat)
            if config.useNoteColor {
                cr = CGFloat(snapshot.barConfig.colorRed)
                cg = CGFloat(snapshot.barConfig.colorGreen)
                cb = CGFloat(snapshot.barConfig.colorBlue)
            } else {
                cr = CGFloat(config.particleColorRed)
                cg = CGFloat(config.particleColorGreen)
                cb = CGFloat(config.particleColorBlue)
            }

            let velScale = max(0.3, velocity)
            let popFactor = 1 + Double(velocity) * (config.loudNotePopMultiplier - 1)
            let particleFactor = 1 + Double(velocity) * (config.loudNoteParticleMultiplier - 1)
            let durationCap = min(noteDuration, 2.0)
            let swirlFactor = 1 + (durationCap / 2.0) * (config.longNoteSwirlMultiplier - 1)
            _ = swirlFactor

            let count = Int(Double(config.numToEmit) * Double(velScale) * particleFactor)
            for _ in 0..<count {
                let angleCenter = config.emissionAngle * .pi / 180
                let angleRange = config.emissionAngleRange * .pi / 180
                let angle = angleCenter + Double.random(in: -angleRange / 2 ... angleRange / 2)

                let spd = (config.speed + Double.random(in: -config.speedRange / 2 ... config.speedRange / 2))
                    * Double(velScale) * popFactor

                let px = emitPos.x + CGFloat.random(in: -6 ... 6)
                let py = emitPos.y

                // In the flipped context, Y increases downward. Emission angle 90° = upward = negative Y.
                let pvx = CGFloat(spd * cos(angle))
                let pvy = CGFloat(-spd * sin(angle))

                let lifetime = CGFloat(config.lifetime * Double(velScale))
                    + CGFloat.random(in: CGFloat(-config.lifetimeRange / 2) ... CGFloat(config.lifetimeRange / 2))
                let pScale = CGFloat(config.scale * popFactor)
                    + CGFloat.random(in: CGFloat(-config.scaleRange / 2) ... CGFloat(config.scaleRange / 2))
                let pAlpha = min(1, max(0, CGFloat(config.alpha * Double(velScale))
                    + CGFloat.random(in: CGFloat(-config.alphaRange / 2) ... CGFloat(config.alphaRange / 2))))

                particles.append(ExportParticle(
                    x: px, y: py,
                    vx: pvx, vy: pvy,
                    age: 0, maxAge: max(0.1, lifetime),
                    scale: max(0.001, pScale), scaleSpeed: CGFloat(config.scaleSpeed),
                    alpha: pAlpha, alphaSpeed: CGFloat(config.alphaSpeed),
                    r: cr, g: cg, b: cb
                ))
            }
        }
    }

    nonisolated private static func updateParticles(
        _ particles: inout [ExportParticle], dt: CGFloat, config: ParticleConfiguration
    ) {
        for i in particles.indices.reversed() {
            particles[i].age += dt
            particles[i].x += particles[i].vx * dt
            particles[i].y += particles[i].vy * dt
            particles[i].vx += CGFloat(config.xAcceleration) * dt
            // yAcceleration is "up" in SpriteKit; in flipped context up = negative Y
            particles[i].vy -= CGFloat(config.yAcceleration) * dt
            particles[i].scale += particles[i].scaleSpeed * dt
            particles[i].alpha += particles[i].alphaSpeed * dt
            if !particles[i].isAlive {
                particles.remove(at: i)
            }
        }
    }

    nonisolated private static func drawParticles(
        _ particles: [ExportParticle], in ctx: CGContext, w: CGFloat, h: CGFloat
    ) {
        guard !particles.isEmpty else { return }
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)

        // Match SpriteKit: scale is a multiplier of texture size (default texture = 32px); use half for radius.
        let textureRadius: CGFloat = 16
        for p in particles where p.alpha > 0.005 && p.scale > 0.001 {
            let radius = max(1, textureRadius * p.scale)
            let center = CGPoint(x: p.x, y: p.y)
            let a = min(1, max(0, p.alpha))

            let components: [CGFloat] = [
                p.r, p.g, p.b, a,
                p.r, p.g, p.b, a * 0.4,
                p.r, p.g, p.b, 0,
            ]
            let locations: [CGFloat] = [0, 0.35, 1]
            guard let gradient = CGGradient(
                colorSpace: colorSpace, colorComponents: components, locations: locations, count: 3
            ) else { continue }

            ctx.saveGState()
            ctx.clip(to: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
            ctx.restoreGState()
        }

        ctx.restoreGState()
    }

    // MARK: - Text Overlays

    nonisolated private static func drawTextOverlays(
        in ctx: CGContext, snapshot: ExportSnapshot, videoTime: Double, videoDuration: Double, w: CGFloat, h: CGFloat
    ) {
        guard !snapshot.textOverlays.isEmpty else { return }

        let videoPercent = videoDuration > 0 ? (videoTime / videoDuration) * 100.0 : 0
        let currentVideoTime = videoDuration * (videoPercent / 100.0)

        for item in snapshot.textOverlays {
            let opacity = textOpacity(for: item, at: currentVideoTime, snapshot: snapshot)
            guard opacity > 0.01 else { continue }

            let fontSize = CGFloat(item.fontSize) * (w / max(1, snapshot.canvasDisplaySize.width))
            let nsFont: NSFont
            if snapshot.globalTextFontName.isEmpty {
                nsFont = NSFont.systemFont(ofSize: fontSize, weight: .medium)
            } else {
                nsFont = NSFont(name: snapshot.globalTextFontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: .medium)
            }

            let nsColor = NSColor(
                red: CGFloat(item.colorRed),
                green: CGFloat(item.colorGreen),
                blue: CGFloat(item.colorBlue),
                alpha: CGFloat(opacity)
            )
            let attrs: [NSAttributedString.Key: Any] = [
                .font: nsFont,
                .foregroundColor: nsColor,
            ]
            let attrString = NSAttributedString(string: item.text, attributes: attrs)
            let line = CTLineCreateWithAttributedString(attrString)

            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

            let centerX = w * CGFloat(item.positionX)
            let centerY = h * CGFloat(item.positionY)

            // Un-flip for Core Text drawing
            ctx.saveGState()
            ctx.translateBy(x: 0, y: h)
            ctx.scaleBy(x: 1, y: -1)
            let cgY = h - centerY
            let baselineX = centerX - lineWidth / 2
            let baselineY = cgY - (ascent - descent) / 2
            ctx.textPosition = CGPoint(x: baselineX, y: baselineY)
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
    }

    nonisolated private static func textOpacity(
        for item: TextOverlayItem, at t: Double, snapshot: ExportSnapshot
    ) -> Double {
        let fadeInAt: Double, fadeInDuration: Double, fadeOutAt: Double, fadeOutDuration: Double
        if item.fadeInOutWithOthers {
            fadeInAt = snapshot.globalTextFadeInAt
            fadeInDuration = snapshot.globalTextFadeInDuration
            fadeOutAt = snapshot.globalTextFadeOutAt
            fadeOutDuration = snapshot.globalTextFadeOutDuration
        } else {
            fadeInAt = item.fadeInAt
            fadeInDuration = item.fadeInDuration
            fadeOutAt = item.fadeOutAt
            fadeOutDuration = item.fadeOutDuration
        }
        if t < fadeInAt - fadeInDuration { return 0 }
        if t < fadeInAt {
            let progress = fadeInDuration > 0 ? (t - (fadeInAt - fadeInDuration)) / fadeInDuration : 1
            return min(1, max(0, progress))
        }
        if fadeOutAt > 0 && t >= fadeOutAt {
            if t >= fadeOutAt + fadeOutDuration { return 0 }
            let progress = fadeOutDuration > 0 ? (t - fadeOutAt) / fadeOutDuration : 1
            return 1 - min(1, max(0, progress))
        }
        return 1
    }

    // MARK: - Helpers

    nonisolated private static func computeMidiTime(snapshot: ExportSnapshot, videoTime: Double) -> Double {
        guard let midiData = snapshot.midiData, midiData.duration > 0 else { return 0 }
        let midiStartTime = midiData.duration * max(0, min(1, snapshot.midiStartPercent / 100.0))
        let raw = midiStartTime + videoTime
        return max(0, min(midiData.duration, raw))
    }

    nonisolated private static func effectiveEdges(snapshot: ExportSnapshot, whiteCount: Int) -> [Double] {
        if snapshot.pianoWhiteKeyEdges.count == whiteCount + 1 {
            return snapshot.pianoWhiteKeyEdges
        }
        return defaultPianoEdges(whiteKeyCount: whiteCount)
    }

    nonisolated private static func blackKeyFracs(
        note: Int, whiteIndexMap: [Int: Int], edges: [Double], ratio: Double
    ) -> (Double, Double) {
        guard let leftIdx = whiteIndexMap[note - 1], leftIdx + 2 < edges.count else { return (0, 0) }
        let boundary = edges[leftIdx + 1]
        let leftWidth = edges[leftIdx + 1] - edges[leftIdx]
        let rightWidth = edges[leftIdx + 2] - edges[leftIdx + 1]
        let avgWidth = (leftWidth + rightWidth) / 2
        let bw = avgWidth * ratio
        return (boundary - bw / 2, boundary + bw / 2)
    }

    nonisolated private static func lerpPt(_ a: CGPoint, _ b: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
