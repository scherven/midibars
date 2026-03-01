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

    @Published var videoPercent: Double = 0.0
    @Published var videoDuration: Double = 0
    @Published var isSeeking = false

    private var playbackTimer: Timer?

    @Published var waveformSamples: [Float] = []
    @Published var isLoadingWaveform = false

    @Published var midiData: MIDIData?
    @Published var isLoadingMIDI = false

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
        videoBookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
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
        _ = url.startAccessingSecurityScopedResource()
        audioBookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
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
        _ = url.startAccessingSecurityScopedResource()
        midiBookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
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

    // MARK: - Project Persistence

    func save(into config: inout ProjectConfig) {
        config.videoBookmark = videoBookmark
        config.audioBookmark = audioBookmark
        config.midiBookmark = midiBookmark
        config.videoOffsetWidth = Double(videoOffset.width)
        config.videoOffsetHeight = Double(videoOffset.height)
        config.videoScale = Double(videoScale)
        config.videoRotation = videoRotation
        config.cropTop = Double(cropTop)
        config.cropBottom = Double(cropBottom)
        config.cropLeft = Double(cropLeft)
        config.cropRight = Double(cropRight)
        config.audioStartPercent = audioStartPercent
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

        if let bookmark = config.videoBookmark, let url = resolveBookmark(bookmark) {
            loadVideoFromBookmark(url: url, bookmark: bookmark)
        }
        if let bookmark = config.audioBookmark, let url = resolveBookmark(bookmark) {
            loadAudioFromBookmark(url: url, bookmark: bookmark)
        }
        if let bookmark = config.midiBookmark, let url = resolveBookmark(bookmark) {
            loadMIDIFromBookmark(url: url, bookmark: bookmark)
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
        playbackPercent = 0
        videoPercent = 0
        videoDuration = 0
        isSeeking = false

        waveformSamples = []
        isLoadingWaveform = false
        midiData = nil
        isLoadingMIDI = false
    }

    // MARK: - Bookmark Helpers

    private func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkDataOf: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    private func loadVideoFromBookmark(url: URL, bookmark: Data) {
        videoBookmark = bookmark
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
        audioBookmark = bookmark
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
        midiBookmark = bookmark
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
