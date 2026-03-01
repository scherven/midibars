import Foundation

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
