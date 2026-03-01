import SwiftUI
import AVFoundation

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

    let canvasAspectRatio: CGFloat = 16.0 / 9.0

    var currentTimeString: String {
        formatTime(videoDuration * (videoPercent / 100.0))
    }

    var durationString: String {
        formatTime(videoDuration)
    }

    // MARK: - Media Loading

    func loadVideo(url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        print("[midibars] loadVideo: startAccessing=\(accessed) url=\(url.path)")
        videoBookmark = createBookmark(for: url)
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

    func loadAudio(url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        print("[midibars] loadAudio: startAccessing=\(accessed) url=\(url.path)")
        audioBookmark = createBookmark(for: url)
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

    func loadMIDI(url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        print("[midibars] loadMIDI: startAccessing=\(accessed) url=\(url.path)")
        midiBookmark = createBookmark(for: url)
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
        let audioStartTime = audioPlayer.duration * (min(max(audioStartPercent, 0), 100) / 100.0)

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
            let midiStartTime = midiData.duration * (min(max(midiStartPercent, 0), 100) / 100.0)
            midiPlaybackPercent = ((midiStartTime + videoCurrentTime) / midiData.duration) * 100.0
            midiPlaybackPercent = min(max(midiPlaybackPercent, 0), 100)

            if showPianoOverlay {
                let currentTime = midiData.duration * (midiPlaybackPercent / 100.0)
                activeMIDINotes = Set(midiData.notes.filter {
                    currentTime >= $0.startTime && currentTime < $0.startTime + $0.duration
                }.map(\.pitch))
            } else {
                activeMIDINotes = []
            }
        } else {
            midiPlaybackPercent = 0
            activeMIDINotes = []
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
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
        let blackSet: Set<Int> = [1, 3, 6, 8, 10]
        let whiteCount = (pianoLowNote...pianoHighNote).filter { !blackSet.contains($0 % 12) }.count
        guard whiteCount > 0 else { return }
        if pianoWhiteKeyEdges.count != whiteCount + 1 {
            pianoWhiteKeyEdges = (0...whiteCount).map { Double($0) / Double(whiteCount) }
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

        print("[midibars] save: videoBookmark=\(videoBookmark?.count ?? 0) bytes, audioBookmark=\(audioBookmark?.count ?? 0) bytes, midiBookmark=\(midiBookmark?.count ?? 0) bytes")
        print("[midibars] save: videoPath=\(videoURL?.path ?? "nil"), audioPath=\(audioURL?.path ?? "nil"), midiPath=\(midiURL?.path ?? "nil")")
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

        print("[midibars] restore: videoBookmark=\(config.videoBookmark?.count ?? 0) bytes, videoPath=\(config.videoPath ?? "nil")")
        print("[midibars] restore: audioBookmark=\(config.audioBookmark?.count ?? 0) bytes, audioPath=\(config.audioPath ?? "nil")")
        print("[midibars] restore: midiBookmark=\(config.midiBookmark?.count ?? 0) bytes, midiPath=\(config.midiPath ?? "nil")")

        restoreFile(bookmark: config.videoBookmark, path: config.videoPath) { url, bookmark in
            self.loadVideoFromBookmark(url: url, bookmark: bookmark)
        }
        restoreFile(bookmark: config.audioBookmark, path: config.audioPath) { url, bookmark in
            self.loadAudioFromBookmark(url: url, bookmark: bookmark)
        }
        restoreFile(bookmark: config.midiBookmark, path: config.midiPath) { url, bookmark in
            self.loadMIDIFromBookmark(url: url, bookmark: bookmark)
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
    }

    // MARK: - Bookmark Helpers

    private func createBookmark(for url: URL) -> Data? {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            print("[midibars] bookmark created: \(bookmark.count) bytes for \(url.lastPathComponent)")
            return bookmark
        } catch {
            print("[midibars] bookmark creation FAILED for \(url.path): \(error)")
            // Fall back to a minimal bookmark without security scope
            do {
                let bookmark = try url.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                print("[midibars] minimal bookmark created: \(bookmark.count) bytes for \(url.lastPathComponent)")
                return bookmark
            } catch {
                print("[midibars] minimal bookmark also FAILED: \(error)")
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
            let accessed = url.startAccessingSecurityScopedResource()
            print("[midibars] bookmark resolved: stale=\(isStale) accessed=\(accessed) url=\(url.path)")
            if isStale {
                videoBookmark = createBookmark(for: url)
            }
            return url
        } catch {
            print("[midibars] security-scoped bookmark resolution FAILED: \(error)")
            // Try without security scope
            do {
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                print("[midibars] plain bookmark resolved: stale=\(isStale) url=\(url.path)")
                return url
            } catch {
                print("[midibars] plain bookmark resolution also FAILED: \(error)")
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
                print("[midibars] falling back to path: \(path)")
                load(url, Data())
                return
            } else {
                print("[midibars] path not readable: \(path)")
            }
        }
    }

    private func loadVideoFromBookmark(url: URL, bookmark: Data) {
        videoBookmark = bookmark.isEmpty ? nil : bookmark
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

    private func loadAudioFromBookmark(url: URL, bookmark: Data) {
        audioBookmark = bookmark.isEmpty ? nil : bookmark
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

    private func loadMIDIFromBookmark(url: URL, bookmark: Data) {
        midiBookmark = bookmark.isEmpty ? nil : bookmark
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
}
