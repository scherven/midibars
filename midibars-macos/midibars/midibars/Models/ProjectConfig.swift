import Foundation

struct BarConfiguration: Codable, Equatable {
    /// Corner radius for note bars (0 = square, higher = more rounded). Stored as points; 0–20 typical.
    var cornerRadius: Double = 2.0
    var colorRed: Double = 0.4
    var colorGreen: Double = 0.5
    var colorBlue: Double = 1.0
}

struct PianoConfig: Codable {
    var topLeftX: Double
    var topLeftY: Double
    var topRightX: Double
    var topRightY: Double
    var bottomLeftX: Double
    var bottomLeftY: Double
    var bottomRightX: Double
    var bottomRightY: Double
    var lowNote: Int
    var highNote: Int
    var showOverlay: Bool
    var keyEdges: [Double]?
}

struct TextOverlayItem: Codable, Identifiable, Equatable {
    var id: UUID
    var text: String
    /// Normalized X position 0–1 (0 = left).
    var positionX: Double
    /// Normalized Y position 0–1 (0 = top).
    var positionY: Double
    var fontSize: Double
    var colorRed: Double
    var colorGreen: Double
    var colorBlue: Double
    /// Video time (seconds) when fade-in completes (text fully visible).
    var fadeInAt: Double
    /// Duration of fade-in in seconds.
    var fadeInDuration: Double
    /// Video time (seconds) when fade-out starts; 0 = no fade out.
    var fadeOutAt: Double
    /// Duration of fade-out in seconds.
    var fadeOutDuration: Double

    init(
        id: UUID = UUID(),
        text: String = "Title",
        positionX: Double = 0.5,
        positionY: Double = 0.1,
        fontSize: Double = 48,
        colorRed: Double = 1, colorGreen: Double = 1, colorBlue: Double = 1,
        fadeInAt: Double = 0, fadeInDuration: Double = 1,
        fadeOutAt: Double = 0, fadeOutDuration: Double = 1
    ) {
        self.id = id
        self.text = text
        self.positionX = positionX
        self.positionY = positionY
        self.fontSize = fontSize
        self.colorRed = colorRed
        self.colorGreen = colorGreen
        self.colorBlue = colorBlue
        self.fadeInAt = fadeInAt
        self.fadeInDuration = fadeInDuration
        self.fadeOutAt = fadeOutAt
        self.fadeOutDuration = fadeOutDuration
    }
}

struct ProjectConfig: Codable, Identifiable {
    let id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date

    var videoBookmark: Data?
    var audioBookmark: Data?
    var midiBookmark: Data?

    var videoPath: String?
    var audioPath: String?
    var midiPath: String?

    var videoOffsetWidth: Double
    var videoOffsetHeight: Double
    var videoScale: Double
    var videoRotation: Double

    var cropTop: Double
    var cropBottom: Double
    var cropLeft: Double
    var cropRight: Double

    var audioStartPercent: Double
    var midiStartPercent: Double

    var pianoConfig: PianoConfig?
    var particleConfig: ParticleConfiguration?
    var barConfig: BarConfiguration?
    var textOverlays: [TextOverlayItem]?

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.videoOffsetWidth = 0
        self.videoOffsetHeight = 0
        self.videoScale = 1.0
        self.videoRotation = 0
        self.cropTop = 0
        self.cropBottom = 0
        self.cropLeft = 0
        self.cropRight = 0
        self.audioStartPercent = 0
        self.midiStartPercent = 0
    }

    var hasVideo: Bool { videoBookmark != nil || videoPath != nil }
    var hasAudio: Bool { audioBookmark != nil || audioPath != nil }
    var hasMIDI: Bool { midiBookmark != nil || midiPath != nil }
}
