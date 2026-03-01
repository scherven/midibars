import SwiftUI
import AVFoundation

@MainActor
class ProjectState: ObservableObject {
    @Published var videoURL: URL?
    @Published var audioURL: URL?
    @Published var midiURL: URL?

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

    private var playbackTimer: Timer?

    @Published var waveformSamples: [Float] = []
    @Published var isLoadingWaveform = false

    @Published var midiData: MIDIData?
    @Published var isLoadingMIDI = false

    let canvasAspectRatio: CGFloat = 16.0 / 9.0

    func loadVideo(url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        videoURL = url
        let item = AVPlayerItem(url: url)
        if let player {
            player.replaceCurrentItem(with: item)
        } else {
            player = AVPlayer(playerItem: item)
        }
        isPlaying = false
    }

    func loadAudio(url: URL) {
        _ = url.startAccessingSecurityScopedResource()
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
                let clampedPercent = min(max(audioStartPercent, 0), 100)
                audioPlayer.currentTime = audioPlayer.duration * (clampedPercent / 100.0)
                audioPlayer.play()
            }
            startPlaybackTimer()
        }
        isPlaying.toggle()
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
        guard let audioPlayer, audioPlayer.duration > 0 else {
            playbackPercent = 0
            return
        }
        playbackPercent = (audioPlayer.currentTime / audioPlayer.duration) * 100.0

        if !audioPlayer.isPlaying && isPlaying {
            player?.pause()
            stopPlaybackTimer()
            isPlaying = false
        }
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
}
