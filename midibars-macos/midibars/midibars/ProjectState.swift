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
        guard let player else { return }
        player.isMuted = true
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
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
