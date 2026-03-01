import SwiftUI
import AVFoundation
import SpriteKit

@MainActor
class ProjectState: ObservableObject {
    @Published var videoURL: URL?
    @Published var audioURL: URL?
    @Published var midiURL: URL?

    var videoBookmark: Data?
    var audioBookmark: Data?
    var midiBookmark: Data?

    @Published var videoOffset: CGSize = .zero
    @Published var videoScale: CGFloat = 1.0
    @Published var videoRotation: Double = 0

    @Published var cropTop: CGFloat = 0
    @Published var cropBottom: CGFloat = 0
    @Published var cropLeft: CGFloat = 0
    @Published var cropRight: CGFloat = 0

    @Published var player: AVPlayer?
    @Published var isPlaying = false

    @Published var audioPlayer: AVAudioPlayer?
    @Published var audioStartPercent: Double = 0.0
    @Published var playbackPercent: Double = 0.0

    @Published var midiStartPercent: Double = 0.0
    @Published var midiPlaybackPercent: Double = 0.0

    @Published var videoPercent: Double = 0.0
    @Published var videoDuration: Double = 0
    @Published var isSeeking = false

    private var playbackTimer: Timer?

    @Published var waveformSamples: [Float] = []
    @Published var isLoadingWaveform = false

    @Published var midiData: MIDIData?
    @Published var isLoadingMIDI = false

    @Published var showPianoOverlay: Bool = false
    @Published var isSettingPiano: Bool = false
    @Published var isAdjustingKeys: Bool = false
    @Published var pianoTopLeft: CGPoint = CGPoint(x: 0.1, y: 0.55)
    @Published var pianoTopRight: CGPoint = CGPoint(x: 0.9, y: 0.55)
    @Published var pianoBottomLeft: CGPoint = CGPoint(x: 0.05, y: 0.95)
    @Published var pianoBottomRight: CGPoint = CGPoint(x: 0.95, y: 0.95)
    @Published var pianoLowNote: Int = 21
    @Published var pianoHighNote: Int = 108
    @Published var pianoWhiteKeyEdges: [Double] = []
    @Published var activeMIDINotes: Set<UInt8> = []

    @Published var barConfig = BarConfiguration()

    // MARK: - Particles

    @Published var particleConfig = ParticleConfiguration()

    // MARK: - Text overlays (titles)

    @Published var textOverlays: [TextOverlayItem] = []
    @Published var selectedTextOverlayID: UUID?
    let particleScene = PianoParticleScene()
    private var previouslyActiveNotes: Set<UInt8> = []
    private let blackKeyWidthRatio: Double = 0.55

    let canvasAspectRatio: CGFloat = 16.0 / 9.0

    var currentTimeString: String {
        formatTime(videoDuration * (videoPercent / 100.0))
    }

    var durationString: String {
        formatTime(videoDuration)
    }

    // MARK: - Media Loading

    func loadVideo(url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        videoBookmark = createBookmark(for: url)
        setupVideo(url: url)
    }

    func loadAudio(url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        audioBookmark = createBookmark(for: url)
        setupAudio(url: url)
    }

    func loadMIDI(url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        midiBookmark = createBookmark(for: url)
        setupMIDI(url: url)
    }

    private func setupVideo(url: URL) {
        videoURL = url
        let item = AVPlayerItem(url: url)
        if let player {
            player.replaceCurrentItem(with: item)
        } else {
            player = AVPlayer(playerItem: item)
        }
        isPlaying = false
        videoPercent = 0
        videoDuration = 0

        Task {
            let duration = try? await item.asset.load(.duration)
            if let duration {
                let seconds = CMTimeGetSeconds(duration)
                if seconds.isFinite { self.videoDuration = seconds }
            }
        }
    }

    private func setupAudio(url: URL) {
        audioURL = url
        isLoadingWaveform = true
        waveformSamples = []

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
        } catch {
            audioPlayer = nil
        }

