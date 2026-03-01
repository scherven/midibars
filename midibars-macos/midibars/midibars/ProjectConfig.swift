import Foundation

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

@MainActor
class ProjectStore: ObservableObject {
    @Published private(set) var projects: [ProjectConfig] = []

    private let directory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = appSupport.appendingPathComponent("midibars/projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadAll()
    }

    private func loadAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" }) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        projects = files.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(ProjectConfig.self, from: data)
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func save(_ config: ProjectConfig) {
        var config = config
        config.modifiedAt = Date()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(config)
            let url = fileURL(for: config.id)
            try data.write(to: url)
            print("[midibars] ProjectStore saved \(config.name) to \(url.path) (\(data.count) bytes)")
            print("[midibars]   videoBookmark: \(config.videoBookmark?.count ?? 0) bytes, videoPath: \(config.videoPath ?? "nil")")
            print("[midibars]   audioBookmark: \(config.audioBookmark?.count ?? 0) bytes, audioPath: \(config.audioPath ?? "nil")")
            print("[midibars]   midiBookmark: \(config.midiBookmark?.count ?? 0) bytes, midiPath: \(config.midiPath ?? "nil")")
        } catch {
            print("[midibars] ProjectStore save FAILED for \(config.name): \(error)")
        }

        if let index = projects.firstIndex(where: { $0.id == config.id }) {
            projects[index] = config
        } else {
            projects.insert(config, at: 0)
        }
        projects.sort { $0.modifiedAt > $1.modifiedAt }
    }

    func delete(_ config: ProjectConfig) {
        try? FileManager.default.removeItem(at: fileURL(for: config.id))
        projects.removeAll { $0.id == config.id }
    }

    func project(for id: UUID) -> ProjectConfig? {
        projects.first { $0.id == id }
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
