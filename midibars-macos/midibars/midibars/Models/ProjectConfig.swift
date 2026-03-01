import Foundation

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
