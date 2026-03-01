import SwiftUI
import AVFoundation

@MainActor
class ProjectState: ObservableObject {
    @Published var videoURL: URL?
    @Published var audioURL: URL?
    @Published var midiURL: URL?

    @Published var videoOffset: CGSize = .zero
    @Published var videoScale: CGFloat = 1.0

    @Published var player: AVPlayer?
    @Published var isPlaying = false

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
    }

    func loadMIDI(url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        midiURL = url
    }

    func togglePlayback() {
        guard let player else { return }
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
    }
}