        let expectedURL = url
        Task.detached {
            let samples = await WaveformExtractor.loadSamples(from: expectedURL)
            await MainActor.run { [weak self] in
                guard let self, self.audioURL == expectedURL else { return }
                self.waveformSamples = samples
                self.isLoadingWaveform = false
            }
        }
    }

    private func setupMIDI(url: URL) {
        midiURL = url
        isLoadingMIDI = true
        midiData = nil

        let expectedURL = url
        Task.detached {
            let parsed = MIDIParser.parse(from: expectedURL)
            await MainActor.run { [weak self] in
                guard let self, self.midiURL == expectedURL else { return }
                self.midiData = parsed
                self.isLoadingMIDI = false
            }
        }
    }

    // MARK: - Playback

    func togglePlayback() {
        guard player != nil || audioPlayer != nil else { return }

        if isPlaying {
            player?.pause()
            audioPlayer?.pause()
            stopPlaybackTimer()
        } else {
            player?.isMuted = true
            player?.play()
            if let audioPlayer, audioPlayer.duration > 0 {
                syncAudioToVideo()
                audioPlayer.play()
            }
            startPlaybackTimer()
        }
        isPlaying.toggle()
    }

    func beginSeeking() {
        isSeeking = true
        if isPlaying {
            player?.pause()
            audioPlayer?.pause()
        }
    }

    func scrubVideo(to percent: Double) {
        guard let player, let item = player.currentItem else { return }
        let duration = CMTimeGetSeconds(item.duration)
        guard duration.isFinite && duration > 0 else { return }
        let target = CMTime(seconds: duration * (percent / 100.0), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func endSeeking() {
        isSeeking = false
        seekVideo(to: videoPercent)
        if isPlaying {
            player?.isMuted = true
            player?.play()
            if let audioPlayer, audioPlayer.duration > 0 {
                audioPlayer.play()
            }
        }
    }

    func seekVideo(to percent: Double) {
        guard let player, let item = player.currentItem else { return }
        let duration = CMTimeGetSeconds(item.duration)
        guard duration.isFinite && duration > 0 else { return }
        let target = CMTime(seconds: duration * (percent / 100.0), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        syncAudioToVideo()
    }

    private func syncAudioToVideo() {
        guard let audioPlayer, audioPlayer.duration > 0 else { return }
        let audioStartTime = audioPlayer.duration * (clampedPercent(audioStartPercent) / 100.0)

        var videoCurrentTime: Double = 0
        if let player, let item = player.currentItem {
            let d = CMTimeGetSeconds(item.duration)
            if d.isFinite && d > 0 {
                videoCurrentTime = CMTimeGetSeconds(player.currentTime())
            }
        }

        audioPlayer.currentTime = min(max(audioStartTime + videoCurrentTime, 0), audioPlayer.duration)
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePlaybackPosition()
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func updatePlaybackPosition() {
        if !isSeeking, let player, let item = player.currentItem {
            let duration = CMTimeGetSeconds(item.duration)
            if duration.isFinite && duration > 0 {
                videoDuration = duration
                let current = CMTimeGetSeconds(player.currentTime())
                videoPercent = (current / duration) * 100.0
            }
        }

        if let audioPlayer, audioPlayer.duration > 0 {
            playbackPercent = (audioPlayer.currentTime / audioPlayer.duration) * 100.0
            if !audioPlayer.isPlaying && isPlaying {
                player?.pause()
                stopPlaybackTimer()
                isPlaying = false
            }
        } else {
            playbackPercent = 0
        }

        if let midiData, midiData.duration > 0 {
            var videoCurrentTime: Double = 0
            if let player, let item = player.currentItem {
                let d = CMTimeGetSeconds(item.duration)
                if d.isFinite && d > 0 {
                    videoCurrentTime = CMTimeGetSeconds(player.currentTime())
                }
            }
            let midiStartTime = midiData.duration * (clampedPercent(midiStartPercent) / 100.0)
            midiPlaybackPercent = clampedPercent(((midiStartTime + videoCurrentTime) / midiData.duration) * 100.0)

            let currentTime = midiData.duration * (midiPlaybackPercent / 100.0)
            let newActive: Set<UInt8> = Set(midiData.notes.filter {
                currentTime >= $0.startTime && currentTime < $0.startTime + $0.duration
            }.map(\.pitch))

            if showPianoOverlay {
                activeMIDINotes = newActive
            } else {
                activeMIDINotes = []
            }

            emitParticlesForNewHits(newActive)
        } else {
            midiPlaybackPercent = 0
            activeMIDINotes = []
            previouslyActiveNotes = []
        }
    }

    // MARK: - Particle Hit Detection

    private func emitParticlesForNewHits(_ currentActive: Set<UInt8>) {
        guard particleConfig.enabled else {
            previouslyActiveNotes = currentActive
            return
        }

        let newHits = currentActive.subtracting(previouslyActiveNotes)
        previouslyActiveNotes = currentActive

        guard !newHits.isEmpty else { return }

        particleScene.particleConfig = particleConfig

        let whites = whiteNotes(low: pianoLowNote, high: pianoHighNote)
        let whiteIndexMap = Dictionary(uniqueKeysWithValues: whites.enumerated().map { ($1, $0) })
        let edges = effectiveEdgesForParticles(whiteCount: whites.count)

        let currentTime = midiData?.duration ?? 0 * (midiPlaybackPercent / 100.0)

        for pitch in newHits {
            guard let fraction = keyFractionOnTopEdge(
                pitch: Int(pitch),
                edges: edges,
                whiteIndexMap: whiteIndexMap,
                blackKeyWidthRatio: blackKeyWidthRatio
            ) else { continue }

            let normalizedPoint = pianoTopEdgePoint(
                fraction: fraction,
                topLeft: pianoTopLeft,
                topRight: pianoTopRight
            )

            let velocity: CGFloat
            if let note = midiData?.notes.first(where: {
                $0.pitch == pitch &&
                currentTime >= $0.startTime &&
                currentTime < $0.startTime + $0.duration
            }) {
                velocity = CGFloat(note.velocity) / 127.0
            } else {
                velocity = 0.8
            }

            let color: NSColor = .red
            particleScene.emitParticles(atNormalized: normalizedPoint, color: color, velocity: velocity)
        }
    }

    private func effectiveEdgesForParticles(whiteCount: Int) -> [Double] {
        if pianoWhiteKeyEdges.count == whiteCount + 1 {
            return pianoWhiteKeyEdges
        }
        return defaultPianoEdges(whiteKeyCount: whiteCount)
    }

    func resetTransform() {
        videoOffset = .zero
        videoScale = 1.0
        videoRotation = 0
        cropTop = 0
        cropBottom = 0
        cropLeft = 0
        cropRight = 0
    }

    func ensurePianoEdgesPopulated() {
        let count = whiteNotes(low: pianoLowNote, high: pianoHighNote).count
        guard count > 0 else { return }
        if pianoWhiteKeyEdges.count != count + 1 {
            pianoWhiteKeyEdges = defaultPianoEdges(whiteKeyCount: count)
        }
    }

    // MARK: - Project Persistence

    func save(into config: inout ProjectConfig) {
        config.videoBookmark = videoBookmark
        config.audioBookmark = audioBookmark
        config.midiBookmark = midiBookmark
        config.videoPath = videoURL?.path
        config.audioPath = audioURL?.path
        config.midiPath = midiURL?.path
        config.videoOffsetWidth = Double(videoOffset.width)
        config.videoOffsetHeight = Double(videoOffset.height)
        config.videoScale = Double(videoScale)
        config.videoRotation = videoRotation
        config.cropTop = Double(cropTop)
        config.cropBottom = Double(cropBottom)
        config.cropLeft = Double(cropLeft)
        config.cropRight = Double(cropRight)
        config.audioStartPercent = audioStartPercent
        config.midiStartPercent = midiStartPercent

        config.pianoConfig = PianoConfig(
            topLeftX: pianoTopLeft.x, topLeftY: pianoTopLeft.y,
            topRightX: pianoTopRight.x, topRightY: pianoTopRight.y,
            bottomLeftX: pianoBottomLeft.x, bottomLeftY: pianoBottomLeft.y,
            bottomRightX: pianoBottomRight.x, bottomRightY: pianoBottomRight.y,
            lowNote: pianoLowNote, highNote: pianoHighNote,
            showOverlay: showPianoOverlay,
            keyEdges: pianoWhiteKeyEdges.isEmpty ? nil : pianoWhiteKeyEdges
        )
        config.particleConfig = particleConfig
        config.barConfig = barConfig
        config.textOverlays = textOverlays.isEmpty ? nil : textOverlays
    }

    func restore(from config: ProjectConfig) {
        reset()

        videoOffset = CGSize(width: config.videoOffsetWidth, height: config.videoOffsetHeight)
        videoScale = CGFloat(config.videoScale)
        videoRotation = config.videoRotation
        cropTop = CGFloat(config.cropTop)
        cropBottom = CGFloat(config.cropBottom)
        cropLeft = CGFloat(config.cropLeft)
        cropRight = CGFloat(config.cropRight)
        audioStartPercent = config.audioStartPercent
        midiStartPercent = config.midiStartPercent

        if let piano = config.pianoConfig {
            pianoTopLeft = CGPoint(x: piano.topLeftX, y: piano.topLeftY)
            pianoTopRight = CGPoint(x: piano.topRightX, y: piano.topRightY)
            pianoBottomLeft = CGPoint(x: piano.bottomLeftX, y: piano.bottomLeftY)
            pianoBottomRight = CGPoint(x: piano.bottomRightX, y: piano.bottomRightY)
            pianoLowNote = piano.lowNote
            pianoHighNote = piano.highNote
            showPianoOverlay = piano.showOverlay
            pianoWhiteKeyEdges = piano.keyEdges ?? []
        }

        if let particles = config.particleConfig {
            particleConfig = particles
        }
        if let bar = config.barConfig {
            barConfig = bar
        }
        if let overlays = config.textOverlays {
            textOverlays = overlays
        }

        restoreFile(bookmark: config.videoBookmark, path: config.videoPath) { url, bookmark in
            self.videoBookmark = bookmark.isEmpty ? nil : bookmark
            self.setupVideo(url: url)
        }
        restoreFile(bookmark: config.audioBookmark, path: config.audioPath) { url, bookmark in
            self.audioBookmark = bookmark.isEmpty ? nil : bookmark
            self.setupAudio(url: url)
        }
        restoreFile(bookmark: config.midiBookmark, path: config.midiPath) { url, bookmark in
            self.midiBookmark = bookmark.isEmpty ? nil : bookmark
            self.setupMIDI(url: url)
        }
    }

    func reset() {
        if isPlaying {
            player?.pause()
            audioPlayer?.pause()
            stopPlaybackTimer()
            isPlaying = false
        }

        player = nil
        audioPlayer = nil

        videoURL = nil
        audioURL = nil
        midiURL = nil

        videoBookmark = nil
        audioBookmark = nil
        midiBookmark = nil

        videoOffset = .zero
        videoScale = 1.0
        videoRotation = 0

        cropTop = 0
        cropBottom = 0
        cropLeft = 0
        cropRight = 0

        audioStartPercent = 0
        midiStartPercent = 0
        playbackPercent = 0
        midiPlaybackPercent = 0
        videoPercent = 0
        videoDuration = 0
        isSeeking = false

        waveformSamples = []
        isLoadingWaveform = false
        midiData = nil
        isLoadingMIDI = false

        showPianoOverlay = false
        isSettingPiano = false
        isAdjustingKeys = false
        pianoTopLeft = CGPoint(x: 0.1, y: 0.55)
        pianoTopRight = CGPoint(x: 0.9, y: 0.55)
        pianoBottomLeft = CGPoint(x: 0.05, y: 0.95)
        pianoBottomRight = CGPoint(x: 0.95, y: 0.95)
        pianoLowNote = 21
        pianoHighNote = 108
        pianoWhiteKeyEdges = []
        activeMIDINotes = []
        previouslyActiveNotes = []
        particleScene.removeAllParticles()
        barConfig = BarConfiguration()
        textOverlays = []
        selectedTextOverlayID = nil
    }

    // MARK: - Bookmark Helpers

    private func createBookmark(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            do {
                return try url.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch {
                return nil
            }
        }
    }

    private func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            _ = url.startAccessingSecurityScopedResource()
            if isStale {
                videoBookmark = createBookmark(for: url)
            }
            return url
        } catch {
            do {
                return try URL(
                    resolvingBookmarkData: data,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
            } catch {
                return nil
            }
        }
    }

    private func restoreFile(bookmark: Data?, path: String?, load: (URL, Data) -> Void) {
        if let bookmark, let url = resolveBookmark(bookmark) {
            load(url, bookmark)
            return
        }
        if let path {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.isReadableFile(atPath: path) {
                load(url, Data())
                return
            }
        }
    }
}
